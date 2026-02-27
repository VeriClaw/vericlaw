const express = require('express');
const { Client } = require('@modelcontextprotocol/sdk/client/index.js');
const { StdioClientTransport } = require('@modelcontextprotocol/sdk/client/stdio.js');
const { StreamableHTTPClientTransport } = require('@modelcontextprotocol/sdk/client/streamableHttp.js');

const app = express();
app.use(express.json());

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
  const server = parts[1];
  const name = parts[2];
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
app.listen(port, () => console.log(`mcp-bridge listening on :${port}`));
