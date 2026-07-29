# Oracle Cloud Free Tier Deployment Guide
## Hosting Cline + Kanban on Oracle Cloud (ARM A1.Flex)

### Architecture Overview
```
┌─────────────────────────────────────────────────────────────┐
│  Oracle Cloud Free Tier - VM.Standard.A1.Flex               │
│  4 OCPUs ARM, 24 GB RAM, 200 GB Boot Volume                 │
├─────────────────────────────────────────────────────────────┤
│  Tailscale (100.x.y.z) ◄──────────────────────────────────┐  │
│  │                                                         │  │
│  ▼                                                         │  │
│  ┌─────────────────────────────────────────────────────┐   │  │
│  │ Nginx Reverse Proxy (Port 80/443)                   │   │  │
│  │  ├── kanban.yourdomain.com → localhost:3000 (Kanban)│   │  │
│  │  └── cline.yourdomain.com → localhost:3001 (Cline)  │   │  │
│  └─────────────────────────────────────────────────────┘   │  │
│         │                              │                    │  │
│         ▼                              ▼                    │  │
│  ┌──────────────┐              ┌──────────────┐            │  │
│  │ Kanban Web UI│              │ Cline CLI    │            │  │
│  │ (React/Vite) │              │ (Antigravity)│            │  │
│  │ PM2:3000     │              │ PM2:3001     │            │  │
│  └──────────────┘              └──────────────┘            │  │
└─────────────────────────────────────────────────────────────┘
```

---

## Prerequisites
- Oracle Cloud Free Tier account
- Domain name (or use nip.io for testing)
- GitHub Personal Access Token (for private repos if needed)

---

## Step 1: Create Oracle Cloud Instance

### 1.1 Create Compute Instance
```bash
# In Oracle Cloud Console:
# 1. Create Compute Instance
# 2. Shape: VM.Standard.A1.Flex
# 3. OCPUs: 4 (max free)
# 4. Memory: 24 GB (max free)
# 5. Image: Ubuntu 22.04 (Canonical)
# 6. Boot Volume: 200 GB (max free)
# 7. SSH Keys: Add your public key
# 8. VCN: Create new or use existing
# 9. Public Subnet: Yes
# 10. Assign Public IP: Yes
```

### 1.2 Configure Security Lists/Network Security Groups
```
Ingress Rules:
- 22/tcp   (SSH) - Your IP only
- 80/tcp   (HTTP) - 0.0.0.0/0
- 443/tcp  (HTTPS) - 0.0.0.0/0
- 3000/tcp (Kanban) - Tailscale CIDR (100.64.0.0/10)
- 3001/tcp (Cline) - Tailscale CIDR (100.64.0.0/10)
- 41641/udp (Tailscale) - 0.0.0.0/0
```
"# Oracle Cloud Free Tier Deployment" 
