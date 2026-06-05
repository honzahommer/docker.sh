#!/usr/bin/env bash

set -euo pipefail

# --- Temporary Docker config directory ---
DOCKER_CONFIG="$(mktemp -d)"
export DOCKER_CONFIG
trap 'rm -rf "$DOCKER_CONFIG"' EXIT

# --- Defaults ---
USERNAME=""
PASSWORD=""
REGISTRY=""
USE_COLOR="auto"
DRY_RUN=0
QUIET=0
INTERACTIVE=1

# --- Check non-interactive mode ---
if [[ ! -t 0 ]] && [[ $- != *i* ]]; then
  INTERACTIVE=0
fi

# --- Run helper ---
CMD_STATUS=0
CMD_OUTPUT=""

run() {
  local tmpfile
  tmpfile="$(mktemp)"
  CMD_OUTPUT=""
  CMD_STATUS=0
  "$@" >"$tmpfile" 2>&1 || CMD_STATUS=$?
  CMD_OUTPUT="$(cat "$tmpfile")"
  rm -f "$tmpfile"
  return "$CMD_STATUS"
}

# --- Logging ---
C_RESET="" C_INFO="" C_WARN="" C_ERR="" C_DBG="" C_MUT=""

setup_colors() {
  case "$USE_COLOR" in
    always) enable=1 ;;
    never)  enable=0 ;;
    auto)   [[ -t 2 && -z "${NO_COLOR:-}" ]] && enable=1 ;;
  esac

  if [[ $enable -eq 1 ]]; then
    C_RESET=$'\033[0m'
    C_INFO=$'\033[0;32m'   # green
    C_WARN=$'\033[0;33m'   # yellow
    C_ERR=$'\033[0;31m'    # red
    C_DBG=$'\033[0;36m'    # cyan
    C_MUT=$'\033[0;90m'    # gray
  fi
}

_log() {
  # _log <color> <level> <message...>
  local color="$1" level="$2" message="$3"; shift 3
    printf '%s%s [%s] %s%s\n' \
      "$color" "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$level" "$C_RESET" "$message" >&2
  if [ -n "$*" ]; then
    printf '\n%s%s%s\n' \
      "$C_MUT" "$(echo "$*" | grep -v "docker --help")" "$C_RESET" >&2
  fi
}

log_info()  { [[ $QUIET -eq 1 ]] && return 0; _log "$C_INFO" "INFO"  "$@"; }
log_warn()  { _log "$C_WARN" "WARN"  "$@"; }
log_err()   { _log "$C_ERR" "ERROR" "$@"; }
log_debug() { [[ $QUIET -eq 1 ]] && return 0; _log "$C_DBG" "DEBUG" "$@"; }

die() { log_err "$@"; exit 1; }

