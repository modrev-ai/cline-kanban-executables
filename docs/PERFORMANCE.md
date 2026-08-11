# Kanban Deployment Performance

Diagnosis and remediation for the "exceptionally slow" deployed Kanban, measured
against the live instance on 2026-08-12.

## What the box actually is

The deployment docs describe `VM.Standard.A1.Flex` (4 OCPU ARM, 24 GB RAM). The
running instance is not that:

| | Documented | Actual |
|---|---|---|
| Shape | VM.Standard.A1.Flex | **VM.Standard.E2.1.Micro** |
| Architecture | aarch64 | x86_64 (AMD EPYC 7551) |
| OCPUs | 4 | 1 (burstable, heavily throttled) |
| RAM | 24 GB | **1 GB** (498 MB usable) |
| Region/AD | — | us-ashburn-1 / AD-2 |

At measurement time the box had **19 MB of free RAM** and 812 MB paged out to
swap. A trivial 30M-iteration loop takes **2.3 s** there — roughly 45x slower
than a normal machine.

## Root causes, in order of impact

### 1. `--jitless` on the proxy (fixed)

`kanban-proxy.service` ran `node --jitless kanban-proxy.js`. That disables the
V8 JIT entirely, leaving the interpreter to execute every byte the UI loads.
Measured on the box, over loopback with no network involved:

| Asset | Direct (:3485) | Via `--jitless` proxy (:3484) | Penalty |
|---|---|---|---|
| `index-*.js` (2.17 MB) | 0.19 s (11.5 MB/s) | 1.49 s (1.45 MB/s) | **7.9x** |
| `xterm-vendor-*.js` (620 KB) | 0.11 s (5.9 MB/s) | 0.81 s (0.76 MB/s) | **7.7x** |

The public entrypoint is the proxy, so every user request paid this. Removed.

### 2. No compression (fixed)

Upstream served everything uncompressed even when the client sent
`Accept-Encoding: gzip`. The proxy now gzips compressible types:

| Asset | Raw | gzip -6 | Saved |
|---|---|---|---|
| `index-*.js` | 2,171,360 B | 571,610 B | 74% |
| `xterm-vendor-*.js` | 620,728 B | 142,073 B | 77% |

Those two assets alone drop from **2.79 MB to 713 KB**.

### 3. `Cache-Control: no-store` on immutable assets (fixed)

Upstream marked content-hashed bundles `no-store`, so browsers re-downloaded the
full ~3 MB on *every* page load. Vite filenames embed a content hash
(`index-DZbLENWC.js`), so they are immutable by construction. The proxy now
rewrites only `/assets/<name>-<hash>.<ext>` to
`public, max-age=31536000, immutable`. The HTML shell keeps `no-store`, so a new
build still invalidates correctly.

### 4. V8 heap sized for a 1 GB box (fixed)

V8 derives its default old-space cap from physical memory — about 256 MB here,
which makes cline GC-thrash. `deploy-infra.sh` now sets
`--max-old-space-size` to half of detected RAM, clamped to [512 MB, 4096 MB].

### 5. `npm maxsockets 1` (fixed)

Serialized every npm download; installing 3 packages took 3 minutes. Raised to 8.
This affects deploy time, not runtime.

## Verification

The proxy rewrite was tested against a stub upstream before deployment:

- gzip applied, `Vary: Accept-Encoding` set, `Transfer-Encoding: chunked`
- **body integrity**: md5 of decompressed body == md5 of origin body
- clients without gzip support still get the full uncompressed body
- **SSE is never compressed or buffered** — first byte at 3 ms of a 166 ms stream
- HTML shell keeps `no-store`; non-hashed images get neither cache nor gzip
- 304 responses gain no `Content-Encoding`
- **WebSocket upgrade still works**, with Host/Origin rewriting intact

## Scaling up (free)

Oracle's Always Free tier includes 4 OCPUs / 24 GB of `VM.Standard.A1.Flex` in
*addition* to the two E2.1.Micro instances — so moving costs nothing and does not
consume the micro quota.

A1.Flex is **aarch64**, and the current instance is x86_64. There is no in-place
resize across architectures; it requires a new instance. `deploy-infra.sh`
previously hardcoded `ARCH="x64"` and would have failed with `Exec format error`
on ARM — it now detects `uname -m`.

```bash
oci session authenticate                                  # tokens expire
./deploy/scripts/provision-a1.sh --source-ip 129.159.69.183 --retry 120
```

The script discovers the compartment, subnet, and SSH key from the existing
instance, picks the newest Oracle Linux 9 aarch64 image, and tries every
availability domain. **Free-tier ARM capacity in us-ashburn-1 is frequently
exhausted** — `--retry <minutes>` keeps trying, which is usually necessary.

After it succeeds:

1. Confirm SSH to the new IP.
2. `gh secret set ORACLE_HOST --body '<new-ip>'`
3. Run the infrastructure + deploy workflows.
4. Verify, then terminate the old E2.1.Micro.

Boot volume defaults to 100 GB (`--boot-gb`); free-tier block storage is 200 GB
total across all volumes, and the existing micro already uses part of that.
