#!/usr/bin/env bash
set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[x]${NC} $1"; }
heading() { echo -e "\n${BOLD}$1${NC}"; }

BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/quickshell/wallpaper"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


heading "Checking dependencies..."

MISSING=()
for dep in quickshell ffmpeg swww jq; do
    if command -v "$dep" &>/dev/null; then
        info "$dep found"
    else
        warn "$dep not found"
        MISSING+=("$dep")
    fi
done

if command -v wl-copy &>/dev/null; then
    info "wl-clipboard found"
else
    warn "wl-clipboard not found — :id command won't work"
fi

if command -v wal &>/dev/null; then
    info "pywal found (system)"
    WAL_CMD="wal"
elif [[ -f "$HOME/.local/venvs/pywal/bin/wal" ]]; then
    info "pywal found (venv at ~/.local/venvs/pywal)"
    WAL_CMD="$HOME/.local/venvs/pywal/bin/wal"
else
    warn "pywal not found — color scheme generation will be skipped"
    WAL_CMD=""
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
    error "Missing required dependencies: ${MISSING[*]}"
    echo "Please install them and re-run this script."
    exit 1
fi


heading "linux-wallpaperengine setup..."

DEFAULT_ENGINE="$HOME/linux-wallpaperengine/build/output/linux-wallpaperengine"
echo -e "Enter the path to your linux-wallpaperengine binary."
echo -e "Press Enter to use the default: ${YELLOW}$DEFAULT_ENGINE${NC}"
read -rp "Path: " ENGINE_PATH
ENGINE_PATH="${ENGINE_PATH:-$DEFAULT_ENGINE}"

if [[ ! -f "$ENGINE_PATH" ]]; then
    warn "Binary not found at: $ENGINE_PATH"
    warn "You can update the path later in wallpaper-apply.sh"
else
    info "Engine found at: $ENGINE_PATH"
fi


heading "Wallpaper engine settings..."

echo -e "Enter wallpaper FPS (default: 60):"
read -rp "FPS: " WALLPAPER_FPS
WALLPAPER_FPS="${WALLPAPER_FPS:-60}"


heading "Installing wallpaper picker..."

mkdir -p "$CONFIG_DIR"
cp -r "$SCRIPT_DIR/qml/"* "$CONFIG_DIR/"
info "QML files installed to $CONFIG_DIR"


heading "Installing wallpaper scripts..."

mkdir -p "$BIN_DIR"

cp "$SCRIPT_DIR/scripts/wallpaper-apply.sh" "$BIN_DIR/wallpaper-apply.sh"
sed -i "s|WALLPAPER_ENGINE_BIN=.*|WALLPAPER_ENGINE_BIN=\"$ENGINE_PATH\"|" "$BIN_DIR/wallpaper-apply.sh"
sed -i "s|WALLPAPER_FPS=.*|WALLPAPER_FPS=$WALLPAPER_FPS|" "$BIN_DIR/wallpaper-apply.sh"
sed -i "s|WAL_CMD=.*|WAL_CMD=\"$WAL_CMD\"|" "$BIN_DIR/wallpaper-apply.sh"

cp "$SCRIPT_DIR/scripts/wallpaper-apply-static.sh" "$BIN_DIR/wallpaper-apply-static.sh"
sed -i "s|WAL_CMD=.*|WAL_CMD=\"$WAL_CMD\"|" "$BIN_DIR/wallpaper-apply-static.sh"

cp "$SCRIPT_DIR/scripts/wallpaper-startup.sh" "$BIN_DIR/wallpaper-startup.sh"
sed -i "s|WALLPAPER_ENGINE_BIN=.*|WALLPAPER_ENGINE_BIN=\"$ENGINE_PATH\"|" "$BIN_DIR/wallpaper-startup.sh"
sed -i "s|WALLPAPER_FPS=.*|WALLPAPER_FPS=$WALLPAPER_FPS|" "$BIN_DIR/wallpaper-startup.sh"

