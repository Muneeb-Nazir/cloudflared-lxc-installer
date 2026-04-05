#!/usr/bin/env bash
# Cloudflared LXC Installer for Proxmox VE 9.x
# With Debian 13 (Trixie) support and updated Cloudflared installation

set -euo pipefail

# Color codes
YW="\033[33m"
BL="\033[36m"
RD="\033[01;31m"
GN="\033[1;92m"
CL="\033[m"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

# Configuration
CT_ID=""
CT_HOSTNAME="cloudflared"
CT_DISK_SIZE="2"
CT_CORES="1"
CT_RAM="512"
CT_BRIDGE="vmbr0"
CT_IP="dhcp"
CT_PASSWORD=""
CT_UNPRIVILEGED="1"
DEBIAN_VERSION="13"  # Default to Trixie

# Functions
msg_info() { echo -e "${BL}[INFO]${CL} $1"; }
msg_ok() { echo -e "${CM} ${GN}$1${CL}"; }
msg_error() { echo -e "${CROSS} ${RD}$1${CL}"; }

header_info() {
clear
cat <<"EOF"
   ________                ________                    __
  / ____/ /___  __  ______/ / __/ /___ _________  ____/ /
 / /   / / __ \/ / / / __  / /_/ / __ `/ ___/ _ \/ __  / 
/ /___/ / /_/ / /_/ / /_/ / __/ / /_/ / /  /  __/ /_/ /  
\____/_/\____/\__,_/\__,_/_/ /_/\__,_/_/   \___/\__,_/   
                                                         
EOF
}

check_pve_version() {
    msg_info "Checking Proxmox VE version"
    if ! pveversion | grep -q "pve-manager/9"; then
        msg_error "This script is designed for Proxmox VE 9.x"
        echo "Current version: $(pveversion)"
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        msg_ok "Proxmox VE 9.x detected"
    fi
}

get_storage() {
    # Find available storage for containers
    msg_info "Detecting available storage"
    
    # Check for ZFS storage first (preferred)
    STORAGE=$(pvesm status -content rootdir | awk 'NR>1 && $6 > 0 {print $1; exit}')
    
    if [ -z "$STORAGE" ]; then
        # Check for directory storage
        STORAGE=$(pvesm status -content vztmpl | awk 'NR>1 && $6 > 0 {print $1; exit}')
    fi
    
    if [ -z "$STORAGE" ]; then
        # Fallback to checking common storage names
        for storage in local-zfs local-lvm local; do
            if pvesm status -storage $storage &>/dev/null; then
                STORAGE=$storage
                break
            fi
        done
    fi
    
    if [ -z "$STORAGE" ]; then
        msg_error "No suitable storage found for containers"
        echo "Available storage:"
        pvesm status
        exit 1
    fi
    
    msg_ok "Using storage: $STORAGE"
}

get_template() {
    msg_info "Finding container template"
    
    # Update template list first
    msg_info "Updating template list"
    pveam update &>/dev/null || true
    
    # First, try to find Debian 13 (Trixie)
    TEMPLATE=$(pveam available | grep "debian-13" | grep amd64 | head -1 | awk '{print $2}')
    
    # If Debian 13 not found, try Debian 12 (Bookworm)
    if [ -z "$TEMPLATE" ]; then
        DEBIAN_VERSION="12"
        TEMPLATE=$(pveam available | grep "debian-12" | grep amd64 | head -1 | awk '{print $2}')
    fi
    
    if [ -z "$TEMPLATE" ]; then
        msg_error "No Debian template available"
        exit 1
    fi
    
    msg_ok "Using template: $TEMPLATE (Debian $DEBIAN_VERSION)"
}

get_next_ct_id() {
    CT_ID=$(pvesh get /cluster/nextid)
    msg_info "Next available CT ID: $CT_ID"
}

configure_container() {
    msg_info "Configuring container settings"
    
    # Ask for custom CT ID
    read -p "Enter Container ID (default: $CT_ID): " input_id
    CT_ID=${input_id:-$CT_ID}
    
    # Ask for hostname
    read -p "Enter Hostname (default: $CT_HOSTNAME): " input_hostname
    CT_HOSTNAME=${input_hostname:-$CT_HOSTNAME}
    
    # Ask for Debian version preference
    echo -e "\n${BL}Debian Version Options:${CL}"
    echo "1) Debian 13 (Trixie) - Latest - Recommended for PVE 9.x"
    echo "2) Debian 12 (Bookworm) - Stable"
    read -p "Choose Debian version (1-2, default: 1): " deb_choice
    DEBIAN_VERSION=$([ "${deb_choice:-1}" == "1" ] && echo "13" || echo "12")
    
    # Ask for disk size
    read -p "Enter Disk Size in GB (default: $CT_DISK_SIZE): " input_disk
    CT_DISK_SIZE=${input_disk:-$CT_DISK_SIZE}
    
    # Ask for cores
    read -p "Enter CPU Cores (default: $CT_CORES): " input_cores
    CT_CORES=${input_cores:-$CT_CORES}
    
    # Ask for RAM
    read -p "Enter RAM in MB (default: $CT_RAM): " input_ram
    CT_RAM=${input_ram:-$CT_RAM}
    
    # Ask for IP configuration
    read -p "Enter IP (dhcp for automatic, or CIDR like 192.168.1.100/24): " input_ip
    CT_IP=${input_ip:-$CT_IP}
    
    # Ask for password
    read -s -p "Enter root password (leave empty for automatic login): " input_pass
    echo
    if [ -n "$input_pass" ]; then
        CT_PASSWORD="-password $input_pass"
    fi
    
    # Update template based on chosen Debian version
    if [ "$DEBIAN_VERSION" == "13" ]; then
        TEMPLATE=$(pveam available | grep "debian-13" | grep amd64 | head -1 | awk '{print $2}')
    else
        TEMPLATE=$(pveam available | grep "debian-12" | grep amd64 | head -1 | awk '{print $2}')
    fi
    
    msg_ok "Container configured"
}

create_container() {
    msg_info "Creating LXC container (this may take a moment)"
    
    # Ensure template is available
    if [ -z "$TEMPLATE" ] || [ "$TEMPLATE" == "" ]; then
        msg_error "No template selected"
        get_template
    fi
    
    # Check if we need to download the template
    if ! pveam list $STORAGE | grep -q "$(basename $TEMPLATE)"; then
        msg_info "Downloading template: $TEMPLATE"
        pveam download $STORAGE $TEMPLATE
    fi
    
    TEMPLATE_FULL="$STORAGE:vztmpl/$TEMPLATE"
    
    # Delete existing container if it exists
    if pct status $CT_ID &>/dev/null; then
        msg_info "Container $CT_ID exists, stopping and destroying it"
        pct stop $CT_ID &>/dev/null || true
        pct destroy $CT_ID &>/dev/null || true
        sleep 2
    fi
    
    # Create the container
    if pct create $CT_ID $TEMPLATE_FULL \
        -arch amd64 \
        -cores $CT_CORES \
        -hostname $CT_HOSTNAME \
        -memory $CT_RAM \
        -net0 name=eth0,bridge=$CT_BRIDGE,ip=$CT_IP \
        -onboot 1 \
        -ostype debian \
        -rootfs $STORAGE:${CT_DISK_SIZE} \
        -unprivileged $CT_UNPRIVILEGED \
        -features keyctl=1,nesting=1 \
        $CT_PASSWORD; then
        
        msg_ok "Container created successfully"
    else
        msg_error "Failed to create container"
        exit 1
    fi
}

start_container() {
    msg_info "Starting container"
    pct start $CT_ID
    
    # Wait for container to be ready
    echo -n "Waiting for container to initialize"
    for i in {1..30}; do
        if pct status $CT_ID | grep -q "running"; then
            echo
            break
        fi
        echo -n "."
        sleep 1
    done
    
    # Additional wait for network
    sleep 5
    msg_ok "Container started"
}

install_cloudflared() {
    msg_info "Installing Cloudflared in container"
    
    # Wait for network to be ready
    pct exec $CT_ID -- bash -c "for i in {1..30}; do ping -c 1 8.8.8.8 &>/dev/null && break; sleep 1; done"
    
    # Install Cloudflared using the updated method
    pct exec $CT_ID -- bash -c "
        # Add cloudflare gpg key
        mkdir -p --mode=0755 /usr/share/keyrings
        curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
        
        # Add this repo to apt repositories
        echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list
        
        # Install cloudflared
        apt-get update && apt-get install -y cloudflared
    "
    
    # Verify installation
    if pct exec $CT_ID -- command -v cloudflared &>/dev/null; then
        msg_ok "Cloudflared installed successfully"
        CLOUDFLARED_VERSION=$(pct exec $CT_ID -- cloudflared --version)
        msg_info "$CLOUDFLARED_VERSION"
    else
        msg_error "Cloudflared installation failed"
        exit 1
    fi
}

configure_cloudflared() {
    msg_info "Configuring Cloudflared as a service"
    
    # Create cloudflared user if not exists
    pct exec $CT_ID -- bash -c "useradd -r -s /bin/false cloudflared || true"
    
    # Create systemd service
    pct exec $CT_ID -- bash -c "cat > /etc/systemd/system/cloudflared.service << 'EOF'
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=cloudflared
Group=cloudflared
ExecStart=/usr/bin/cloudflared tunnel --no-autoupdate
Restart=on-failure
RestartSec=5
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF"
    
    # Enable and start service
    pct exec $CT_ID -- bash -c "systemctl daemon-reload"
    pct exec $CT_ID -- bash -c "systemctl enable cloudflared.service"
    
    msg_ok "Cloudflared service configured"
}

show_instructions() {
    # Get container IP
    CT_IP_ADDR=$(pct exec $CT_ID -- ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
    
    echo -e "\n${GN}═══════════════════════════════════════════════════════════${CL}"
    echo -e "${GN}           CLOUDFLARED LXC INSTALLATION COMPLETE            ${CL}"
    echo -e "${GN}═══════════════════════════════════════════════════════════${CL}"
    echo -e ""
    echo -e "${BL}Container Details:${CL}"
    echo -e "  • Container ID:     ${YW}$CT_ID${CL}"
    echo -e "  • Hostname:         ${YW}$CT_HOSTNAME${CL}"
    echo -e "  • IP Address:       ${YW}${CT_IP_ADDR}${CL}"
    echo -e "  • Storage:          ${YW}$STORAGE${CL}"
    echo -e "  • Debian Version:   ${YW}$DEBIAN_VERSION${CL}"
    echo -e ""
    echo -e "${BL}Access Methods:${CL}"
    echo -e "  • pct enter $CT_ID"
    echo -e "  • lxc-attach -n $CT_ID"
    echo -e "  • ssh root@${CT_IP_ADDR} (if password set)"
    echo -e ""
    echo -e "${BL}Cloudflare Tunnel Setup:${CL}"
    echo -e "  ${YW}1.${CL} Login to Cloudflare:"
    echo -e "     pct exec $CT_ID -- cloudflared tunnel login"
    echo -e ""
    echo -e "  ${YW}2.${CL} Create a tunnel:"
    echo -e "     pct exec $CT_ID -- cloudflared tunnel create <tunnel-name>"
    echo -e ""
    echo -e "  ${YW}3.${CL} Route DNS:"
    echo -e "     pct exec $CT_ID -- cloudflared tunnel route dns <tunnel-name> <hostname>"
    echo -e ""
    echo -e "  ${YW}4.${CL} Create config.yml:"
    echo -e "     pct exec $CT_ID -- nano ~/.cloudflared/config.yml"
    echo -e ""
    echo -e "${BL}Service Management:${CL}"
    echo -e "  • Status:   pct exec $CT_ID -- systemctl status cloudflared"
    echo -e "  • Start:    pct exec $CT_ID -- systemctl start cloudflared"
    echo -e "  • Stop:     pct exec $CT_ID -- systemctl stop cloudflared"
    echo -e "  • Restart:  pct exec $CT_ID -- systemctl restart cloudflared"
    echo -e "  • Logs:     pct exec $CT_ID -- journalctl -u cloudflared -f"
    echo -e ""
    echo -e "${BL}Quick Test:${CL}"
    pct exec $CT_ID -- cloudflared --version
    echo -e ""
    echo -e "${GN}═══════════════════════════════════════════════════════════${CL}"
}

# Main execution
main() {
    header_info
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        msg_error "This script must be run as root"
        exit 1
    fi
    
    # Check if running on Proxmox
    if ! command -v pveversion &>/dev/null; then
        msg_error "This script must be run on a Proxmox VE host"
        exit 1
    fi
    
    check_pve_version
    get_storage
    get_template
    get_next_ct_id
    configure_container
    create_container
    start_container
    install_cloudflared
    configure_cloudflared
    show_instructions
}

# Run the script
main
