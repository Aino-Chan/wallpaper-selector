#!/bin/bash
export PATH="$HOME/.local/bin:$PATH"
export HOME="$(eval echo ~$USER)"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"


source "$HOME/.local/venvs/pywal/bin/activate"

if pgrep -f "quickshell -c wallpaper" > /dev/null; then
    quickshell -c wallpaper ipc call wallpaper close
else
    QML_XHR_ALLOW_FILE_READ=1 quickshell -c wallpaper
fi