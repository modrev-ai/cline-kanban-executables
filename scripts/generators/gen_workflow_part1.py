"part1 = '''name: Deploy to Oracle Cloud Free Tier" 
on:
  push:
    branches: [main, feature/kanban-dashboard-antigravity-tailscale]
  pull_request:
    branches: [main]
  workflow_dispatch:
    inputs:
      oracle_host:
        description: Oracle Cloud instance public IP or hostname
        required: true
        type: string
      oracle_user:
        description: SSH username (usually ubuntu)
        required: false
        default: ubuntu
        type: string
      ssh_key:
        description: SSH private key for authentication
        required: true
        type: string

permissions:
  contents: read
  id-token: write

jobs:
  deploy:
    name: Deploy to Oracle Cloud
    runs-on: ubuntu-latest
    timeout-minutes: 30
    environment: production
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Setup SSH
        uses: webfactory/ssh-agent@v0.9.0
        with:
          ssh-private-key: ${{ github.event.inputs.ssh_key || secrets.ORACLE_SSH_KEY }}\n
      - name: Add known hosts
        run: |
          ssh-keyscan -H ${{ github.event.inputs.oracle_host || secrets.ORACLE_INSTANCE_HOST }} >> ~/.ssh/known_hosts
"