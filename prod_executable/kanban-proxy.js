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

// Compression level 1, not the usual 6. Measured on the E2.1.Micro this runs on,
// against the 2.17 MB app bundle:
//   level 1 -> 703 KB in 303 ms      level 6 -> 571 KB in 788 ms
// The extra 23% of savings is not worth 2.6x the CPU on a box with 1 burstable
// OCPU, where the proxy is single-threaded and blocks other requests while it
// compresses. Override with PROXY_GZIP_LEVEL if the host gets bigger.
const GZIP_LEVEL = parseInt(process.env.PROXY_GZIP_LEVEL || '1', 10);

// 64 KB chunks instead of zlib's 16 KB default: fewer passes through the stream
// machinery, which dominated the cost on this CPU.
const GZIP_CHUNK = 64 * 1024;

// Compressing the same immutable bundle for every visitor is pure waste, so keep
// the gzipped bytes. Only content-hashed assets are cached -- their filenames
// change on rebuild, so entries can never go stale. Bounded because this box has
// ~19 MB of free RAM; oldest entries are evicted first.
const CACHE_MAX_BYTES = parseInt(process.env.PROXY_CACHE_BYTES || String(8 * 1024 * 1024), 10);
const gzipCache = new Map();
let gzipCacheBytes = 0;

function cachePut(key, body, headers) {
    if (body.length > CACHE_MAX_BYTES) return;
    while (gzipCacheBytes + body.length > CACHE_MAX_BYTES && gzipCache.size > 0) {
        const oldest = gzipCache.keys().next().value;
        gzipCacheBytes -= gzipCache.get(oldest).body.length;
        gzipCache.delete(oldest);
    }
    gzipCache.set(key, { body, headers });
    gzipCacheBytes += body.length;
}

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

    const gzip = zlib.createGzip({ level: GZIP_LEVEL, chunkSize: GZIP_CHUNK });
    gzip.on('error', (err) => {
        console.error('[GZIP ERROR]', err.message);
        res.destroy();
    });

    // Tee immutable assets into the cache as they stream to this first client.
    if (HASHED_ASSET.test(pathname)) {
        const chunks = [];
        let aborted = false;
        gzip.on('data', (c) => chunks.push(c));
        proxyRes.on('aborted', () => { aborted = true; });
        gzip.on('end', () => {
            if (!aborted) cachePut(pathname, Buffer.concat(chunks), headers);
        });
    }

    proxyRes.pipe(gzip).pipe(res);
});

// The backend is slow to come up (~1 min after a restart) and single-threaded, so
// it briefly refuses connections during restarts and under load. Returning 502 on
// the first ECONNREFUSED turns every such blip into a user-visible error. Instead,
// retry the upstream connection a few times with a short backoff before giving up.
//
// Only connection-level failures are retried, and only while nothing has been sent
// to the client yet -- so a response is never duplicated or corrupted. On
// ECONNREFUSED/ETIMEDOUT the request never reached the backend, so replaying it
// (including a POST) is safe. Total added latency is bounded by
// RETRIES * RETRY_MS (default ~2.5s) before the honest 502.
const UPSTREAM_RETRIES = parseInt(process.env.PROXY_UPSTREAM_RETRIES || '5', 10);
const UPSTREAM_RETRY_MS = parseInt(process.env.PROXY_UPSTREAM_RETRY_MS || '500', 10);
const RETRIABLE_CODES = new Set(['ECONNREFUSED', 'ECONNRESET', 'ETIMEDOUT', 'EHOSTUNREACH', 'ENETUNREACH']);

function forwardWithRetry(req, res, attempt) {
    // Each proxy.web() call adds 'aborted'/'error' listeners to req; retrying on the
    // same req would otherwise trip the 10-listener leak warning. Raise the ceiling
    // once to match the bounded retry count.
    if (attempt === 0) req.setMaxListeners(UPSTREAM_RETRIES + 4);

    // Passing a callback to proxy.web() routes this request's errors here instead
    // of to the global 'error' event, which is what lets us retry per-request.
    proxy.web(req, res, {}, (err) => {
        const canRetry =
            RETRIABLE_CODES.has(err.code) &&
            !res.headersSent &&
            !res.writableEnded &&
            attempt < UPSTREAM_RETRIES;

        if (canRetry) {
            console.warn(`[UPSTREAM RETRY] ${err.code} on ${req.method} ${req.url} -> attempt ${attempt + 2}/${UPSTREAM_RETRIES + 1}`);
            setTimeout(() => forwardWithRetry(req, res, attempt + 1), UPSTREAM_RETRY_MS);
            return;
        }

        console.error('[PROXY ERROR]', err.code || err.message, `(after ${attempt + 1} attempt(s))`);
        if (!res.headersSent) {
            res.writeHead(502, { 'Content-Type': 'text/plain', 'Retry-After': '2' });
            res.end('502 Bad Gateway: Backend service unavailable\n');
        } else {
            res.destroy();
        }
    });
}

const server = http.createServer((req, res) => {
    const pathname = (req.url || '').split('?')[0];

    // Serve an already-compressed immutable asset without touching upstream or
    // spending any CPU on zlib.
    if (req.method === 'GET' && /\bgzip\b/i.test(req.headers['accept-encoding'] || '')) {
        const hit = gzipCache.get(pathname);
        if (hit) {
            res.writeHead(200, hit.headers);
            res.end(hit.body);
            return;
        }
    }

    // Rewrite Host and Origin headers to match what Kanban expects
    req.headers['host'] = `${TARGET_HOST}:${TARGET_PORT}`;
    req.headers['origin'] = `http://${TARGET_HOST}:${TARGET_PORT}`;
    forwardWithRetry(req, res, 0);
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

// Fallback error handler. HTTP request errors are handled per-request in
// forwardWithRetry() (which passes a callback to proxy.web); this catches the
// remaining cases -- chiefly failed WebSocket upgrades, where `res` is a raw
// net.Socket rather than an http.ServerResponse.
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
