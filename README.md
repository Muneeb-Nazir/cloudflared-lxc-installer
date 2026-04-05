# Cloudflared LXC Installer for Proxmox VE 9.x

## Overview

This automated script creates a lightweight LXC container on Proxmox VE 9.x and installs Cloudflared (Cloudflare Tunnel) inside it. The script is specifically updated to support Debian 13 (Trixie) and uses the latest Cloudflared installation method.

## What is Cloudflared?

Cloudflared is the client that runs the Cloudflare Tunnel, creating a secure, outbound-only connection between your infrastructure and Cloudflare's edge network. This allows you to:
- Expose services without opening firewall ports
- Hide your origin server IP address
- Add Zero Trust security to your applications
- Reduce DDoS attack surface

## What This Script Does

### Phase 1: Environment Setup
- ✅ Validates Proxmox VE 9.x compatibility
- ✅ Detects available storage (ZFS, LVM, or directory)
- ✅ Finds or downloads Debian container template (supports Debian 12 & 13)
- ✅ Determines next available container ID

### Phase 2: Container Creation
- Creates an unprivileged LXC container with:
  - Customizable hostname, disk size, CPU cores, RAM
  - Static IP or DHCP configuration
  - Network bridge attachment (vmbr0 by default)
  - Optional root password (or automatic login)
  - Nesting and keyctl features enabled

### Phase 3: Cloudflared Installation
- Installs Cloudflared using the official method:
  - Adds Cloudflare GPG key (`cloudflare-public-v2.gpg`)
  - Configures apt repository
  - Installs latest Cloudflared package
- Sets up systemd service for automatic startup
- Creates dedicated `cloudflared` system user

### Phase 4: Post-Installation
- Displays container details (IP, ID, storage)
- Shows service management commands
- Provides Cloudflare Tunnel setup instructions

## Prerequisites

### System Requirements
- **Proxmox VE 9.x** (tested with 9.0 and later)
- **Root access** to the Proxmox host
- **Internet connection** for downloading templates and packages
- **At least 2GB free storage** for the container

### Recommended Resources
| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU Cores | 1 | 1-2 |
| RAM | 512 MB | 512 MB - 1 GB |
| Disk | 2 GB | 2-4 GB |

## Installation

### Method 1: Direct Download & Run (Quickest)

```bash
# Download and run script directly
curl -sSL https://raw.githubusercontent.com/your-repo/cloudflared-lxc-installer/main/install.sh | bash
```

### Method 2: Save Locally & Execute

```bash
# Save the script
nano install-cloudflared.sh

# Make it executable
chmod +x install-cloudflared.sh

# Run the script
./install-cloudflared.sh
```

### Method 3: Copy from Source

```bash
# Create script file
cat > /usr/local/bin/install-cloudflared.sh << 'EOF'
[PASTE THE ENTIRE SCRIPT HERE]
EOF

# Make executable and run
chmod +x /usr/local/bin/install-cloudflared.sh
/usr/local/bin/install-cloudflared.sh
```

## Interactive Setup Walkthrough

When you run the script, you'll be prompted for:

### 1. Container ID
```
Enter Container ID (default: 106): 
```
- Accept default or enter a unique ID (must not be in use)

### 2. Hostname
```
Enter Hostname (default: cloudflared): cloudflared.services
```
- Choose a descriptive hostname

### 3. Debian Version
```
Debian Version Options:
1) Debian 13 (Trixie) - Latest - Recommended for PVE 9.x
2) Debian 12 (Bookworm) - Stable
Choose Debian version (1-2, default: 1):
```
- **Debian 13** is recommended for Proxmox 9.x
- **Debian 12** for maximum stability

### 4. Disk Size
```
Enter Disk Size in GB (default: 2): 
```
- 2GB is sufficient for Cloudflared
- Increase if you plan to add other services

### 5. CPU Cores
```
Enter CPU Cores (default: 1): 
```
- 1 core is sufficient for most use cases

### 6. RAM
```
Enter RAM in MB (default: 512): 
```
- 512MB is sufficient
- Increase for high-traffic tunnels

### 7. IP Configuration
```
Enter IP (dhcp for automatic, or CIDR like 192.168.1.100/24): 192.168.10.179/24
```
- Use `dhcp` for automatic IP
- Or specify static IP in CIDR format

### 8. Root Password (Optional)
```
Enter root password (leave empty for automatic login):
```
- Leave empty for automatic login (no password needed)
- Set a password if you plan to use SSH

## Post-Installation

### Access the Container

```bash
# Direct console access
pct enter 106

# Or via lxc-attach
lxc-attach -n 106

# Or SSH (if password was set)
ssh root@192.168.10.179
```

### Set Up Cloudflare Tunnel

#### Step 1: Login to Cloudflare
```bash
pct exec 106 -- cloudflared tunnel login
```
- Opens browser for Cloudflare authentication
- Select your domain/zone

#### Step 2: Create a Tunnel
```bash
pct exec 106 -- cloudflared tunnel create my-tunnel
```
- Replace `my-tunnel` with your tunnel name
- Saves credentials to `~/.cloudflared/`

#### Step 3: Route DNS
```bash
pct exec 106 -- cloudflared tunnel route dns my-tunnel app.example.com
```
- Routes `app.example.com` through the tunnel

#### Step 4: Create Configuration
```bash
# Create config file
pct exec 106 -- nano ~/.cloudflared/config.yml
```

Example `config.yml`:
```yaml
tunnel: my-tunnel
credentials-file: /root/.cloudflared/my-tunnel.json

ingress:
  - hostname: app.example.com
    service: http://localhost:8080
  - service: http_status:404
```

