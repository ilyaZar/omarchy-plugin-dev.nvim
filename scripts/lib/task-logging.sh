# shellcheck shell=bash

TASK_LOG_RED=$'\033[0;31m'
TASK_LOG_GREEN=$'\033[0;32m'
TASK_LOG_YELLOW=$'\033[0;33m'
TASK_LOG_BLUE=$'\033[1;34m'
TASK_LOG_CYAN=$'\033[0;36m'
TASK_LOG_PURPLE=$'\033[1;35m'
TASK_LOG_NC=$'\033[0m'
TASK_LOG_SMALL_ARROW=' ->'
TASK_LOG_OP_SYMBOL='::'
TASK_LOG_WIDTH=120

task_log_ok() {
  printf '%b[OK]%b %s\n' "$TASK_LOG_GREEN" "$TASK_LOG_NC" "$*" \
    | fold -s -w "$TASK_LOG_WIDTH"
}

task_log_info() {
  printf '%b[INFO]%b %s\n' "$TASK_LOG_BLUE" "$TASK_LOG_NC" "$*" \
    | fold -s -w "$TASK_LOG_WIDTH"
}

task_log_context() {
  printf '%b%s%b %s\n' "$TASK_LOG_PURPLE" "$TASK_LOG_OP_SYMBOL" \
    "$TASK_LOG_NC" "$*" | fold -s -w "$TASK_LOG_WIDTH"
}

task_log_command() {
  printf '%b%s%b $ %s\n' "$TASK_LOG_CYAN" "$TASK_LOG_SMALL_ARROW" \
    "$TASK_LOG_NC" "$*" | fold -s -w "$TASK_LOG_WIDTH"
}

task_log_warn() {
  printf '%b[WARN]%b %s\n' "$TASK_LOG_YELLOW" "$TASK_LOG_NC" "$*" \
    | fold -s -w "$TASK_LOG_WIDTH"
}

task_log_error() {
  printf '%b[ERROR]%b %s\n' "$TASK_LOG_RED" "$TASK_LOG_NC" "$*" \
    | fold -s -w "$TASK_LOG_WIDTH" >&2
}
