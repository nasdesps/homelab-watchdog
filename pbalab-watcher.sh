#!/bin/bash
# pbalab-watcher.sh — external watchdog running on Oracle (Phoenix)
# Checks pbalab's status page over Tailscale. Requires 2 consecutive
# failures before alerting, to filter out transient network blips.

# --- Configuration ---
PBALAB_URL="http://100.123.21.56:30080"
STATE_FILE="/home/ubuntu/.pbalab_watcher_state"
FAIL_FILE="/home/ubuntu/.pbalab_watcher_fails"
TIMEOUT=5
FAIL_THRESHOLD=2

# --- Load secret ---
source /home/ubuntu/.watcher_env

# --- Notification function ---
send_notification() {
    MESSAGE=$1
    curl -s -H "Content-Type: application/json" -X POST \
        -d "{\"content\": \"$MESSAGE\"}" "$DISCORD_WEBHOOK_URL" > /dev/null
}

# --- Read previous alert state (UP or DOWN); default UP ---
if [ -f "$STATE_FILE" ]; then
    PREV_STATE=$(cat "$STATE_FILE")
else
    PREV_STATE="UP"
fi

# --- Read consecutive failure count; default 0 ---
if [ -f "$FAIL_FILE" ]; then
    FAIL_COUNT=$(cat "$FAIL_FILE")
else
    FAIL_COUNT=0
fi

# --- Check pbalab ---
HTTP_CODE=$(curl -s --connect-timeout $TIMEOUT -o /dev/null -w "%{http_code}" "$PBALAB_URL")

if [ "$HTTP_CODE" = "200" ]; then
    # Success — reset failure counter
    FAIL_COUNT=0
    echo "$FAIL_COUNT" > "$FAIL_FILE"

    # If we were previously alerting DOWN, send recovery
    if [ "$PREV_STATE" = "DOWN" ]; then
        send_notification "✅ **pbalab is BACK ONLINE** — reachable again from Oracle. $(date)"
        echo "UP" > "$STATE_FILE"
    fi
else
    # Failure — increment counter
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "$FAIL_COUNT" > "$FAIL_FILE"

    # Alert only when we cross the threshold AND we weren't already alerting
    if [ "$FAIL_COUNT" -ge "$FAIL_THRESHOLD" ] && [ "$PREV_STATE" = "UP" ]; then
        send_notification "🚨 **pbalab is UNREACHABLE** from Oracle (Phoenix) — $FAIL_COUNT consecutive failures. Home server may be down or offline. HTTP code: $HTTP_CODE — $(date)"
        echo "DOWN" > "$STATE_FILE"
    fi
fi
