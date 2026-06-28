#!/usr/bin/env bash
# scripts/smoke-test-read.sh — send file contents to ds4 and verify it can
# reorder them alphanumerically.
#
# Usage:
#   scripts/smoke-test-read.sh                          # default paths
#   scripts/smoke-test-read.sh --port 8000              # against ds4-server
#   scripts/smoke-test-read.sh --gguf /path/to/file     # against local GGUF
#   scripts/smoke-test-read.sh --file other.txt          # different data file

set -euo pipefail

DS4_SRC_DIR="${DS4_SRC_DIR:-$HOME/code/ds4}"
DS4_GGUF_DIR="${DS4_GGUF_DIR:-$HOME/gguf}"
GGUF_FILE="${GGUF_FILE:-DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2.gguf}"
GGUF_PATH="${GGUF_PATH:-$DS4_GGUF_DIR/$GGUF_FILE}"
PORT=""
DATA_FILE="scripts/smoke-test-read-data.txt"
EXPECT_RE='<h1>\n.*<h2>\n.*<h3>\n.*<h4>\n.*<h5>\n.*<h6>'

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)   PORT="$2";     shift 2 ;;
        --gguf)   GGUF_PATH="$2"; shift 2 ;;
        --file)   DATA_FILE="$2"; shift 2 ;;
        --expect) EXPECT_RE="$2"; shift 2 ;;
        --help|-h)
            sed -n '2,/^$/p' "$0"; exit 0 ;;
        *) echo "Unknown flag: $1" >&2; exit 2 ;;
    esac
done

[[ -f "$DATA_FILE" ]] || { echo "Data file not found: $DATA_FILE" >&2; exit 1; }

FILE_CONTENT=$(cat "$DATA_FILE")
PROMPT=$(printf 'Reorder the lines in this file alphanumerically.\n\n%s' "$FILE_CONTENT")

if [[ -n "$PORT" ]]; then
    # HTTP path — talk to ds4-server.
    body=$(jq -n --arg p "$PROMPT" '{
        model: "deepseek-v4-flash",
        messages: [{role: "user", content: $p}],
        max_tokens: 256,
        stream: false
    }')
    out=$(curl -sS -X POST "http://127.0.0.1:$PORT/v1/chat/completions" \
        -H 'Content-Type: application/json' --data "$body")
    text=$(echo "$out" | jq -r '.choices[0].message.content // ""')
else
    # CLI path — direct ds4 binary against GGUF.
    [[ -x "$DS4_SRC_DIR/ds4" ]] || { echo "ds4 binary not at $DS4_SRC_DIR/ds4" >&2; exit 1; }
    [[ -f "$GGUF_PATH" ]] || { echo "GGUF not at $GGUF_PATH" >&2; exit 1; }
    text=$( "$DS4_SRC_DIR/ds4" --cuda -m "$GGUF_PATH" -c 4096 -p "$PROMPT" 2>&1 | tail -20 )
fi

echo "$text"
echo "---"
if printf '%s' "$text" | grep -qzE "$EXPECT_RE"; then
    echo "PASS — output matches /$EXPECT_RE/"
else
    echo "FAIL — output does not match /$EXPECT_RE/" >&2
    exit 1
fi
