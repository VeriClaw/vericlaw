const express = require('express');
const { Client } = require('@modelcontextprotocol/sdk/client/index.js');
const { StdioClientTransport } = require('@modelcontextprotocol/sdk/client/stdio.js');
const { StreamableHTTPClientTransport } = require('@modelcontextprotocol/sdk/client/streamableHttp.js');

const crypto = require('crypto');

const app = express();
app.use(express.json());

// MCP_BRIDGE_TOKEN env var: bearer token for authenticating requests.
// If not set, a random token is generated and printed on startup.
const BRIDGE_TOKEN = process.env.MCP_BRIDGE_TOKEN || crypto.randomBytes(32).toString('hex');

// Rate limiting: max requests per window per IP.
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = parseInt(process.env.MCP_RATE_LIMIT_MAX || '60', 10);
const rateCounts = new Map();

function checkRateLimit(ip) {
  const now = Date.now();
  let entry = rateCounts.get(ip);
  if (!entry || now - entry.start > RATE_LIMIT_WINDOW_MS) {
    entry = { start: now, count: 0 };
    rateCounts.set(ip, entry);
  }
  entry.count++;
  return entry.count <= RATE_LIMIT_MAX;
}

// Authentication middleware: require valid bearer token on all non-health endpoints.
function authMiddleware(req, res, next) {
  if (req.path === '/health') return next();
  const auth = req.headers.authorization;
  if (!auth || !auth.startsWith('Bearer ') || auth.slice(7) !== BRIDGE_TOKEN) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  if (!checkRateLimit(req.ip)) {
    return res.status(429).json({ error: 'rate limit exceeded' });
  }
  next();
}
app.use(authMiddleware);

// Tool allowlist: only tools matching these patterns are callable.
// Set MCP_TOOL_ALLOWLIST to a comma-separated list (e.g. "filesystem:*,github:read_*").
// If unset, all tools from connected servers are allowed.
const toolAllowlistRaw = process.env.MCP_TOOL_ALLOWLIST || '';
const toolAllowPatterns = toolAllowlistRaw ? toolAllowlistRaw.split(',').map(s => s.trim()) : [];

function isToolAllowed(serverName, toolName) {
  if (toolAllowPatterns.length === 0) return true;
  const qualified = `${serverName}:${toolName}`;
  return toolAllowPatterns.some(pattern => {
    const re = new RegExp('^' + pattern.replace(/\*/g, '.*') + '$');
    return re.test(qualified);
  });
}

// MCP_SERVERS env var: JSON array of server configs
// [{"name":"filesystem","command":"npx","args":["-y","@modelcontextprotocol/server-filesystem","/home/user"]},
//  {"name":"github","url":"http://localhost:8090"}]
const serverConfigs = JSON.parse(process.env.MCP_SERVERS || '[]');
const clients = new Map();
const allTools = [];

async function connectServers() {
  for (const cfg of serverConfigs) {
    const client = new Client({ name: 'vericlaw-mcp', version: '1.0.0' }, {});
    let transport;
    if (cfg.url) {
      transport = new StreamableHTTPClientTransport(new URL(cfg.url));
    } else {
      transport = new StdioClientTransport({ command: cfg.command, args: cfg.args || [] });
    }
    try {
      await client.connect(transport);
      const { tools } = await client.listTools();
      for (const tool of tools) {
        allTools.push({ ...tool, _server: cfg.name });
        clients.set(`${cfg.name}:${tool.name}`, client);
      }
      console.log(`Connected to MCP server: ${cfg.name} (${tools.length} tools)`);
    } catch (e) {
      console.error(`Failed to connect to ${cfg.name}:`, e.message);
    }
  }
}

connectServers();

app.get('/tools', (req, res) => {
  res.json(allTools.map(t => ({
    name: `mcp__${t._server}__${t.name}`,
    description: t.description,
    inputSchema: t.inputSchema
  })));
});

app.post('/tools/:toolName/call', async (req, res) => {
  const parts = req.params.toolName.split('__');
  // toolName format: mcp__servername__toolname
  if (parts.length !== 3 || parts[0] !== 'mcp') {
    return res.status(400).json({ error: 'Invalid tool name format. Expected mcp__server__tool' });
  }
  const server = parts[1];
  const name = parts[2];

  if (!isToolAllowed(server, name)) {
    return res.status(403).json({ error: 'Tool not in allowlist' });
  }

  const client = clients.get(`${server}:${name}`);
  if (!client) return res.status(404).json({ error: 'Tool not found' });
  try {
    const result = await client.callTool({ name, arguments: req.body.arguments || {} });
    const text = result.content?.filter(c => c.type === 'text').map(c => c.text).join('\n') || '';
    res.json({ result: text });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/health', (req, res) => res.json({ ok: true, tools: allTools.length }));

const port = process.env.PORT || 3004;
app.listen(port, '127.0.0.1', () => {
  console.log(`mcp-bridge listening on 127.0.0.1:${port}`);
  if (!process.env.MCP_BRIDGE_TOKEN) {
    console.log(`Auto-generated bridge token: ${BRIDGE_TOKEN}`);
    console.log('Set MCP_BRIDGE_TOKEN env var to use a fixed token.');
  }
});
