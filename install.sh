#!/bin/bash
# OBS Camera Freeze Installer

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OBS_WS_PASSWORD="U9FeMZxbPH86GPBtftMY"

echo "=== OBS Camera Freeze Installer ==="
echo

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install OBS
if ! [ -d "/Applications/OBS.app" ] && ! command -v obs &> /dev/null; then
    echo "Installing OBS Studio..."
    brew install --cask obs
else
    echo "OBS Studio already installed"
fi

# Install Hammerspoon
if ! [ -d "/Applications/Hammerspoon.app" ]; then
    echo "Installing Hammerspoon..."
    brew install --cask hammerspoon
else
    echo "Hammerspoon already installed"
fi

# Install Python websockets
echo "Installing Python websockets..."
pip3 install --user websockets -q 2>/dev/null || pip3 install websockets --break-system-packages -q 2>/dev/null || echo "websockets may already be installed"

# Copy cam-freeze script
echo "Installing cam-freeze script..."
sudo cp "$SCRIPT_DIR/cam-freeze" /usr/local/bin/cam-freeze
sudo chmod 755 /usr/local/bin/cam-freeze

# Set up Hammerspoon config
echo "Setting up Hammerspoon config..."
mkdir -p ~/.hammerspoon
cp "$SCRIPT_DIR/hammerspoon-config.lua" ~/.hammerspoon/init.lua

# Configure OBS WebSocket
echo "Configuring OBS WebSocket..."
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
echo "Detecting default camera..."
CAMERA_UUID=$(system_profiler SPCameraDataType 2>/dev/null | grep -B5 "Unique ID:" | grep -v "OBS Virtual" | grep "Unique ID:" | head -1 | awk '{print $3}')
if [ -z "$CAMERA_UUID" ]; then
    echo "Warning: Could not detect camera. You may need to manually select it in OBS."
    CAMERA_UUID=""
else
    echo "Found camera: $CAMERA_UUID"
fi

echo "Creating OBS scene with camera..."
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
    echo "Installing OBS MCP server for Claude Code..."

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

print("Claude MCP settings updated with OBS server")
PYEOF
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
        echo "Created Claude settings with OBS MCP server"
    fi
else
    echo "npx not found - skipping Claude MCP installation"
    echo "To install manually: npx @anthropic-ai/claude-code mcp add obs-mcp -- npx -y obs-mcp"
fi

# Permission check functions
check_accessibility_permission() {
    local app_id="$1"
    # Check system TCC database for accessibility permission
    # auth_value=2 means granted, auth_value=0 means denied
    local result=$(sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
        "SELECT auth_value FROM access WHERE service='kTCCServiceAccessibility' AND client='$app_id';" 2>/dev/null)
    [ "$result" = "2" ]
}

check_camera_permission() {
    local app_id="$1"
    # Check user TCC database for camera permission
    local result=$(sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
        "SELECT auth_value FROM access WHERE service='kTCCServiceCamera' AND client='$app_id';" 2>/dev/null)
    [ "$result" = "2" ]
}

check_system_extension() {
    # Check if OBS Virtual Camera extension is enabled
    # This checks if the system extension is loaded
    systemextensionsctl list 2>/dev/null | grep -q "com.obsproject.obs-studio" && \
    systemextensionsctl list 2>/dev/null | grep "com.obsproject.obs-studio" | grep -q "enabled"
}

prompt_permission() {
    local title="$1"
    local message="$2"
    local settings_url="$3"

    # Open the relevant System Settings pane
    open "$settings_url"

    # Show dialog to guide user
    osascript -e "display dialog \"$message\" with title \"$title\" buttons {\"Done\"} default button \"Done\""
}

# Restart Hammerspoon
echo "Restarting Hammerspoon..."
killall Hammerspoon 2>/dev/null || true
sleep 1
open -a Hammerspoon

echo
echo "=== Checking Permissions ==="
echo

# Check and prompt for Hammerspoon Accessibility
if ! check_accessibility_permission "org.hammerspoon.Hammerspoon"; then
    echo "Hammerspoon needs Accessibility permission..."
    prompt_permission "Accessibility Permission Required" \
        "Please enable Hammerspoon in the Accessibility list.\n\n1. Click the + button\n2. Find and select Hammerspoon\n3. Enable the checkbox\n\nClick Done when complete." \
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
else
    echo "✓ Hammerspoon already has Accessibility permission"
fi

# Check and prompt for OBS Camera
if ! check_camera_permission "com.obsproject.obs-studio"; then
    echo "OBS needs Camera permission..."
    prompt_permission "Camera Permission Required" \
        "Please enable OBS in the Camera list.\n\n1. Find OBS in the list\n2. Enable the checkbox\n\nIf OBS is not listed, open OBS once and it will request permission.\n\nClick Done when complete." \
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
else
    echo "✓ OBS already has Camera permission"
fi

# Check and prompt for OBS Virtual Camera extension
if ! check_system_extension; then
    echo "OBS Virtual Camera extension needs to be enabled..."
    prompt_permission "Camera Extension Required" \
        "Please enable the OBS Virtual Camera extension.\n\n1. Scroll down to 'Camera Extensions'\n2. Enable 'OBS Virtual Camera'\n\nIf not listed, open OBS and click 'Start Virtual Camera' first.\n\nClick Done when complete." \
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Login%20Items"
else
    echo "✓ OBS Virtual Camera extension already enabled"
fi

echo
echo "=== Installation Complete ==="
echo
echo "Next steps:"
echo "1. Open OBS and click 'Start Virtual Camera' (bottom right)"
echo "   - A scene with your default camera is already configured"
echo
echo "2. In Zoom/Meet, select 'OBS Virtual Camera' as your camera"
echo
echo "3. Press Cmd+Shift+F to freeze/unfreeze!"
echo
echo "WebSocket Password: $OBS_WS_PASSWORD"
