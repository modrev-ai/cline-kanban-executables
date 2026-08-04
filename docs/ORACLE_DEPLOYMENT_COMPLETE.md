# Oracle Cloud Free Tier Deployment Guide
## Hosting Cline + Kanban on Oracle Cloud (ARM A1.Flex)

### Architecture Overview
```
Oracle Cloud Free Tier - VM.Standard.A1.Flex
4 OCPUs ARM, 24 GB RAM, 200 GB Boot Volume
Tailscale (100.x.y.z)
  |
  v
Nginx Reverse Proxy (Port 80/443)
  |-- kanban.yourdomain.com -> localhost:3000 (Kanban)
  |-- cline.yourdomain.com -> localhost:3001 (Cline)
      |                    |
      v                    v
 Kanban Web UI          Cline CLI
 (React/Vite)           (Antigravity)
 PM2:3000               PM2:3001
```

---')