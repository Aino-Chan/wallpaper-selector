#!/bin/bash
export PATH="$HOME/.local/bin:$PATH"
export HOME="$(eval echo ~$USER)"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

QML_XHR_ALLOW_FILE_READ=1 quickshell -c wallpaper