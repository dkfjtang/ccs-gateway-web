#!/bin/bash

# CC-Switch Web 模式后台启动脚本

set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SOURCE" ]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
PROJECT_ROOT="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"

cd "$PROJECT_ROOT"

RUNTIME_DIR="${CC_SWITCH_RUNTIME_DIR:-$PROJECT_ROOT/.run/web}"
BACKEND_LOG_FILE="$RUNTIME_DIR/backend.log"
BACKEND_PID_FILE="$RUNTIME_DIR/backend.pid"

BACKEND_HOST="${CC_SWITCH_HOST:-127.0.0.1}"
BACKEND_PORT="${CC_SWITCH_PORT:-17666}"
START_TIMEOUT="${CC_SWITCH_START_TIMEOUT:-30}"
BUILD_MODE="${CC_SWITCH_BUILD_MODE:-auto}"

BACKEND_BIN="$PROJECT_ROOT/crates/server/target/release/cc-switch-web"
FRONTEND_ENTRY="$PROJECT_ROOT/dist/index.html"

mkdir -p "$RUNTIME_DIR"

resolve_app_config_dir() {
    local app_config_dir=""
    if [[ -n "${CC_SWITCH_CONFIG_DIR:-}" ]]; then
        app_config_dir="$CC_SWITCH_CONFIG_DIR"
    else
        app_config_dir="${HOME:-$PROJECT_ROOT}/.cc-switch"
    fi

    if ! mkdir -p "$app_config_dir" 2>/dev/null; then
        echo "❌ Error: unable to create app config dir: $app_config_dir" >&2
        echo "   Use CC_SWITCH_CONFIG_DIR to point to an explicit writable directory." >&2
        return 1
    fi

    if [[ ! -w "$app_config_dir" ]]; then
        echo "❌ Error: app config dir is not writable: $app_config_dir" >&2
        echo "   Refusing to switch to a fallback data directory automatically." >&2
        echo "   Use CC_SWITCH_CONFIG_DIR to point to your real writable config directory." >&2
        return 1
    fi

    printf '%s\n' "$app_config_dir"
}

is_pid_running() {
    local pid="${1:-}"
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

read_pid_file() {
    local pid_file="$1"
    [[ -f "$pid_file" ]] || return 1
    local pid
    pid="$(<"$pid_file")"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$pid"
}

cleanup_stale_pid_file() {
    local pid_file="$1"
    local pid

    pid="$(read_pid_file "$pid_file" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && ! is_pid_running "$pid"; then
        rm -f "$pid_file"
    fi
}

probe_tcp() {
    local host="$1"
    local port="$2"

    (exec 3<>"/dev/tcp/$host/$port") >/dev/null 2>&1
}

probe_host_for() {
    local host="$1"
    case "$host" in
        0.0.0.0|::|\*)
            printf '127.0.0.1\n'
            ;;
        *)
            printf '%s\n' "$host"
            ;;
    esac
}

