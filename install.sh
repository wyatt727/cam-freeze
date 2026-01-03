#!/bin/bash
# OBS Camera Freeze Installer

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OBS_WS_PASSWORD="U9FeMZxbPH86GPBtftMY"
GUIDED_MODE="false"

# Parse flags
for arg in "$@"; do
    case $arg in
        --guided)
            GUIDED_MODE="true"
            shift
            ;;
    esac
done

echo
echo -e "${BOLD}${CYAN}  ╔═══════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}  ║     🎥 OBS Camera Freeze Installer    ║${NC}"
echo -e "${BOLD}${CYAN}  ╚═══════════════════════════════════════╝${NC}"
echo

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    echo -e "${BLUE}▶${NC} Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install OBS
if ! [ -d "/Applications/OBS.app" ] && ! command -v obs &> /dev/null; then
    echo -e "${BLUE}▶${NC} Installing OBS Studio..."
    brew install --cask obs
else
    echo -e "${GREEN}✓${NC} OBS Studio already installed"
fi

# Install Hammerspoon
if ! [ -d "/Applications/Hammerspoon.app" ]; then
    echo -e "${BLUE}▶${NC} Installing Hammerspoon..."
    brew install --cask hammerspoon
else
    echo -e "${GREEN}✓${NC} Hammerspoon already installed"
fi

# Install Python websockets
echo -e "${BLUE}▶${NC} Installing Python websockets..."
pip3 install --user websockets -q 2>/dev/null || pip3 install websockets --break-system-packages -q 2>/dev/null || true

# Copy cam-freeze script
echo -e "${BLUE}▶${NC} Installing cam-freeze script..."
sudo cp "$SCRIPT_DIR/cam-freeze" /usr/local/bin/cam-freeze
sudo chmod 755 /usr/local/bin/cam-freeze

# Set up Hammerspoon config
echo -e "${BLUE}▶${NC} Setting up Hammerspoon config..."
mkdir -p ~/.hammerspoon
cp "$SCRIPT_DIR/hammerspoon-config.lua" ~/.hammerspoon/init.lua

# Configure OBS WebSocket
echo -e "${BLUE}▶${NC} Configuring OBS WebSocket..."
OBS_WS_CONFIG_DIR="$HOME/Library/Application Support/obs-studio/plugin_config/obs-websocket"
mkdir -p "$OBS_WS_CONFIG_DIR"

cat > "$OBS_WS_CONFIG_DIR/config.json" << EOF
{
  "alerts_enabled": false,
  "auth_required": true,
  "first_load": false,
  "server_enabled": true,
  "server_password": "$OBS_WS_PASSWORD",
  "server_port": 4455
}
EOF

# Create OBS scene with camera
OBS_SCENES_DIR="$HOME/Library/Application Support/obs-studio/basic/scenes"
mkdir -p "$OBS_SCENES_DIR"

# Detect default camera device UUID (exclude OBS Virtual Camera)
echo -e "${BLUE}▶${NC} Detecting default camera..."
CAMERA_UUID=$(system_profiler SPCameraDataType 2>/dev/null | grep -B5 "Unique ID:" | grep -v "OBS Virtual" | grep "Unique ID:" | head -1 | awk '{print $3}')
if [ -z "$CAMERA_UUID" ]; then
    echo -e "${YELLOW}⚠${NC} Could not detect camera. You may need to manually select it in OBS."
    CAMERA_UUID=""
else
    echo -e "${GREEN}✓${NC} Found camera: ${DIM}$CAMERA_UUID${NC}"
fi

echo -e "${BLUE}▶${NC} Creating OBS scene with camera..."
cat > "$OBS_SCENES_DIR/Untitled.json" << EOF
{
    "current_scene": "Scene",
    "current_program_scene": "Scene",
    "scene_order": [{"name": "Scene"}],
    "name": "Untitled",
    "sources": [
        {
            "name": "Scene",
            "uuid": "scene-uuid-001",
            "id": "scene",
            "versioned_id": "scene",
            "settings": {
                "id_counter": 1,
                "custom_size": false,
                "items": [
                    {
                        "name": "Video Capture Device",
                        "source_uuid": "camera-uuid-001",
                        "visible": true,
                        "locked": false,
                        "rot": 0.0,
                        "pos": {"x": 0.0, "y": 0.0},
                        "scale": {"x": 1.5, "y": 1.5},
                        "align": 5,
                        "bounds_type": 0,
                        "bounds_align": 0,
                        "crop_left": 0,
                        "crop_top": 0,
                        "crop_right": 0,
                        "crop_bottom": 0,
                        "id": 1,
                        "group_item_backup": false
                    }
                ]
            },
            "mixers": 0,
            "enabled": true
        },
        {
            "name": "Video Capture Device",
            "uuid": "camera-uuid-001",
            "id": "macos-avcapture",
            "versioned_id": "macos-avcapture",
            "settings": {
                "device": "$CAMERA_UUID",
                "use_preset": true,
                "preset": "AVCaptureSessionPreset1280x720"
            },
            "mixers": 255,
            "enabled": true,
            "muted": false
        }
    ],
    "groups": [],
    "transitions": [],
    "virtual-camera": {"type2": 4}
}
EOF

