#!/usr/bin/env bash
cd "$(dirname "$0")"

WALLPAPER_ENGINE_BIN="$HOME/linux-wallpaperengine/build/output/linux-wallpaperengine"
WALLPAPER_FPS=60
SCREENSHOT_DIR="$HOME/.cache/wallpaper-screenshots"

mkdir -p "$SCREENSHOT_DIR"


WALLPAPER_DIR="$1"
if [[ -z "$WALLPAPER_DIR" || ! -d "$WALLPAPER_DIR" ]]; then
    echo "Usage: $0 <wallpaper_folder_path>"
    echo "Error: Folder does not exist: $WALLPAPER_DIR" >&2
    exit 1
fi

echo "$1" > ~/.cache/quickshell-last-wallpaper

find_preview_image() {
    local dir="$1"
    for img in preview.jpg preview.jpeg preview.png preview.gif thumbnail.jpg; do
        [[ -f "$dir/$img" ]] && { echo "$dir/$img"; return 0; }
    done
    [[ -f "$dir/project.json" ]] && jq -r '.preview // .thumbnail // empty' "$dir/project.json" 2>/dev/null | while read -r path; do
        [[ -f "$dir/$path" ]] && { echo "$dir/$path"; return 0; }
    done
    return 1
}


MONITORS=()
if command -v hyprctl >/dev/null 2>&1; then
    MONITORS=($(hyprctl monitors -j | jq -r '.[].name'))
elif command -v xrandr >/dev/null 2>&1; then
    MONITORS=($(xrandr --query | grep " connected" | awk '{print $1}'))
else
    MONITORS=("eDP-1")
fi
[[ ${#MONITORS[@]} -eq 0 ]] && MONITORS=("eDP-1")


pkill -f "$WALLPAPER_ENGINE_BIN" 2>/dev/null || true
sleep 0.5

WALLPAPER_IMAGE=""
if PREVIEW_IMAGE=$(find_preview_image "$WALLPAPER_DIR"); then
    WALLPAPER_IMAGE="$PREVIEW_IMAGE"
else

    SS_FILE="$SCREENSHOT_DIR/$(basename "$WALLPAPER_DIR").png"
    (linux-wallpaperengine --screenshot "$SS_FILE" --bg "$WALLPAPER_DIR" >/dev/null 2>&1 &)
    sleep 2
    WALLPAPER_IMAGE="$SS_FILE"
fi


[[ -f "$WALLPAPER_IMAGE" ]] && wal -i "$WALLPAPER_IMAGE" >/dev/null 2>&1

for i in "${!MONITORS[@]}"; do
    MON="${MONITORS[$i]}"
    CMD=("$WALLPAPER_ENGINE_BIN" --no-foreground --silent --scaling fill --"$WALLPAPER_FPS"fps --screen-root "$MON" --bg "$WALLPAPER_DIR")
    [[ $i -ne 0 ]] && CMD+=(--silent)
    nohup "${CMD[@]}" >/dev/null 2>&1 &
    disown
done