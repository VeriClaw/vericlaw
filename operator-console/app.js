const securityDefaults = [
  { control: "Default bind host", value: "127.0.0.1" },
  { control: "Public bind default", value: "false" },
  { control: "Pairing required", value: "true" },
  { control: "Empty allowlist denies all", value: "true" },
  { control: "Private network egress blocked", value: "true" },
  { control: "Observability export", value: "none" }
];

const localDataPaths = {
  releaseMetadata: "./tests/release_metadata.json",
  conformanceReport: "./tests/cross_repo_conformance_report.json"
};

const defaultGatewayUrl = "http://127.0.0.1:8787";
const storageKey = "vericlaw.operatorConsole.v2";
const maxStoredMessages = 120;
const maxStoredSessions = 12;
const chatStreamEndpoint = "/api/chat/stream";

const elements = {
  securityDefaults: document.getElementById("security-defaults"),
  todoSnapshot: document.getElementById("todo-snapshot"),
  healthSnapshot: document.getElementById("health-snapshot"),
  gatewayUrl: document.getElementById("gateway-url"),
  sessionId: document.getElementById("session-id"),
  connectButton: document.getElementById("connect-btn"),
  newSessionButton: document.getElementById("new-session-btn"),
  connectionPill: document.getElementById("connection-pill"),
  transportPill: document.getElementById("transport-pill"),
  streamingBanner: document.getElementById("streaming-banner"),
  gatewayStatus: document.getElementById("gateway-status"),
  gatewayDetail: document.getElementById("gateway-detail"),
  sessionSummary: document.getElementById("session-summary"),
  sessionDetail: document.getElementById("session-detail"),
  errorBanner: document.getElementById("error-banner"),
  errorMessage: document.getElementById("error-message"),
  clearErrorButton: document.getElementById("clear-error-btn"),
  chatHistory: document.getElementById("chat-history"),
  chatForm: document.getElementById("chat-form"),
  chatInput: document.getElementById("chat-input"),
  sendButton: document.getElementById("send-btn"),
  channelsTableBody: document.querySelector("#channels-table tbody"),
  gatewayVersion: document.getElementById("gateway-version"),
  gatewayUptime: document.getElementById("gateway-uptime"),
  gatewayProviderRequests: document.getElementById("gateway-provider-requests"),
  gatewayProviderErrors: document.getElementById("gateway-provider-errors"),
  gatewayToolCalls: document.getElementById("gateway-tool-calls"),
  renderedAt: document.getElementById("rendered-at")
};

function normalizeBaseUrl(value) {
  if (typeof value !== "string") {
    return "";
  }
  return value.trim().replace(/\/+$/, "");
}

function sanitizeSessionId(value) {
  if (typeof value !== "string") {
    return "";
  }
  return value.trim().slice(0, 128);
}

function makeSessionKey(gatewayUrl, sessionId) {
  return `${encodeURIComponent(normalizeBaseUrl(gatewayUrl))}::${encodeURIComponent(sanitizeSessionId(sessionId))}`;
}

