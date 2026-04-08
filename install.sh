#!/bin/bash

# Server Transcode Installation Script
# Usage: curl -fsSL https://raw.githubusercontent.com/zergolf1994/server-transcode-releases/main/install.sh | sudo -E bash -s -- [OPTIONS]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
WORKER_COUNT=1
UNINSTALL=false
MONGODB_URI=""
STORAGE_ID=""
STORAGE_PATH="/home/files"
NODE_VERSION="22"

APP_NAME="server-transcode"
APP_DIR="/opt/$APP_NAME"
SERVICE_NAME="server-transcode"
URL_BASE="https://raw.githubusercontent.com/zergolf1994/server-transcode-releases/main"

# Functions
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        -n|--count)
            WORKER_COUNT="$2"
            shift 2
            ;;
        --mongodb-uri)
            MONGODB_URI="$2"
            shift 2
            ;;
        --storage-id)
            STORAGE_ID="$2"
            shift 2
            ;;
        --storage-path)
            STORAGE_PATH="$2"
            shift 2
            ;;
        --node-version)
            NODE_VERSION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Server Transcode Installer"
            echo ""
            echo "Usage: curl -fsSL $URL_BASE/install.sh | sudo -E bash -s -- [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --uninstall          Uninstall completely"
            echo "  -n, --count NUM      Number of worker instances (default: 1)"
            echo "  --mongodb-uri URI    MongoDB connection string"
            echo "  --storage-id ID      Storage ID"
            echo "  --storage-path DIR   Storage path (default: /home/files)"
            echo "  --node-version VER   Node.js version (default: 22)"
            echo "  -h, --help           Show this help message"
            echo ""
            echo "Examples:"
            echo "  # Install with 1 worker (default)"
            echo "  curl -fsSL $URL_BASE/install.sh | sudo -E bash"
            echo ""
            echo "  # Install with 2 workers"
            echo "  curl -fsSL $URL_BASE/install.sh | sudo -E bash -s -- -n 2"
            echo ""
            echo "  # Install with MongoDB URI"
            echo "  curl -fsSL $URL_BASE/install.sh | sudo -E bash -s -- \\"
            echo "      --mongodb-uri \"mongodb+srv://user:pass@host/dbname\" \\"
            echo "      --storage-id \"storage1\" -n 2"
            echo ""
            echo "  # Uninstall entirely"
            echo "  curl -fsSL $URL_BASE/install.sh | sudo -E bash -s -- --uninstall"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ==========================================
# Uninstallation
# ==========================================
if [ "$UNINSTALL" = true ]; then
    print_warning "⚠️  Starting Uninstallation..."

    # Stop and disable all worker instances
    print_status "Stopping and disabling services..."
    for i in $(seq 1 20); do
        systemctl stop "${SERVICE_NAME}@${i}" 2>/dev/null || true
        systemctl disable "${SERVICE_NAME}@${i}" 2>/dev/null || true
    done

    # Also stop single instance service if exists
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}" 2>/dev/null || true

    # Remove systemd service template
    if [ -f "/etc/systemd/system/${SERVICE_NAME}@.service" ]; then
        print_status "Removing systemd service template..."
        rm "/etc/systemd/system/${SERVICE_NAME}@.service"
    fi

    # Remove single instance service if exists
    if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
        print_status "Removing systemd service file..."
        rm "/etc/systemd/system/${SERVICE_NAME}.service"
    fi

    systemctl daemon-reload

    # Remove application directory
    if [ -d "$APP_DIR" ]; then
        print_status "Removing application directory..."
        rm -rf "$APP_DIR"
    fi

    print_status "✅ Uninstallation completed successfully!"
    exit 0
fi

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

print_status "🚀 Starting Installation..."
print_status "Configuration: Workers=$WORKER_COUNT"

# ==========================================
# Install System Dependencies
# ==========================================
print_status "Updating system packages..."
if command -v apt-get &> /dev/null; then
    apt-get update -qq
    print_status "Installing dependencies (curl, jq, ffmpeg)..."
    apt-get install -y -qq curl jq ffmpeg
elif command -v yum &> /dev/null; then
    yum install -y curl jq ffmpeg
elif command -v dnf &> /dev/null; then
    dnf install -y curl jq ffmpeg
fi

# Check if required commands exist
print_status "Checking required commands..."
for cmd in curl jq ffmpeg; do
    if ! command -v $cmd &> /dev/null; then
        print_error "$cmd is not installed. Please install it and try again."
        exit 1
    fi
done
print_status "All required system commands are installed."

# Check GPU availability (informational)
print_status "Checking GPU availability..."
if command -v nvidia-smi &> /dev/null; then
    GPU_INFO=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    if [ -n "$GPU_INFO" ]; then
        print_status "NVIDIA GPU detected: $GPU_INFO"
    else
        print_warning "nvidia-smi found but no GPU detected. Will use CPU fallback."
    fi
else
    print_warning "No NVIDIA GPU detected. Transcoding will use CPU (slower)."
fi

# ==========================================
# Install Node.js (via NVM)
# ==========================================
print_status "Installing Node.js $NODE_VERSION via NVM..."

export NVM_DIR="${NVM_DIR:-/root/.nvm}"

if [ ! -d "$NVM_DIR" ]; then
    print_status "Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi

# Load NVM
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Source bashrc to ensure nvm is available
source ~/.bashrc 2>/dev/null || true

# Reload NVM after sourcing bashrc
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

if ! command -v nvm &> /dev/null; then
    print_error "Failed to load NVM. Please run: source ~/.bashrc && re-run this script"
    exit 1
fi

nvm install $NODE_VERSION
nvm use $NODE_VERSION
nvm alias default $NODE_VERSION

print_status "Node.js version: $(node --version)"
print_status "npm version: $(npm --version)"

# ==========================================
# Stop existing services
# ==========================================
print_status "Stopping existing services (if running)..."
systemctl stop ${SERVICE_NAME}@* 2>/dev/null || true
systemctl stop ${SERVICE_NAME} 2>/dev/null || true

# ==========================================
# Create application directory
# ==========================================
print_status "Creating application directory: $APP_DIR"
mkdir -p "$APP_DIR"
mkdir -p "$APP_DIR/scripts"
cd "$APP_DIR"

# ==========================================
# Determine architecture & download binary
# ==========================================
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    BINARY="server-transcode-linux"
elif [ "$ARCH" = "aarch64" ]; then
    BINARY="server-transcode-linux-arm64"
else
    print_error "Unsupported architecture: $ARCH"
    exit 1
fi

print_status "Downloading binary ($BINARY)..."
curl -fsSL "$URL_BASE/$BINARY" -o "$APP_DIR/$APP_NAME"
chmod +x "$APP_DIR/$APP_NAME"
print_status "Binary downloaded successfully."

# ==========================================
# Download SCP scripts & install npm deps
# ==========================================
print_status "Downloading SCP scripts..."
curl -fsSL "$URL_BASE/scripts/package.json" -o "$APP_DIR/scripts/package.json"
curl -fsSL "$URL_BASE/scripts/scp-upload.js" -o "$APP_DIR/scripts/scp-upload.js"
curl -fsSL "$URL_BASE/scripts/scp-download.js" -o "$APP_DIR/scripts/scp-download.js"

print_status "Installing npm dependencies for SCP..."
cd "$APP_DIR/scripts"
npm install --production
cd "$APP_DIR"

print_status "SCP scripts installed successfully."

# ==========================================
# Create .env file
# ==========================================
print_status "Creating .env file..."
cat > "$APP_DIR/.env" <<EOF
MONGODB_URI=$MONGODB_URI
STORAGE_ID=$STORAGE_ID
STORAGE_PATH=$STORAGE_PATH
EOF
print_status ".env file created."

# ==========================================
# Create systemd service template
# ==========================================
print_status "Creating systemd service template..."

# Get node path for systemd
NODE_PATH=$(which node)
NODE_DIR=$(dirname "$NODE_PATH")

cat > /etc/systemd/system/${SERVICE_NAME}@.service <<EOF
[Unit]
Description=Server Transcode Service - Worker %i
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/$APP_NAME
Restart=always
RestartSec=5
EnvironmentFile=$APP_DIR/.env
Environment="WORKER_ID=$(hostname)-transcode-%i"
Environment="PATH=$NODE_DIR:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=multi-user.target
EOF
print_status "Systemd service template created."

# ==========================================
# Reload systemd, enable & start workers
# ==========================================
print_status "Reloading systemd daemon..."
systemctl daemon-reload

print_status "Starting $WORKER_COUNT worker(s)..."
for i in $(seq 1 $WORKER_COUNT); do
    systemctl enable ${SERVICE_NAME}@$i
    systemctl start ${SERVICE_NAME}@$i
    sleep 0.3
done

# ==========================================
# Verify services
# ==========================================
sleep 2
print_status "Verifying services..."
RUNNING=0
for i in $(seq 1 $WORKER_COUNT); do
    if systemctl is-active --quiet ${SERVICE_NAME}@$i; then
        RUNNING=$((RUNNING + 1))
    fi
done

if [ $RUNNING -eq $WORKER_COUNT ]; then
    echo ""
    echo "============================================"
    print_status "✅ Installation completed successfully!"
    echo "============================================"
    echo ""
    echo "  Service:    ${SERVICE_NAME}@{1..$WORKER_COUNT}"
    echo "  Running:    $RUNNING of $WORKER_COUNT workers"
    echo "  Directory:  $APP_DIR"
    echo "  Binary:     $APP_DIR/$APP_NAME"
    echo "  Node.js:    $(node --version)"
    echo "  SCP Script: $APP_DIR/scripts/"
    echo ""
    echo "  Commands:"
    echo "    View logs:     journalctl -u \"${SERVICE_NAME}@*\" -f"
    echo "    View worker 1: journalctl -u \"${SERVICE_NAME}@1\" -f"
    echo "    Stop all:      for i in \$(seq 1 $WORKER_COUNT); do systemctl stop ${SERVICE_NAME}@\$i; done"
    echo "    Restart all:   for i in \$(seq 1 $WORKER_COUNT); do systemctl restart ${SERVICE_NAME}@\$i; done"
    echo "============================================"
else
    print_warning "$RUNNING of $WORKER_COUNT workers are running. Checking logs..."
    journalctl -u "${SERVICE_NAME}@1" -n 10 --no-pager
fi