cp "$SCRIPT_DIR/scripts/wallpaper-selector.sh" "$BIN_DIR/wallpaper-selector.sh"
sed -i "s|CONFIG_DIR=.*|CONFIG_DIR=\"$CONFIG_DIR\"|" "$BIN_DIR/wallpaper-selector.sh"

heading "Wallpaper reloader..."
echo -e "Linux wallpaper engine has known memory leak issues, this optional script"
echo -e "restarts it automatically when memory usage exceeds a threshold."
echo -e "If installed, add it to your compositor's autostart. Example for Hyprland:"
echo -e "  ${YELLOW}exec-once = /bin/bash \$HOME/.local/bin/wallpaper-reloader.sh${NC}"
echo ""
read -rp "Install wallpaper reloader? [Y/n] " install_reloader
install_reloader="${install_reloader:-Y}"

if [[ "${install_reloader,,}" == "y" ]]; then
    cp "$SCRIPT_DIR/scripts/wallpaper-reloader.sh" "$BIN_DIR/wallpaper-reloader.sh"
    chmod +x "$BIN_DIR/wallpaper-reloader.sh"
    info "Reloader installed to $BIN_DIR/wallpaper-reloader.sh"
else
    info "Skipping reloader installation."
fi

cp "$SCRIPT_DIR/scripts/wallpaper-playlist.sh" "$BIN_DIR/wallpaper-playlist.sh"
sed -i "s|SETTINGS=.*|SETTINGS=\"$CONFIG_DIR/settings.json\"|" "$BIN_DIR/wallpaper-playlist.sh"
chmod +x "$BIN_DIR/wallpaper-playlist.sh"
info "Playlist daemon installed to $BIN_DIR/wallpaper-playlist.sh"

cat > "$BIN_DIR/wallpaper-selector.sh" << SCRIPT
#!/usr/bin/env bash
export PATH="\$HOME/.local/bin:\$PATH"
export XDG_RUNTIME_DIR="/run/user/\$(id -u)"

$(if [[ -n "$WAL_CMD" && "$WAL_CMD" == *venv* ]]; then
    echo "source \"$HOME/.local/venvs/pywal/bin/activate\""
fi)

QML_XHR_ALLOW_FILE_READ=1 quickshell -p "$CONFIG_DIR"
SCRIPT

chmod +x \
    "$BIN_DIR/wallpaper-apply.sh" \
    "$BIN_DIR/wallpaper-apply-static.sh" \
    "$BIN_DIR/wallpaper-startup.sh" \
    "$BIN_DIR/wallpaper-selector.sh"

info "Scripts installed to $BIN_DIR"


heading "Installation complete!"
echo ""
echo -e "${BOLD}Launch the wallpaper selector:${NC}"
echo -e "  ${YELLOW}$BIN_DIR/wallpaper-selector.sh${NC}"
echo ""
echo -e "${BOLD}Add to your compositor autostart (Hyprland example):${NC}"
echo -e "  ${YELLOW}exec-once = /bin/bash $BIN_DIR/wallpaper-startup.sh${NC}"
echo ""
echo -e "${BOLD}Add a keybind to open the wallpaper selector (Hyprland example):${NC}"
echo -e "  ${YELLOW}bindr = SUPER, C, exec, /bin/bash $BIN_DIR/wallpaper-selector.sh${NC}"
echo -e "  (using ${YELLOW}bindr${NC} instead of ${YELLOW}bind${NC} so holding Super+C doesn't reopen it)"
echo ""
if [[ "${install_reloader,,}" == "y" ]]; then
echo -e "${BOLD}Add the reloader to autostart (Hyprland example):${NC}"
echo -e "  ${YELLOW}exec-once = /bin/bash $BIN_DIR/wallpaper-reloader.sh${NC}"
echo ""
fi
echo -e "${BOLD}Config locations:${NC}"
echo -e "  Wallpaper selector:  ${YELLOW}$CONFIG_DIR${NC}"
echo -e "  Scripts: ${YELLOW}$BIN_DIR${NC}"
echo ""
info "Make sure $BIN_DIR is in your PATH."