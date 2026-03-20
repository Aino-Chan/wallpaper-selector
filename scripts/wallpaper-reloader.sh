#!/bin/bash

LIMIT=1500000
CHECK_INTERVAL=3600 

while true; do
    PID=$(pgrep -u "$USER" -f linux-wallpaperengine)

    if [ -z "$PID" ]; then
        sleep 10
        continue
    fi

    RSS=$(ps -o rss= -p "$PID")

    if [ "$RSS" -gt "$LIMIT" ]; then

        CMD=$(tr '\0' ' ' < /proc/$PID/cmdline)

        kill "$PID"
        wait "$PID" 2>/dev/null

        sleep 2

        nohup $CMD >/dev/null 2>&1 &
    fi

    sleep $CHECK_INTERVAL
done