# --- Usage ---
usage() {
  cat <<EOF
Usage: ${0##*/} [OPTIONS] [COMMANDS...]

Docker wrapper that performs a one-shot login, runs the given Docker
command, and removes stored credentials on exit.

Defaults to Docker Hub if no registry is specified.

Precedence (highest to lowest):
  1. Command-line arguments (-u, -p, -r)
  2. Environment variables (DOCKER_USERNAME, DOCKER_PASSWORD, DOCKER_REGISTRY)
  3. Config file (docker.sh.conf in the current directory)
  4. Interactive prompt (for username, password, and command)

Options:
  -u, --username string   Username (default: \$USER)
  -p, --password string   Password
  -r, --registry string   Registry (default: Docker Hub)
  -c, --color    when     Colorize output: auto, always, never (default: auto)
  -d, --dry-run           Print commands instead of executing them
  -q, --quiet             Suppress informational output
  -h                      Show this help and exit
EOF
}

# --- Source config file (if present) ---
if [[ -f docker.sh.conf ]]; then
  # shellcheck source=/dev/null
  source docker.sh.conf
fi

# --- Environment variables override config file ---
USERNAME="${DOCKER_USERNAME:-${USERNAME:-}}"
PASSWORD="${DOCKER_PASSWORD:-${PASSWORD:-}}"
REGISTRY="${DOCKER_REGISTRY:-${REGISTRY:-}}"

# --- Save values so CLI args can override ---
CFG_USERNAME="$USERNAME"
CFG_PASSWORD="$PASSWORD"
CFG_REGISTRY="$REGISTRY"

# --- Arguments helper ---
need_value() {
    # need_value <flag> <value>
    [[ -n "${2:-}" && "${2:-}" != --* ]] || die "Argument '$1' requires a non-empty value."
}

# --- Parse options (override config) ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--username) need_value "$1" "${2:-}"; CFG_USERNAME="$2"; shift 2 ;;
    -p|--password) need_value "$1" "${2:-}"; CFG_PASSWORD="$2"; shift 2 ;;
    -r|--registry) need_value "$1" "${2:-}"; CFG_REGISTRY="$2"; shift 2 ;;
    -c|--color)
      need_value "$1" "${2:-}"
      [[ "$2" =~ ^(auto|always|never)$ ]] || die "Invalid --color '$2'. Allowed: auto, always, never."
      USE_COLOR="$2"; shift 2 ;;
    -d|--dry-run)  DRY_RUN=1; shift ;;
    -q|--quiet)    QUIET=1; shift ;;
    -h)            usage; exit 0 ;;
    --)            shift; break ;;
    *)             break ;;
  esac
done

setup_colors

USERNAME="$CFG_USERNAME"
PASSWORD="$CFG_PASSWORD"
REGISTRY="$CFG_REGISTRY"

# --- Interactive prompts for missing values ---
if [[ $INTERACTIVE -eq 1 ]]; then
  if [[ -z "$USERNAME" ]]; then
    read -rp "Username [${USER:-}]: " USERNAME
  fi

  if [[ -z "$PASSWORD" ]]; then
    read -rsp "Password: " PASSWORD
    echo
  fi
fi

USERNAME="${USERNAME:-${USER:-}}"

if [[ -z "$PASSWORD" ]]; then
  log_err "Password is required"
  exit 1
fi

# --- Login ---
login_args=( --username "$USERNAME" --password-stdin )
[[ $QUIET -eq 1 ]] && login_args+=( --quiet )
[[ -n "$REGISTRY" ]] && login_args+=( "$REGISTRY" )

if [[ $DRY_RUN -eq 1 ]]; then
  log_debug "[dry-run] docker login ${login_args[*]}"
else
  CMD_OUTPUT=""
  CMD_STATUS=0
  CMD_OUTPUT="$(printf '%s' "$PASSWORD" | docker login "${login_args[@]}" 2>&1)" || CMD_STATUS=$?
  if [[ $CMD_STATUS -ne 0 ]]; then
    die "docker login failed (exit $CMD_STATUS)" "$CMD_OUTPUT"
  fi
  log_info "$CMD_OUTPUT"
fi

# --- Resolve Docker command ---
if [[ $# -eq 0 && -n "${DOCKER_COMMAND:-}" ]]; then
  # shellcheck disable=SC2086
  set -- $DOCKER_COMMAND
fi

if [[ $# -eq 0 && $INTERACTIVE -eq 1 ]]; then
  read -rp "Docker command: docker " DOCKER_COMMAND_INPUT
  if [[ -n "$DOCKER_COMMAND_INPUT" ]]; then
    # shellcheck disable=SC2086
    set -- $DOCKER_COMMAND_INPUT
  fi
fi

# --- Execute remaining Docker command ---
if [[ $# -gt 0 ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    log_debug "[dry-run] docker $*"
  else
    if ! run docker "$@"; then
      log_err "docker $* failed (exit $CMD_STATUS)" "$CMD_OUTPUT"
    else
      log_debug "docker $*" "$CMD_OUTPUT"
    fi
    exit "$CMD_STATUS"
  fi
else
  die "No Docker command to execute"
fi
