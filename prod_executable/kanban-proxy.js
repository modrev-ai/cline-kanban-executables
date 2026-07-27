const http = require('http');
const path = require('path');

// Ensure global npm modules are in the module resolution path
const globalNodeModules = path.join(process.env.APPDATA || '', 'npm', 'node_modules');
if (globalNodeModules && !module.paths.includes(globalNodeModules)) {
    module.paths.push(globalNodeModules);
}

const httpProxy = require('http-proxy');

// Proxy configuration
const TARGET_HOST = '127.0.0.1';
const TARGET_PORT = process.env.KANBAN_RUNTIME_PORT || '3485';
const PROXY_HOST = '0.0.0.0';
const PROXY_PORT = process.env.PROXY_PORT || '3484';

// Creates a proxy that rewrites headers to satisfy Cline's host check
const proxy = httpProxy.createProxyServer({
    target: `http://${TARGET_HOST}:${TARGET_PORT}`,
    ws: true
});

const server = http.createServer((req, res) => {
    // Rewrite Host and Origin headers to match what Kanban expects
    req.headers['host'] = `${TARGET_HOST}:${TARGET_PORT}`;
    req.headers['origin'] = `http://${TARGET_HOST}:${TARGET_PORT}`;
    proxy.web(req, res);
});

// Let http-proxy handle WebSocket upgrades automatically (ws: true in createProxyServer)
// We just need to rewrite headers before the upgrade
server.on('upgrade', (req, socket, head) => {
    // Rewrite Host and Origin headers to match what Kanban expects
    req.headers['host'] = `${TARGET_HOST}:${TARGET_PORT}`;
    req.headers['origin'] = `http://${TARGET_HOST}:${TARGET_PORT}`;
    // Let the proxy handle the WebSocket upgrade
    proxy.ws(req, socket, head);
});

// Also handle the proxy's upgrade event to ensure headers are rewritten
proxy.on('proxyReqWs', (proxyReq, req, socket, options, head) => {
    // Ensure headers are set on the proxied WebSocket request
    proxyReq.setHeader('host', `${TARGET_HOST}:${TARGET_PORT}`);
    proxyReq.setHeader('origin', `http://${TARGET_HOST}:${TARGET_PORT}`);
});

proxy.on('error', (err) => {
    console.error('[PROXY ERROR]', err.message);
});

server.listen(PROXY_PORT, PROXY_HOST, () => {
    console.log(`Kanban Proxy listening on ${PROXY_HOST}:${PROXY_PORT} -> forwarding to ${TARGET_HOST}:${TARGET_PORT}`);
});