#### Step 5: Run the Tunnel
```bash
# Run as a service
pct exec 106 -- systemctl start cloudflared
pct exec 106 -- systemctl enable cloudflared

# Or run manually for testing
pct exec 106 -- cloudflared tunnel run my-tunnel
```

### Service Management Commands

```bash
# Check status
pct exec 106 -- systemctl status cloudflared

# View logs
pct exec 106 -- journalctl -u cloudflared -f

# Restart service
pct exec 106 -- systemctl restart cloudflared

# Stop service
pct exec 106 -- systemctl stop cloudflared
```

## Container Management

### Basic Container Operations

```bash
# Stop container
pct stop 106

# Start container
pct start 106

# Reboot container
pct reboot 106

# Destroy container (removes everything)
pct destroy 106

# Backup container
vzdump 106 --mode stop --compress zstd

# Restore container from backup
pct restore 106 /var/lib/vz/dump/vzdump-lxc-106-2024_01_01.tar.zst
```

### Resource Management

```bash
# Change CPU cores (requires reboot)
pct set 106 --cores 2

# Change RAM (live, no reboot)
pct set 106 --memory 1024

# Change disk size (requires storage support)
pct resize 106 rootfs +2G

# View resource usage
pct status 106
pct enter 106 -- top
```

## Troubleshooting

### Common Issues

#### Container Won't Start
```bash
# Check container status
pct status 106

# Check logs
journalctl -u pve-container@106

# Try starting with debug
pct start 106 --debug
```

#### Cloudflared Won't Install
```bash
# Check network connectivity
pct exec 106 -- ping -c 4 8.8.8.8
pct exec 106 -- ping -c 4 pkg.cloudflare.com

# Manual install inside container
pct enter 106
curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | tee /usr/share/keyrings/cloudflare-public-v2.gpg
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list
apt-get update && apt-get install cloudflared
```

#### Storage Error
```bash
# Check available storage
pvesm status

# List storage that supports containers
pvesm status -content rootdir

# Download template manually
pveam update
pveam download local debian-13-standard_13.0-1_amd64.tar.zst
```

#### Network Issues
```bash
# Verify IP configuration
pct exec 106 -- ip addr show
pct exec 106 -- ip route show

# Test connectivity
pct exec 106 -- ping -c 4 1.1.1.1

# Restart network inside container
pct exec 106 -- systemctl restart networking
```

## Uninstallation

### Remove the Container
```bash
# Stop the container
pct stop 106

# Destroy the container
pct destroy 106 --purge

# Remove backup (if any)
rm /var/lib/vz/dump/vzdump-lxc-106-*.tar.zst
```

### Remove Cloudflared Only (Keep Container)
```bash
pct enter 106
systemctl stop cloudflared
systemctl disable cloudflared
apt-get remove cloudflared
rm -rf /etc/apt/sources.list.d/cloudflared.list
rm -rf /usr/share/keyrings/cloudflare-public-v2.gpg
rm -rf /root/.cloudflared/
```

## Security Considerations

1. **Unprivileged Containers**: Script uses unprivileged containers by default (recommended)
2. **Automatic Login**: No root password set by default (use `pct enter`)
3. **Isolation**: Container runs with limited system access
4. **Updates**: Regularly update both Proxmox and the container:
   ```bash
   apt update && apt upgrade  # On Proxmox host
   pct exec 106 -- apt update && apt upgrade  # Inside container
   ```

## Performance Tips

1. **Tune systemd service** for better performance:
   ```bash
   pct exec 106 -- nano /etc/systemd/system/cloudflared.service
   # Add: LimitNOFILE=65536
   # Add: CPUQuota=50%
   ```

2. **Enable caching** for static content:
   ```bash
   pct exec 106 -- cloudflared tunnel run --hello-world
   ```

3. **Monitor resource usage**:
   ```bash
   pct exec 106 -- htop
   pct exec 106 -- cloudflared tunnel --metrics localhost:45678
   ```

## Support

### Useful Commands Reference

| Action | Command |
|--------|---------|
| Enter container | `pct enter <CT_ID>` |
| Check Cloudflared version | `pct exec <CT_ID> -- cloudflared --version` |
| View tunnel list | `pct exec <CT_ID> -- cloudflared tunnel list` |
| Delete tunnel | `pct exec <CT_ID> -- cloudflared tunnel delete <tunnel-name>` |
| Update Cloudflared | `pct exec <CT_ID> -- apt update && apt upgrade cloudflared` |

### Log Locations
- Container logs: `journalctl -u pve-container@<CT_ID>`
- Cloudflared logs: `pct exec <CT_ID> -- journalctl -u cloudflared`
- Cloudflared debug logs: `pct exec <CT_ID> -- cloudflared tunnel run --loglevel debug`

## License

MIT License - See original script header for details

## Version History

- **v2.0** - Added Debian 13 support, updated Cloudflared installation method
- **v1.0** - Initial release for Proxmox 8.x

## Contributing

Found an issue or have a suggestion? Please report it with:
- Proxmox version (`pveversion -v`)
- Container configuration (`pct config <CT_ID>`)
- Error messages and logs

---
# Key Changes Made:
- Removed GPG/apt repository method - No more GPG key issues
- Uses direct binary download from GitHub releases
- Installs prerequisites (curl, wget, ca-certificates)
- Verifies binary before moving to system path
- Service uses /usr/local/bin/cloudflared (where binary is installed)
- Cleaner installation - No more sudo or GPG verification failures

# Run directly from GitHub
curl -sSL https://raw.githubusercontent.com/Muneeb-Nazir/cloudflared-lxc-installer/main/install-cloudflared-pve9.sh | bash
This method is much more reliable and will work on any Debian-based container without GPG or repository issues!




**Note**: This script is community-maintained and not officially supported by Cloudflare or Proxmox. Always test in a non-production environment first.