function generateSessionId() {
  if (window.crypto && typeof window.crypto.randomUUID === "function") {
    return `browser-${window.crypto.randomUUID().slice(0, 12)}`;
  }
  return `browser-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

function sanitizeMessages(raw) {
  if (!Array.isArray(raw)) {
    return [];
  }
  return raw
    .map((message) => {
      if (!message || typeof message !== "object") {
        return null;
      }
      const role = message.role === "user" || message.role === "assistant" ? message.role : null;
      const content = typeof message.content === "string" ? message.content : "";
      if (!role || !content) {
        return null;
      }
      return {
        role,
        content,
        createdAt: typeof message.createdAt === "string" ? message.createdAt : new Date().toISOString()
      };
    })
    .filter(Boolean)
    .slice(-maxStoredMessages);
}

function sanitizeTranscripts(raw) {
  const transcripts = {};
  if (!raw || typeof raw !== "object") {
    return transcripts;
  }

  Object.values(raw).forEach((entry) => {
    if (!entry || typeof entry !== "object") {
      return;
    }
    const gatewayUrl = normalizeBaseUrl(entry.gatewayUrl);
    const sessionId = sanitizeSessionId(entry.sessionId);
    if (!gatewayUrl || !sessionId) {
      return;
    }
    const key = makeSessionKey(gatewayUrl, sessionId);
    transcripts[key] = {
      gatewayUrl,
      sessionId,
      messages: sanitizeMessages(entry.messages),
      updatedAt: typeof entry.updatedAt === "string" ? entry.updatedAt : new Date().toISOString()
    };
  });

  return transcripts;
}

function createDefaultPersistentState() {
  const gatewayUrl = defaultGatewayUrl;
  const sessionId = generateSessionId();
  const key = makeSessionKey(gatewayUrl, sessionId);
  return {
    gatewayUrl,
    sessionId,
    transcripts: {
      [key]: {
        gatewayUrl,
        sessionId,
        messages: [],
        updatedAt: new Date().toISOString()
      }
    }
  };
}

function ensureTranscript(state, gatewayUrl = state.gatewayUrl, sessionId = state.sessionId) {
  const normalizedGateway = normalizeBaseUrl(gatewayUrl) || defaultGatewayUrl;
  const normalizedSession = sanitizeSessionId(sessionId) || generateSessionId();
  const key = makeSessionKey(normalizedGateway, normalizedSession);
  if (!state.transcripts[key]) {
    state.transcripts[key] = {
      gatewayUrl: normalizedGateway,
      sessionId: normalizedSession,
      messages: [],
      updatedAt: new Date().toISOString()
    };
  }
  return state.transcripts[key];
}

function loadPersistentState() {
  try {
    const raw = window.localStorage.getItem(storageKey);
    if (!raw) {
      return createDefaultPersistentState();
    }
    const parsed = JSON.parse(raw);
    const fallback = createDefaultPersistentState();
    const state = {
      gatewayUrl: normalizeBaseUrl(parsed.gatewayUrl) || fallback.gatewayUrl,
      sessionId: sanitizeSessionId(parsed.sessionId) || fallback.sessionId,
      transcripts: sanitizeTranscripts(parsed.transcripts)
    };
    ensureTranscript(state, state.gatewayUrl, state.sessionId);
    return state;
  } catch (_error) {
    return createDefaultPersistentState();
  }
}

const persistentState = loadPersistentState();
const runtimeState = {
  isSending: false,
  lastError: "",
  connectionState: "idle",
  connectionSummary: "Gateway not checked yet.",
  connectionDetail: "Use Check gateway to confirm the local API is reachable from this browser.",
  gatewaySnapshot: null,
  pendingAssistantText: "",
  pendingStartedAt: "",
  streamMode: "buffered-sse",
  streamChunkCount: 0
};

function pruneTranscripts() {
  const entries = Object.entries(persistentState.transcripts);
  if (entries.length <= maxStoredSessions) {
    return;
  }
  entries
    .sort(([, left], [, right]) => {
      const leftTime = Date.parse(left.updatedAt || "") || 0;
      const rightTime = Date.parse(right.updatedAt || "") || 0;
      return rightTime - leftTime;
    })
    .slice(maxStoredSessions)
    .forEach(([key]) => {
      delete persistentState.transcripts[key];
    });
}

function savePersistentState() {
  pruneTranscripts();
  try {
    window.localStorage.setItem(storageKey, JSON.stringify(persistentState));
  } catch (_error) {
    // Best-effort local persistence only.
  }
}

function getActiveTranscript() {
  return ensureTranscript(persistentState);
}

function activateSessionFromInputs() {
  persistentState.gatewayUrl = normalizeBaseUrl(elements.gatewayUrl.value) || defaultGatewayUrl;
  persistentState.sessionId = sanitizeSessionId(elements.sessionId.value) || generateSessionId();
  ensureTranscript(persistentState);
  savePersistentState();
  syncInputsFromState();
}

function syncInputsFromState() {
  elements.gatewayUrl.value = persistentState.gatewayUrl;
  elements.sessionId.value = persistentState.sessionId;
}

function appendTranscriptMessage(role, content) {
  const transcript = getActiveTranscript();
  transcript.messages.push({
    role,
    content,
    createdAt: new Date().toISOString()
  });
  transcript.messages = transcript.messages.slice(-maxStoredMessages);
  transcript.updatedAt = new Date().toISOString();
  savePersistentState();
}

function clearLastError() {
  runtimeState.lastError = "";
}

function setLastError(message) {
  runtimeState.lastError = message;
}

function setConnectionState(state, summary, detail) {
  runtimeState.connectionState = state;
  runtimeState.connectionSummary = summary;
  runtimeState.connectionDetail = detail;
}

function formatTimestamp(value) {
  if (!value) {
    return "unknown time";
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  return date.toLocaleString();
}

function formatUptime(seconds) {
  if (typeof seconds !== "number" || Number.isNaN(seconds)) {
    return "unknown";
  }
  if (seconds < 60) {
    return `${seconds}s`;
  }
  const wholeSeconds = Math.floor(seconds);
  const hours = Math.floor(wholeSeconds / 3600);
  const minutes = Math.floor((wholeSeconds % 3600) / 60);
  const secs = wholeSeconds % 60;
  if (hours > 0) {
    return `${hours}h ${minutes}m ${secs}s`;
  }
  return `${minutes}m ${secs}s`;
}

function setSecurityDefaults() {
  elements.securityDefaults.textContent = "";
  securityDefaults.forEach((item) => {
    const row = document.createElement("tr");
    const controlCell = document.createElement("td");
    const valueCell = document.createElement("td");
    controlCell.textContent = item.control;
    valueCell.textContent = item.value;
    row.append(controlCell, valueCell);
    elements.securityDefaults.appendChild(row);
  });
}

function setListItems(elementId, values) {
  const list = document.getElementById(elementId);
  list.textContent = "";
  values.forEach((value) => {
    const li = document.createElement("li");
    li.textContent = value;
    list.appendChild(li);
  });
}

function normalizeLocalPath(path) {
  if (!path || typeof path !== "string") {
    return null;
  }
  return path.startsWith("./") ? path : `./${path.replace(/^\/+/, "")}`;
}

async function fetchLocal(path) {
  try {
    const response = await fetch(path, { cache: "no-store" });
    if (!response.ok) {
      return { ok: false, path, error: `HTTP ${response.status}` };
    }
    return { ok: true, path, response };
  } catch (error) {
    return { ok: false, path, error: error instanceof Error ? error.message : String(error) };
  }
}

async function loadLocalJson(path) {
  const result = await fetchLocal(path);
  if (!result.ok) {
    return result;
  }
  try {
    return { ok: true, path, data: await result.response.json() };
  } catch (error) {
    return { ok: false, path, error: error instanceof Error ? error.message : String(error) };
  }
}

function buildTodoSnapshot(releaseMetadataResult) {
  if (!releaseMetadataResult.ok) {
    return [
      `Release metadata unavailable locally (${releaseMetadataResult.path}). Run make release-check to regenerate local artifacts.`,
      `Local read error: ${releaseMetadataResult.error}`
    ];
  }

  const metadata = releaseMetadataResult.data;
  const checks = Object.entries(metadata.checks || {});
  const items = [
    `Release gate: ${metadata.gate || "unknown"} (${metadata.toolchain_mode || "unknown"} mode).`,
    `Metadata generated at: ${metadata.generated_at || "unknown"}.`
  ];

  if (checks.length === 0) {
    items.push("Release metadata contains no local check status entries.");
    return items;
  }

  checks.forEach(([check, status]) => {
    items.push(`Check ${check}: ${status}`);
  });
  return items;
}

async function buildHealthSnapshot(releaseMetadataResult) {
  const conformancePath = normalizeLocalPath(releaseMetadataResult.data?.artifacts?.conformance_report)
    || localDataPaths.conformanceReport;
  let conformanceResult = await loadLocalJson(conformancePath);
  if (!conformanceResult.ok && conformancePath !== localDataPaths.conformanceReport) {
    conformanceResult = await loadLocalJson(localDataPaths.conformanceReport);
  }

  const items = [];
  if (conformanceResult.ok) {
    const report = conformanceResult.data;
    const suites = Array.isArray(report.suites) ? report.suites : [];
    const passedSuites = suites.filter((suite) => suite.status === "pass").length;
    const gatewayDoctorSuite = suites.find((suite) => suite.suite === "gateway-doctor-startup-guard");
    items.push(`Conformance overall: ${report.overall_status || "unknown"} (${passedSuites}/${suites.length} suites passing).`);
    items.push(`Conformance generated at: ${report.generated_at || "unknown"}.`);
    if (gatewayDoctorSuite) {
      items.push(`Gateway doctor startup guard: ${gatewayDoctorSuite.status} (exit ${gatewayDoctorSuite.exit_code}).`);
    } else {
      items.push("Gateway doctor startup guard status is missing from the local conformance report.");
    }
  } else {
    items.push(`Conformance report unavailable locally (${conformanceResult.path}). Run make conformance-suite.`);
    items.push(`Local read error: ${conformanceResult.error}`);
  }

  const checksumPath = normalizeLocalPath(releaseMetadataResult.data?.artifacts?.checksum_manifest);
  if (checksumPath) {
    const checksumResult = await fetchLocal(checksumPath);
    if (checksumResult.ok) {
      items.push(`Checksum manifest available: ${checksumPath}.`);
    } else {
      items.push(`Checksum manifest missing locally (${checksumPath}). Run make release-check.`);
      items.push(`Local read error: ${checksumResult.error}`);
    }
  } else {
    items.push("Checksum manifest path is missing from local release metadata.");
  }

  return items;
}

async function renderLiveSnapshots() {
  const releaseMetadataResult = await loadLocalJson(localDataPaths.releaseMetadata);
  setListItems("todo-snapshot", buildTodoSnapshot(releaseMetadataResult));
  setListItems("health-snapshot", await buildHealthSnapshot(releaseMetadataResult));
}

async function buildResponseError(response, path) {
  let body = "";
  try {
    body = await response.text();
  } catch (_error) {
    body = "";
  }

  let message = `${path} returned HTTP ${response.status}`;
  if (body) {
    try {
      const parsed = JSON.parse(body);
      if (parsed && typeof parsed.error === "string" && parsed.error) {
        message = parsed.error;
      } else {
        message = body.trim();
      }
    } catch (_error) {
      message = body.trim();
    }
  }

  if (response.status === 403) {
    message = `${message}. The gateway APIs are localhost-only and allow local console origins only.`;
  } else if (response.status === 429) {
    message = `${message}. The local gateway rate limiter rejected the request.`;
  }

  return new Error(message);
}

async function fetchGatewayJson(path) {
  const baseUrl = persistentState.gatewayUrl;
  const response = await fetch(`${baseUrl}${path}`, {
    cache: "no-store",
    headers: { Accept: "application/json" }
  });

  if (!response.ok) {
    throw await buildResponseError(response, path);
  }

  return response.json();
}

function renderChannels(channels) {
  elements.channelsTableBody.textContent = "";
  if (!Array.isArray(channels) || channels.length === 0) {
    const row = document.createElement("tr");
    const cell = document.createElement("td");
    cell.colSpan = 3;
    cell.textContent = "No channel data available.";
    row.appendChild(cell);
    elements.channelsTableBody.appendChild(row);
    return;
  }

  channels.forEach((channel) => {
    const row = document.createElement("tr");
    const kindCell = document.createElement("td");
    const enabledCell = document.createElement("td");
    const rpsCell = document.createElement("td");
    kindCell.textContent = channel.kind || "unknown";
    enabledCell.textContent = channel.enabled ? "yes" : "no";
    rpsCell.textContent = typeof channel.max_rps === "number" ? String(channel.max_rps) : "unknown";
    row.append(kindCell, enabledCell, rpsCell);
    elements.channelsTableBody.appendChild(row);
  });
}

function renderGatewaySnapshot() {
  const snapshot = runtimeState.gatewaySnapshot;
  elements.gatewayVersion.textContent = snapshot?.status?.version || "unknown";
  elements.gatewayUptime.textContent = formatUptime(snapshot?.status?.uptime_s);
  elements.gatewayProviderRequests.textContent = String(snapshot?.metrics?.provider_requests_total ?? 0);
  elements.gatewayProviderErrors.textContent = String(snapshot?.metrics?.provider_errors_total ?? 0);
  elements.gatewayToolCalls.textContent = String(snapshot?.metrics?.tool_calls_total ?? 0);
  renderChannels(snapshot?.channels?.channels || []);
}

function renderConnectionState() {
  const labelByState = {
    idle: "Gateway not checked",
    checking: "Checking gateway",
    connected: "Gateway ready",
    sending: "Waiting for reply",
    error: "Gateway unavailable"
  };
  elements.connectionPill.dataset.state = runtimeState.connectionState;
  elements.connectionPill.textContent = labelByState[runtimeState.connectionState] || "Gateway status";
  elements.gatewayStatus.textContent = runtimeState.connectionSummary;
  elements.gatewayDetail.textContent = runtimeState.connectionDetail;
}

function renderTransportState() {
  let pillText = "Buffered SSE chat";
  let pillState = "warning";

  if (runtimeState.streamMode === "incremental" || runtimeState.streamChunkCount > 1) {
    pillText = `Incremental SSE observed (${runtimeState.streamChunkCount} events last reply)`;
    pillState = "connected";
  } else if (runtimeState.isSending) {
    pillText = "Buffered SSE in flight";
    pillState = "sending";
  } else if (runtimeState.streamChunkCount === 1) {
    pillText = "Buffered SSE observed (1 event last reply)";
    pillState = "warning";
  }

  elements.transportPill.dataset.state = pillState;
  elements.transportPill.textContent = pillText;
}

function renderSessionState() {
  const transcript = getActiveTranscript();
  const messageCount = transcript.messages.length;
  const noun = messageCount === 1 ? "message" : "messages";
  elements.sessionSummary.textContent =
    `Session ${persistentState.sessionId} · ${messageCount} local ${noun} saved for ${persistentState.gatewayUrl}.`;
  elements.sessionDetail.textContent =
    "The browser keeps this transcript and session ID locally. The gateway continues context only while its configured memory store still has history for the same session.";
}

function renderErrorState() {
  if (!runtimeState.lastError) {
    elements.errorBanner.classList.add("hidden");
    elements.errorMessage.textContent = "";
    return;
  }
  elements.errorBanner.classList.remove("hidden");
  elements.errorMessage.textContent = runtimeState.lastError;
}

function createMessageNode(message) {
  const article = document.createElement("article");
  article.className = "message";
  article.dataset.role = message.role;
  if (message.pending) {
    article.dataset.pending = "true";
  }

  const meta = document.createElement("div");
  meta.className = "message-meta";
  meta.textContent =
    `${message.role === "user" ? "You" : "Gateway"} · ${formatTimestamp(message.createdAt)}`
    + (message.pending ? " · waiting…" : "");

  const body = document.createElement("p");
  body.className = "message-body";
  body.textContent = message.content;

  article.append(meta, body);
  return article;
}

function renderChatHistory() {
  const transcript = getActiveTranscript();
  const messages = transcript.messages.slice();
  elements.chatHistory.textContent = "";

  if (messages.length === 0 && !runtimeState.isSending) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = "No messages yet. Start the gateway, check connectivity, then send a prompt.";
    elements.chatHistory.appendChild(empty);
    return;
  }

  messages.forEach((message) => {
    elements.chatHistory.appendChild(createMessageNode(message));
  });

  if (runtimeState.isSending) {
    elements.chatHistory.appendChild(createMessageNode({
      role: "assistant",
      content: runtimeState.pendingAssistantText || "Waiting for the gateway reply…",
      createdAt: runtimeState.pendingStartedAt || new Date().toISOString(),
      pending: true
    }));
  }

  elements.chatHistory.scrollTop = elements.chatHistory.scrollHeight;
}

function renderControls() {
  const disabled = runtimeState.isSending;
  elements.sendButton.disabled = disabled;
  elements.sendButton.textContent = disabled ? "Sending…" : "Send";
  elements.gatewayUrl.disabled = disabled;
  elements.sessionId.disabled = disabled;
  elements.connectButton.disabled = disabled;
  elements.newSessionButton.disabled = disabled;
}

function renderAll() {
  syncInputsFromState();
  renderConnectionState();
  renderTransportState();
  renderSessionState();
  renderErrorState();
  renderChatHistory();
  renderGatewaySnapshot();
  renderControls();
}

async function connectToGateway({ announceErrors = true } = {}) {
  activateSessionFromInputs();
  setConnectionState(
    "checking",
    `Checking ${persistentState.gatewayUrl}`,
    "Requesting /api/status, /api/channels, and /api/metrics/summary."
  );
  renderAll();

  try {
    const [status, channels, metrics] = await Promise.all([
      fetchGatewayJson("/api/status"),
      fetchGatewayJson("/api/channels"),
      fetchGatewayJson("/api/metrics/summary")
    ]);
    runtimeState.gatewaySnapshot = {
      status,
      channels,
      metrics,
      checkedAt: new Date().toISOString()
    };
    setConnectionState(
      "connected",
      `Connected to ${persistentState.gatewayUrl}`,
      `Status ${status.status || "unknown"} · version ${status.version || "unknown"} · uptime ${formatUptime(status.uptime_s)} · ${status.channels_active ?? 0} active channels · checked ${formatTimestamp(runtimeState.gatewaySnapshot.checkedAt)}.`
    );
    if (announceErrors) {
      clearLastError();
    }
  } catch (error) {
    runtimeState.gatewaySnapshot = null;
    const message = error instanceof Error ? error.message : String(error);
    setConnectionState(
      "error",
      `Could not reach ${persistentState.gatewayUrl}`,
      "The local gateway did not answer the operator-console status requests."
    );
    if (announceErrors) {
      setLastError(message);
    }
  }

  renderAll();
}

function consumeSseBuffer(buffer, onEvent, flush = false) {
  const normalized = buffer.replace(/\r\n/g, "\n");
  const parts = normalized.split("\n\n");
  const completeParts = flush ? parts : parts.slice(0, -1);

  completeParts.forEach((part) => {
    if (part.trim()) {
      onEvent(part);
    }
  });

  return flush ? "" : parts[parts.length - 1];
}

async function requestStreamChat(message) {
  const payload = {
    message,
    session_id: persistentState.sessionId
  };
  const response = await fetch(`${persistentState.gatewayUrl}${chatStreamEndpoint}`, {
    method: "POST",
    cache: "no-store",
    headers: {
      "Content-Type": "application/json",
      Accept: "text/event-stream"
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    throw await buildResponseError(response, chatStreamEndpoint);
  }

  runtimeState.streamMode = response.headers.get("x-vericlaw-stream-mode") || "buffered-sse";

  let aggregate = "";
  let chunks = 0;
  let sawContent = false;

  const handleEvent = (rawEvent) => {
    const data = rawEvent
      .split("\n")
      .filter((line) => line.startsWith("data:"))
      .map((line) => line.slice(5).trimStart())
      .join("\n");

    if (!data || data === "[DONE]") {
      return;
    }

    let parsed;
    try {
      parsed = JSON.parse(data);
    } catch (_error) {
      throw new Error(`Unable to parse /api/chat/stream payload: ${data}`);
    }

    if (parsed && typeof parsed.error === "string" && parsed.error) {
      throw new Error(parsed.error);
    }

    if (parsed && typeof parsed.content === "string") {
      aggregate += parsed.content;
      sawContent = true;
      chunks += 1;
      runtimeState.pendingAssistantText = aggregate || "Waiting for the gateway reply…";
      runtimeState.streamChunkCount = chunks;
      renderChatHistory();
      renderTransportState();
    }
  };

  if (response.body && typeof response.body.getReader === "function") {
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    while (true) {
      const { value, done } = await reader.read();
      if (done) {
        break;
      }
      buffer += decoder.decode(value, { stream: true });
      buffer = consumeSseBuffer(buffer, handleEvent);
    }
    buffer += decoder.decode();
    consumeSseBuffer(buffer, handleEvent, true);
  } else {
    const text = await response.text();
    consumeSseBuffer(text, handleEvent, true);
  }

  if (!sawContent) {
    throw new Error("The gateway completed /api/chat/stream without any assistant content.");
  }

  return {
    content: aggregate,
    chunks
  };
}

function normalizeRuntimeError(error) {
  const message = error instanceof Error ? error.message : String(error);
  if (message === "Failed to fetch") {
    return "Failed to reach the gateway. Make sure the gateway is running locally and that its browser CORS preflight succeeded.";
  }
  return message;
}

async function handleChatSubmit(event) {
  event.preventDefault();
  if (runtimeState.isSending) {
    return;
  }

  const message = elements.chatInput.value.trim();
  if (!message) {
    setLastError("Enter a message before sending it to the gateway.");
    renderAll();
    return;
  }

  activateSessionFromInputs();
  clearLastError();
  appendTranscriptMessage("user", message);
  runtimeState.isSending = true;
  runtimeState.pendingAssistantText = "";
  runtimeState.pendingStartedAt = new Date().toISOString();
  runtimeState.streamChunkCount = 0;
  setConnectionState(
    "sending",
    `Sending to ${persistentState.gatewayUrl}`,
    `Waiting for ${chatStreamEndpoint}. Current builds still return buffered pseudo-SSE, so browser updates may appear only after the full reply is ready.`
  );
  elements.chatInput.value = "";
  renderAll();

  try {
    const result = await requestStreamChat(message);
    appendTranscriptMessage("assistant", result.content);
    runtimeState.streamChunkCount = result.chunks;
    setConnectionState(
      "connected",
      `Reply received from ${persistentState.gatewayUrl}`,
      `${chatStreamEndpoint} completed with ${result.chunks} SSE event${result.chunks === 1 ? "" : "s"}. Browser history and session ID remain available locally.`
    );
    clearLastError();
    connectToGateway({ announceErrors: false }).catch(() => {});
  } catch (error) {
    const messageText = normalizeRuntimeError(error);
    setLastError(messageText);
    setConnectionState(
      "error",
      "Chat request failed",
      "The message stayed in the local transcript, but the gateway did not produce a usable assistant reply."
    );
  } finally {
    runtimeState.isSending = false;
    runtimeState.pendingAssistantText = "";
    runtimeState.pendingStartedAt = "";
    renderAll();
    elements.chatInput.focus();
  }
}

function startNewSession() {
  persistentState.gatewayUrl = normalizeBaseUrl(elements.gatewayUrl.value) || persistentState.gatewayUrl || defaultGatewayUrl;
  persistentState.sessionId = generateSessionId();
  ensureTranscript(persistentState);
  savePersistentState();
  clearLastError();
  runtimeState.pendingAssistantText = "";
  runtimeState.pendingStartedAt = "";
  runtimeState.streamChunkCount = 0;
  setConnectionState(
    runtimeState.connectionState,
    runtimeState.connectionSummary,
    "Started a fresh local browser session. The next message will use a new session_id at the gateway."
  );
  renderAll();
  elements.chatInput.focus();
}

function handleComposerKeys(event) {
  if (event.key === "Enter" && !event.shiftKey) {
    event.preventDefault();
    elements.chatForm.requestSubmit();
  }
}

setSecurityDefaults();
renderLiveSnapshots().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  setListItems("todo-snapshot", [`Unable to read local operator status artifacts. Error: ${message}`]);
  setListItems("health-snapshot", ["Unable to render local health snapshot due to a local runtime error."]);
});

elements.renderedAt.textContent = new Date().toLocaleString();
elements.chatForm.addEventListener("submit", handleChatSubmit);
elements.chatInput.addEventListener("keydown", handleComposerKeys);
elements.connectButton.addEventListener("click", () => {
  connectToGateway({ announceErrors: true });
});
elements.newSessionButton.addEventListener("click", startNewSession);
elements.clearErrorButton.addEventListener("click", () => {
  clearLastError();
  renderAll();
});
elements.gatewayUrl.addEventListener("change", () => {
  activateSessionFromInputs();
  renderAll();
});
elements.sessionId.addEventListener("change", () => {
  activateSessionFromInputs();
  renderAll();
});

renderAll();
connectToGateway({ announceErrors: false }).catch(() => {
  // The UI already renders an explicit disconnected state.
});