# Install OBS MCP server for Claude Code
if command -v npx &> /dev/null; then
    echo -e "${BLUE}▶${NC} Installing OBS MCP server for Claude Code..."

    # Configure Claude settings with MCP server
    CLAUDE_SETTINGS="$HOME/.claude/settings.json"
    mkdir -p "$HOME/.claude"

    if [ -f "$CLAUDE_SETTINGS" ]; then
        # Update existing settings
        python3 << PYEOF
import json
import os

settings_path = os.path.expanduser("~/.claude/settings.json")
with open(settings_path, 'r') as f:
    settings = json.load(f)

if 'mcpServers' not in settings:
    settings['mcpServers'] = {}

settings['mcpServers']['obs-mcp'] = {
    "command": "npx",
    "args": ["-y", "obs-mcp"],
    "env": {
        "OBS_WEBSOCKET_PASSWORD": "$OBS_WS_PASSWORD"
    }
}

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
PYEOF
        echo -e "${GREEN}✓${NC} Claude MCP settings updated"
    else
        # Create new settings
        cat > "$CLAUDE_SETTINGS" << JSONEOF
{
  "mcpServers": {
    "obs-mcp": {
      "command": "npx",
      "args": ["-y", "obs-mcp"],
      "env": {
        "OBS_WEBSOCKET_PASSWORD": "$OBS_WS_PASSWORD"
      }
    }
  }
}
JSONEOF
        echo -e "${GREEN}✓${NC} Created Claude MCP settings"
    fi
else
    echo -e "${DIM}  Skipping Claude MCP (npx not found)${NC}"
fi

# Restart Hammerspoon
echo "Restarting Hammerspoon..."
killall Hammerspoon 2>/dev/null || true
sleep 1
open -a Hammerspoon

# Guided permission setup (only with --guided flag)
if [ "$GUIDED_MODE" = "true" ]; then
    echo
    echo "=== Guided Permission Setup ==="
    echo

    # Hammerspoon Accessibility
    echo "Step 1/3: Hammerspoon Accessibility"
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    sleep 0.5
    open -a "System Settings"
    osascript -e 'display dialog "Enable Hammerspoon in the Accessibility list.\n\n1. Click the + button (if Hammerspoon not listed)\n2. Find and select Hammerspoon\n3. Enable the checkbox\n\nClick Done when complete." with title "Step 1/3: Accessibility" buttons {"Done"} default button "Done"'

    # OBS Camera
    echo "Step 2/3: OBS Camera Permission"
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
    sleep 0.5
    open -a "System Settings"
    osascript -e 'display dialog "Enable OBS in the Camera list.\n\n1. Find OBS in the list\n2. Enable the checkbox\n\nIf OBS is not listed, open OBS once first.\n\nClick Done when complete." with title "Step 2/3: Camera" buttons {"Done"} default button "Done"'

    # OBS Virtual Camera Extension
    echo "Step 3/3: OBS Virtual Camera Extension"
    open "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    sleep 0.5
    open -a "System Settings"
    osascript -e 'display dialog "Enable the OBS Virtual Camera extension.\n\n1. Scroll down to \"Camera Extensions\"\n2. Enable \"OBS Virtual Camera\"\n\nIf not listed, open OBS and click \"Start Virtual Camera\" first.\n\nClick Done when complete." with title "Step 3/3: Camera Extension" buttons {"Done"} default button "Done"'

    echo "✓ Guided setup complete"
fi

echo
echo "=== Installation Complete ==="
echo

if [ "$GUIDED_MODE" = "false" ]; then
    echo "Grant permissions in System Settings:"
    echo "  - Privacy & Security → Accessibility → Enable Hammerspoon"
    echo "  - Privacy & Security → Camera → Enable OBS"
    echo "  - General → Login Items → Camera Extensions → Enable OBS"
    echo
    echo "(Run './install.sh --guided' for step-by-step permission setup)"
    echo
fi
echo "Don't forget to select 'OBS Virtual Camera' in your video app (Zoom, Meet, etc.)"
echo
echo "Press Cmd+Shift+F to freeze/unfreeze!"
echo
echo "WebSocket Password: $OBS_WS_PASSWORD"
