# Agent Container Setup

The agent runs as a dedicated system user `ha_agent` on the host, following IAM principles for identity management.

## Overview

```
Host (riva)
├── User: ha_agent
│   ├── ~/.ssh/
│   │   ├── id_ed25519           # Agent SSH key
│   │   ├── id_ed25519-cert.pub  # Short-lived certificate
│   │   ├── config               # SSH client config
│   │   └── ca/ca_key            # CA for signing certs
│   ├── ~/.secrets/              # API keys, tokens
│   ├── ~/.claude/               # Claude Code config
│   ├── ~/workspace/             # Git repos
│   ├── ~/sessions/              # Session recordings
│   └── ~/Dockerfile, scripts    # Container build files
└── Podman (rootless, as ha_agent)
    └── Container: claude-ha-agent
```

## Prerequisites

- Ansible installed on riva
- sudo access to create users

## 1. Create ha_agent User (Ansible)

```bash
cd agent_containers/ansible
ansible-playbook playbooks/agent-setup.yml
```

This creates:
- User `ha_agent` with home directory
- SSH key pair and CA
- Initial certificate (valid 1 day)
- Cron job for daily certificate renewal
- Enabled lingering (systemd user services)

## 2. Create ha_agent User on HA Host

On Home Assistant, create the `ha_agent` user:
- **HA OS**: Settings → People → Users → Add User
  - Username: `ha_agent`
  - Enable "Can only log in from the local network" (optional)
  - Enable "Administrator" if the agent needs full access
- **Or via CLI** (if SSH addon installed): `ha auth create --name ha_agent`

## 3. Configure HA Host to Trust Agent CA

Copy the CA public key to HA host:
```bash
sudo -u ha_agent cat /home/ha_agent/.ssh/ca/ca_key.pub | \
  ssh root@10.4.4.10 "cat >> /etc/ssh/ca-keys.pub"
```

On HA host (10.4.4.10), add to `/etc/ssh/sshd_config`:
```
TrustedUserCAKeys /etc/ssh/ca-keys.pub
```

Reload sshd (HA OS runs in container without systemd):
```bash
ssh root@10.4.4.10 "kill -HUP \$(cat /var/run/sshd.pid)"
```

### (Future step) Restrict agent to forced commands

On HA host, create `/usr/local/bin/ha-agent-shell`:
```bash
#!/bin/bash
# Allowed commands for ha_agent
case "$SSH_ORIGINAL_COMMAND" in
  "ha core check"*|"ha config"*|"cat /config/"*)
    eval "$SSH_ORIGINAL_COMMAND"
    ;;
  *)
    echo "Command not allowed: $SSH_ORIGINAL_COMMAND"
    exit 1
    ;;
esac
```

And in `sshd_config`:
```
Match User ha_agent
    ForceCommand /usr/local/bin/ha-agent-shell
```

## 3. Provision API Keys and Tokens

Switch to ha_agent:
```bash
sudo -iu ha_agent
```

### Anthropic API key
Get from https://console.anthropic.com/settings/keys
```bash
echo -n "sk-ant-..." > ~/.secrets/anthropic_api_key
chmod 600 ~/.secrets/anthropic_api_key
```

### GitHub token
Create at https://github.com/settings/tokens with scopes: `repo`, `read:org`
```bash
echo -n "ghp_..." > ~/.secrets/github_token
chmod 600 ~/.secrets/github_token
```

### Home Assistant access token
In HA: Profile → Long-Lived Access Tokens → Create Token
```bash
echo -n "eyJ..." > ~/.secrets/ha_access_token
chmod 600 ~/.secrets/ha_access_token
```

## 4. Create Podman Secrets

As ha_agent:
```bash
sudo -iu ha_agent

export XDG_RUNTIME_DIR=/run/user/$(id -u)

podman secret create anthropic_api_key ~/.secrets/anthropic_api_key
podman secret create github_token ~/.secrets/github_token
podman secret create ha_access_token ~/.secrets/ha_access_token
```

Verify:
```bash
podman secret ls
```

## 5. Build Container Image

As ha_agent:
```bash
sudo -iu ha_agent
cd ~
./build.sh
```

## 6. Create Podman Network

As ha_agent:
```bash
export XDG_RUNTIME_DIR=/run/user/$(id -u)
podman --cgroup-manager=cgroupfs network create ha-agent-net --subnet 10.89.1.0/24
```

## 7. Deploy Network Isolation

As admin user (needs sudo for system services):
```bash
cd agent_containers/ansible
ansible-playbook playbooks/agent-proxy.yml
```

## 8. Clone Workspace Repos

As ha_agent:
```bash
sudo -iu ha_agent
cd ~/workspace
git clone git@github.com:rhoerbe/hadmin.git
```

## 9. Run the Agent Container

As ha_agent:
```bash
sudo -iu ha_agent
./start_container.sh
```

## 10. Verify Setup

Inside the container:
```bash
# Test SSH to HA
ssh ha "echo ok"

# Test proxy (should work)
curl -I https://api.github.com

# Test blocked domain (should fail)
curl -I https://example.com
```

## Running as a Service (Optional)

Create systemd user service for ha_agent:

```bash
sudo -iu ha_agent
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/claude-ha-agent.service << 'EOF'
[Unit]
Description=Claude HA Agent Container
After=network.target

[Service]
Type=simple
ExecStart=/home/ha_agent/start_container.sh
ExecStop=/usr/bin/podman --cgroup-manager=cgroupfs stop claude-ha-agent
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable claude-ha-agent
```

## Credential Rotation

| Credential | Rotation | Method |
|------------|----------|--------|
| SSH certificate | Daily | Cron job (automatic) |
| Anthropic API key | As needed | Update ~/.secrets/, recreate podman secret |
| GitHub token | 90 days | Regenerate, update secret |
| HA access token | As needed | Regenerate in HA UI, update secret |

### Updating a podman secret
As ha_agent:
```bash
podman secret rm anthropic_api_key
podman secret create anthropic_api_key ~/.secrets/anthropic_api_key
```

## Playbook Summary

| Playbook | Purpose | Run as |
|----------|---------|--------|
| `agent-setup.yml` | Create ha_agent user, SSH keys, CA | Admin (sudo) |
| `agent-proxy.yml` | Deploy tinyproxy + nftables | Admin (sudo) |

## Troubleshooting

### Container can't reach proxy
```bash
systemctl status tinyproxy
ss -tlnp | grep 8888
```

### SSH certificate expired
Check validity:
```bash
sudo -u ha_agent ssh-keygen -L -f /home/ha_agent/.ssh/id_ed25519-cert.pub
```

Manually renew:
```bash
sudo -iu ha_agent
ssh-keygen -s ~/.ssh/ca/ca_key -I ha_agent -n ha_agent -V +1d ~/.ssh/id_ed25519.pub
```

### Blocked network traffic
```bash
sudo journalctl -k | grep agent-blocked
```

### Podman permission issues
Ensure XDG_RUNTIME_DIR is set:
```bash
export XDG_RUNTIME_DIR=/run/user/$(id -u ha_agent)
```
