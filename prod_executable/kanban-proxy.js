const http = require('http');
const path = require('path');
const os = require('os');
const zlib = require('zlib');

// Ensure global npm modules are in the module resolution path (cross-platform)
let globalNodeModules = '';
if (process.platform === 'win32') {
    globalNodeModules = path.join(process.env.APPDATA || '', 'npm', 'node_modules');
} else {
    // Linux/macOS - check common global npm locations
    const homeDir = os.homedir();
    globalNodeModules = path.join(homeDir, '.npm-global', 'lib', 'node_modules');
    // Also check /usr/local/lib/node_modules as fallback
    if (!require('fs').existsSync(globalNodeModules)) {
        globalNodeModules = '/usr/local/lib/node_modules';
    }
}
if (globalNodeModules && !module.paths.includes(globalNodeModules)) {
    module.paths.push(globalNodeModules);
}

const httpProxy = require('http-proxy');

// Proxy configuration
const TARGET_HOST = '127.0.0.1';
const TARGET_PORT = process.env.KANBAN_RUNTIME_PORT || '3485';
const PROXY_HOST = '0.0.0.0';
const PROXY_PORT = process.env.PROXY_PORT || '3484';

// Creates a proxy that rewrites headers to satisfy Cline's host check.
// selfHandleResponse lets us gzip and re-cache responses in the proxyRes handler
// below; without it http-proxy pipes upstream straight to the client.
const proxy = httpProxy.createProxyServer({
    target: `http://${TARGET_HOST}:${TARGET_PORT}`,
    ws: true,
    selfHandleResponse: true
});

// Upstream serves everything uncompressed and with `Cache-Control: no-store`, so
// every page load re-downloads ~3 MB of JS. Vite emits content-hashed filenames
// under /assets/, which are immutable by construction and safe to cache forever.
const HASHED_ASSET = /^\/assets\/.+-[A-Za-z0-9_-]{8,}\.(?:js|css|woff2?|ttf|otf|svg|png|jpe?g|webp|avif)$/;
const COMPRESSIBLE = /^(?:text\/|application\/(?:javascript|json|xml|wasm|manifest)|image\/svg)/i;

proxy.on('proxyRes', (proxyRes, req, res) => {
    const headers = Object.assign({}, proxyRes.headers);
    const contentType = headers['content-type'] || '';
    const pathname = (req.url || '').split('?')[0];

    if (HASHED_ASSET.test(pathname)) {
        headers['cache-control'] = 'public, max-age=31536000, immutable';
    }

    // Never touch SSE (must stream unbuffered), already-encoded bodies, bodiless
    // responses, or types that do not benefit from compression.
    const acceptsGzip = /\bgzip\b/i.test(req.headers['accept-encoding'] || '');
    const shouldGzip =
        acceptsGzip &&
        proxyRes.statusCode === 200 &&
        req.method !== 'HEAD' &&
        !headers['content-encoding'] &&
        !/text\/event-stream/i.test(contentType) &&
        COMPRESSIBLE.test(contentType);

    if (!shouldGzip) {
        res.writeHead(proxyRes.statusCode, headers);
        proxyRes.pipe(res);
        return;
    }

    // Length changes once compressed; gzip streams out chunked instead.
    delete headers['content-length'];
    headers['content-encoding'] = 'gzip';
    headers['vary'] = headers['vary']
        ? `${headers['vary']}, Accept-Encoding`
        : 'Accept-Encoding';

    res.writeHead(proxyRes.statusCode, headers);

    const gzip = zlib.createGzip({ level: 6 });
    gzip.on('error', (err) => {
        console.error('[GZIP ERROR]', err.message);
        res.destroy();
    });
    proxyRes.pipe(gzip).pipe(res);
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

// Return 502 immediately when backend is unavailable so health checks fail fast
// instead of hanging until the client times out.
proxy.on('error', (err, req, res) => {
    console.error('[PROXY ERROR]', err.message);
    // res is an http.ServerResponse for HTTP requests, or a net.Socket for WebSocket
    // upgrades. Only send an HTTP response for the former.
    if (res && typeof res.writeHead === 'function' && !res.headersSent) {
        res.writeHead(502, { 'Content-Type': 'text/plain' });
        res.end('502 Bad Gateway: Backend service unavailable\n');
    } else if (res && typeof res.destroy === 'function') {
        res.destroy();
    }
});

server.listen(PROXY_PORT, PROXY_HOST, () => {
    console.log(`Kanban Proxy listening on ${PROXY_HOST}:${PROXY_PORT} -> forwarding to ${TARGET_HOST}:${TARGET_PORT}`);
});
