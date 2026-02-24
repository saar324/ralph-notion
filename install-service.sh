#!/bin/bash

# Install Ralph Notion as a systemd service
# Usage: ./install-service.sh /path/to/project

set -e

PROJECT_DIR="${1:-$(pwd)}"
RALPH_HOME="${RALPH_HOME:-$HOME/.ralph-notion}"
SERVICE_NAME="ralph-notion"

# Validate
if [[ ! -f "$PROJECT_DIR/.ralphrc" ]]; then
    echo "Error: No .ralphrc found in $PROJECT_DIR"
    echo "Create .ralphrc first with your Notion configuration"
    exit 1
fi

if [[ ! -f "$RALPH_HOME/ralph_loop.sh" ]]; then
    echo "Error: ralph_loop.sh not found in $RALPH_HOME"
    exit 1
fi

echo "Installing Ralph Notion service..."
echo "  Project directory: $PROJECT_DIR"
echo "  Ralph home: $RALPH_HOME"

# Create service file with correct paths
cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Ralph Notion Loop - Autonomous Claude Code Task Runner
After=network.target

[Service]
Type=simple
WorkingDirectory=$PROJECT_DIR
ExecStart=$RALPH_HOME/ralph_loop.sh --notion
Restart=on-failure
RestartSec=30
Environment=HOME=$HOME
Environment=PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin:$HOME/.npm-global/bin

# Logging
StandardOutput=append:/var/log/ralph-notion.log
StandardError=append:/var/log/ralph-notion.log

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
systemctl daemon-reload

# Enable service (start on boot)
systemctl enable ${SERVICE_NAME}

# Start service now
systemctl start ${SERVICE_NAME}

echo ""
echo "✅ Ralph Notion service installed and started!"
echo ""
echo "Commands:"
echo "  systemctl status ralph-notion   # Check status"
echo "  systemctl stop ralph-notion     # Stop"
echo "  systemctl start ralph-notion    # Start"
echo "  systemctl restart ralph-notion  # Restart"
echo "  journalctl -u ralph-notion -f   # View logs"
echo "  tail -f /var/log/ralph-notion.log  # View logs (alt)"