probe_http() {
    local host="$1"
    local port="$2"
    local path="$3"
    local line=""

    if command -v curl >/dev/null 2>&1; then
        curl --silent --fail --max-time 2 "http://$host:$port$path" >/dev/null
        return
    fi

    exec 3<>"/dev/tcp/$host/$port" || return 1
    printf 'GET %s HTTP/1.0\r\nHost: %s\r\nConnection: close\r\n\r\n' "$path" "$host" >&3 || {
        exec 3>&-
        exec 3<&-
        return 1
    }

    if ! IFS= read -r -t 2 line <&3; then
        exec 3>&-
        exec 3<&-
        return 1
    fi

    exec 3>&-
    exec 3<&-
    [[ "$line" == HTTP/* ]]
}

wait_for_http() {
    local name="$1"
    local pid="$2"
    local host="$3"
    local port="$4"
    local path="$5"
    local log_file="$6"
    local elapsed=0

    while (( elapsed < START_TIMEOUT )); do
        if probe_http "$host" "$port" "$path"; then
            return 0
        fi

        if ! is_pid_running "$pid"; then
            break
        fi

        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "❌ ${name} 启动失败，日志如下："
    tail -n 40 "$log_file" 2>/dev/null || true
    return 1
}

require_command() {
    local cmd="$1"
    local message="$2"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ Error: $message"
        exit 1
    fi
}

should_build_output() {
    local output_path="$1"
    shift

    case "$BUILD_MODE" in
        always)
            return 0
            ;;
        auto)
            if [[ ! -e "$output_path" ]]; then
                return 0
            fi

            if source_is_newer_than_output "$output_path" "$@"; then
                return 0
            fi

            return 1
            ;;
        never)
            return 1
            ;;
        *)
            echo "❌ Error: invalid CC_SWITCH_BUILD_MODE: $BUILD_MODE" >&2
            echo "   Supported values: auto, always, never" >&2
            exit 1
            ;;
    esac
}

source_is_newer_than_output() {
    local output_path="$1"
    shift
    local source_path=""

    for source_path in "$@"; do
        [[ -e "$source_path" ]] || continue
        if [[ "$source_path" -nt "$output_path" ]]; then
            return 0
        fi
    done

    return 1
}

collect_files() {
    local path=""

    for path in "$@"; do
        if [[ -f "$path" ]]; then
            printf '%s\n' "$path"
            continue
        fi

        if [[ -d "$path" ]]; then
            find "$path" -type f
        fi
    done
}

ensure_required_output() {
    local output_path="$1"
    local label="$2"

    if [[ ! -e "$output_path" ]]; then
        echo "❌ Error: missing ${label}: $output_path" >&2
        echo "   Current CC_SWITCH_BUILD_MODE=$BUILD_MODE prevents building it automatically." >&2
        echo "   Run with CC_SWITCH_BUILD_MODE=always or build it manually first." >&2
        exit 1
    fi
}

start_detached() {
    local log_file="$1"
    shift

    nohup "$@" </dev/null >>"$log_file" 2>&1 &
    printf '%s\n' "$!"
}

cleanup_stale_pid_file "$BACKEND_PID_FILE"

BACKEND_PROBE_HOST="$(probe_host_for "$BACKEND_HOST")"
APP_CONFIG_DIR="$(resolve_app_config_dir)"

if pid="$(read_pid_file "$BACKEND_PID_FILE" 2>/dev/null || true)"; [[ -n "$pid" ]] && is_pid_running "$pid"; then
    echo "❌ Backend is already running (PID: $pid)"
    echo "   Stop it first: ./stop-web.sh"
    exit 1
fi

if probe_tcp "$BACKEND_PROBE_HOST" "$BACKEND_PORT"; then
    echo "❌ Backend port $BACKEND_PORT is already in use"
    echo "   Stop the existing service or set CC_SWITCH_PORT to another port."
    exit 1
fi

echo "🚀 CC-Switch Web Mode Launcher"
echo "================================"
echo ""

require_command cargo "cargo not found. Please install Rust."
require_command node "node not found. Please install Node.js."

echo "📦 Runtime directory: $RUNTIME_DIR"
echo "🗂 App config dir: $APP_CONFIG_DIR"
echo "🧱 Build mode: $BUILD_MODE"

mapfile -t FRONTEND_SOURCES < <(
    collect_files \
        "$PROJECT_ROOT/package.json" \
        "$PROJECT_ROOT/pnpm-lock.yaml" \
        "$PROJECT_ROOT/vite.config.ts" \
        "$PROJECT_ROOT/src"
)

mapfile -t BACKEND_SOURCES < <(
    collect_files \
        "$PROJECT_ROOT/Cargo.lock" \
        "$PROJECT_ROOT/crates/server/Cargo.toml" \
        "$PROJECT_ROOT/crates/server/src" \
        "$PROJECT_ROOT/crates/core/Cargo.toml" \
        "$PROJECT_ROOT/crates/core/src" \
        "$PROJECT_ROOT/src-tauri/Cargo.toml" \
        "$PROJECT_ROOT/src-tauri/build.rs" \
        "$PROJECT_ROOT/src-tauri/src"
)

if should_build_output "$FRONTEND_ENTRY" "${FRONTEND_SOURCES[@]}"; then
    echo "🎨 Building frontend assets..."
    if command -v pnpm >/dev/null 2>&1; then
        pnpm build:web
    else
        npx vite build --mode web
    fi
else
    echo "✓ Reusing frontend assets: $FRONTEND_ENTRY"
fi

if should_build_output "$BACKEND_BIN" "${BACKEND_SOURCES[@]}"; then
    echo "🔨 Building backend server..."
    cargo build --release --manifest-path crates/server/Cargo.toml
else
    echo "✓ Reusing backend binary: $BACKEND_BIN"
fi

ensure_required_output "$FRONTEND_ENTRY" "frontend asset entry"
ensure_required_output "$BACKEND_BIN" "backend binary"

if [[ ! -x "$BACKEND_BIN" ]]; then
    echo "❌ Error: backend binary not found at $BACKEND_BIN"
    exit 1
fi

: >"$BACKEND_LOG_FILE"

echo ""
echo "🎯 Starting service in background..."
echo ""

echo "▶ Starting backend on http://$BACKEND_HOST:$BACKEND_PORT"
BACKEND_PID="$(start_detached "$BACKEND_LOG_FILE" env CC_SWITCH_HOST="$BACKEND_HOST" CC_SWITCH_PORT="$BACKEND_PORT" CC_SWITCH_AUTO_PORT=false CC_SWITCH_CONFIG_DIR="$APP_CONFIG_DIR" "$BACKEND_BIN")"
printf '%s\n' "$BACKEND_PID" >"$BACKEND_PID_FILE"

if ! wait_for_http "Backend" "$BACKEND_PID" "$BACKEND_PROBE_HOST" "$BACKEND_PORT" "/health" "$BACKEND_LOG_FILE"; then
    rm -f "$BACKEND_PID_FILE"
    exit 1
fi

echo "  ✓ Backend is running (PID: $BACKEND_PID)"
echo ""
echo "================================"
echo "✨ CC-Switch Web Mode is ready!"
echo ""
echo "  Web UI:   http://$BACKEND_HOST:$BACKEND_PORT"
echo "  API:      http://$BACKEND_HOST:$BACKEND_PORT/api"
echo ""
echo "  Logs:     tail -f $BACKEND_LOG_FILE"
echo "  Stop:     ./stop-web.sh"
echo "================================"
