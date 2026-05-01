#!/bin/bash
# ============================================================================
# JL Keychain Tools - PopClip extension
#
# Manage macOS Keychain entries (API keys, passwords) namespaced with 'jl-'.
# Usage: jl_keychain.sh <save|get|list|delete>
# Reads $POPCLIP_TEXT for save/get/delete (the selection from PopClip).
# ============================================================================

# Debug log: capture every invocation so we can diagnose silent failures from
# inside PopClip's restricted environment. Safe to keep enabled.
JL_LOG_FILE="/tmp/jl_keychain_debug.log"
{
    /usr/bin/printf '\n========== %s ==========\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')"
    /usr/bin/printf 'argv[1]      : %s\n' "${1:-<empty>}"
    /usr/bin/printf 'PWD          : %s\n' "$PWD"
    /usr/bin/printf 'USER         : %s\n' "${USER:-<unset>}"
    /usr/bin/printf 'HOME         : %s\n' "${HOME:-<unset>}"
    /usr/bin/printf 'PATH         : %s\n' "${PATH:-<unset>}"
    /usr/bin/printf 'BASH_VERSION : %s\n' "${BASH_VERSION:-<unset>}"
    /usr/bin/printf 'POPCLIP_TEXT : %s\n' "${POPCLIP_TEXT:-<unset>}"
    /usr/bin/printf 'POPCLIP_BUNDLE_PATH : %s\n' "${POPCLIP_BUNDLE_PATH:-<unset>}"
} >> "$JL_LOG_FILE" 2>&1

set -u

JL_PREFIX="jl-"
# PopClip strips $USER from the env, so always derive it from `id -un`.
JL_ACCOUNT="$(/usr/bin/id -un 2>/dev/null)"
if [ -z "$JL_ACCOUNT" ]; then
    JL_ACCOUNT="${USER:-}"
fi
jl_log() { /usr/bin/printf '%s\n' "$*" >> "$JL_LOG_FILE" 2>&1; }
jl_log "JL_ACCOUNT resolved to: ${JL_ACCOUNT}"

# Trap to log any error before exit
trap 'jl_log "EXIT code=$? line=$LINENO command=[$BASH_COMMAND]"' EXIT

# ----------------------------------------------------------------------------
# AppleScript helpers
# ----------------------------------------------------------------------------

# Escape a string so it can be embedded inside an AppleScript double-quoted literal.
ascript_escape() {
    /usr/bin/printf '%s' "$1" | /usr/bin/sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Show input dialog. Args: $1=prompt, $2=default. Echoes typed text or empty if cancelled.
show_input() {
    local prompt
    local default
    prompt="$(ascript_escape "$1")"
    default="$(ascript_escape "$2")"
    /usr/bin/osascript \
        -e "tell application \"System Events\" to activate" \
        -e "try" \
        -e "    set theResult to display dialog \"${prompt}\" default answer \"${default}\" with title \"JL Keychain Tools\"" \
        -e "    return text returned of theResult" \
        -e "on error" \
        -e "    return \"\"" \
        -e "end try" 2>/dev/null
}

# Show OK/Cancel confirmation. Args: $1=prompt. Echoes "OK" or empty.
show_confirm() {
    local prompt
    prompt="$(ascript_escape "$1")"
    /usr/bin/osascript \
        -e "tell application \"System Events\" to activate" \
        -e "try" \
        -e "    set theResult to display dialog \"${prompt}\" with title \"JL Keychain Tools\" buttons {\"Cancel\", \"OK\"} default button \"OK\" cancel button \"Cancel\"" \
        -e "    return button returned of theResult" \
        -e "on error" \
        -e "    return \"\"" \
        -e "end try" 2>/dev/null
}

# Show macOS notification. Args: $1=message
show_notify() {
    local msg
    msg="$(ascript_escape "$1")"
    /usr/bin/osascript -e "display notification \"${msg}\" with title \"JL Keychain Tools\"" 2>/dev/null
}

# Show choose-from-list. Args: $1=prompt, then list items.
# Echoes selected item or empty if cancelled.
show_choose() {
    local prompt="$1"; shift
    local items_as=""
    local item
    for item in "$@"; do
        local esc
        esc="$(ascript_escape "$item")"
        items_as="${items_as}\"${esc}\", "
    done
    items_as="${items_as%, }"
    local prompt_esc
    prompt_esc="$(ascript_escape "$prompt")"
    /usr/bin/osascript \
        -e "tell application \"System Events\" to activate" \
        -e "set theChoice to choose from list {${items_as}} with title \"JL Keychain Tools\" with prompt \"${prompt_esc}\"" \
        -e "if theChoice is false then return \"\"" \
        -e "return item 1 of theChoice" 2>/dev/null
}

# ----------------------------------------------------------------------------
# Parsing helpers
# ----------------------------------------------------------------------------

# Trim leading/trailing whitespace.
trim() {
    /usr/bin/printf '%s' "$1" | /usr/bin/sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Strip surrounding matching quotes ("..." or '...'). Echoes the inner string.
strip_quotes() {
    local s="$1"
    local len=${#s}
    if [ "$len" -lt 2 ]; then
        /usr/bin/printf '%s' "$s"
        return
    fi
    local first="${s:0:1}"
    local last="${s:$((len-1)):1}"
    if [ "$first" = "$last" ] && { [ "$first" = '"' ] || [ "$first" = "'" ]; }; then
        /usr/bin/printf '%s' "${s:1:$((len-2))}"
    else
        /usr/bin/printf '%s' "$s"
    fi
}

# Parse env-style line "NAME=VALUE". Echoes "name|value" or empty if no '='.
# Tolerates: leading 'export ', spaces around '=', single/double quotes,
# trailing comments " #..." (only when value is unquoted), trailing newlines.
parse_env_line() {
    local input
    input="$(trim "$1")"

    # Strip leading "export "
    case "$input" in
        export\ *) input="${input#export }"; input="$(trim "$input")" ;;
    esac

    # Must contain '='
    case "$input" in
        *=*) ;;
        *) return ;;
    esac

    local name="${input%%=*}"
    local value="${input#*=}"
    name="$(trim "$name")"
    value="$(trim "$value")"

    if [ -z "$name" ]; then
        return
    fi

    # Detect surrounding quotes
    local first_char="${value:0:1}"
    local was_quoted="no"
    if [ "$first_char" = '"' ] || [ "$first_char" = "'" ]; then
        local stripped
        stripped="$(strip_quotes "$value")"
        if [ "$stripped" != "$value" ]; then
            value="$stripped"
            was_quoted="yes"
        fi
    fi

    # If unquoted, strip trailing inline comment " #..."
    if [ "$was_quoted" = "no" ]; then
        value="$(/usr/bin/printf '%s' "$value" | /usr/bin/sed 's/[[:space:]]\{1,\}#.*$//')"
    fi

    /usr/bin/printf '%s|%s' "$name" "$value"
}

# Normalize service name: lowercase, [^a-z0-9-] -> '-', collapse '-', ensure jl- prefix.
normalize_name() {
    local raw
    raw="$(trim "$1")"
    local norm
    norm="$(/usr/bin/printf '%s' "$raw" \
        | /usr/bin/tr '[:upper:]' '[:lower:]' \
        | /usr/bin/sed -e 's/[^a-z0-9-]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')"
    case "$norm" in
        "${JL_PREFIX}"*) ;;
        *) norm="${JL_PREFIX}${norm}" ;;
    esac
    /usr/bin/printf '%s' "$norm"
}

# ----------------------------------------------------------------------------
# Commands
# ----------------------------------------------------------------------------

cmd_save() {
    local text="${POPCLIP_TEXT:-}"
    if [ -z "$text" ]; then
        show_notify "Nothing selected"
        exit 1
    fi

    local parsed
    parsed="$(parse_env_line "$text")"

    local name=""
    local value=""

    if [ -n "$parsed" ]; then
        name="${parsed%%|*}"
        value="${parsed#*|}"
    else
        name="$(show_input "Name for this key (e.g. openrouter-api-key):" "")"
        if [ -z "$name" ]; then
            exit 0
        fi
        value="$(trim "$text")"
    fi

    if [ -z "$value" ]; then
        show_notify "Empty value, nothing to save"
        exit 1
    fi

    local norm_name
    norm_name="$(normalize_name "$name")"

    # If already exists, ask before overwrite
    if /usr/bin/security find-generic-password -s "$norm_name" -a "$JL_ACCOUNT" >/dev/null 2>&1; then
        local result
        result="$(show_confirm "Key \"${norm_name}\" already exists. Overwrite?")"
        if [ "$result" != "OK" ]; then
            exit 0
        fi
    fi

    if /usr/bin/security add-generic-password -s "$norm_name" -a "$JL_ACCOUNT" -w "$value" -U >/dev/null 2>&1; then
        show_notify "Saved as ${norm_name}"
    else
        show_notify "Failed to save ${norm_name}"
        exit 1
    fi
}

cmd_get() {
    local text="${POPCLIP_TEXT:-}"
    if [ -z "$text" ]; then
        show_notify "Nothing selected"
        exit 1
    fi

    local norm_name
    norm_name="$(normalize_name "$text")"

    local value
    value="$(/usr/bin/security find-generic-password -s "$norm_name" -a "$JL_ACCOUNT" -w 2>/dev/null)"

    if [ -z "$value" ]; then
        show_notify "Key \"${norm_name}\" not found"
        exit 1
    fi

    # PopClip pastes whatever we send to stdout (after: paste-result).
    /usr/bin/printf '%s' "$value"
}

cmd_list() {
    # Extract all service names matching jl- prefix from the default keychain.
    local items
    items="$(/usr/bin/security dump-keychain 2>/dev/null \
        | /usr/bin/awk -F'"' '/"svce"<blob>=/{print $4}' \
        | /usr/bin/grep "^${JL_PREFIX}" \
        | /usr/bin/sort -u)"

    if [ -z "$items" ]; then
        show_notify "No keys found with prefix '${JL_PREFIX}'"
        exit 0
    fi

    # Convert newline-separated to argument list
    local -a items_array=()
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            items_array+=("$line")
        fi
    done <<< "$items"

    local choice
    choice="$(show_choose "Select a key to copy its value:" "${items_array[@]}")"

    if [ -z "$choice" ]; then
        exit 0
    fi

    local value
    value="$(/usr/bin/security find-generic-password -s "$choice" -a "$JL_ACCOUNT" -w 2>/dev/null)"

    if [ -z "$value" ]; then
        show_notify "Key \"${choice}\" not found"
        exit 1
    fi

    # PopClip pastes whatever we send to stdout (after: paste-result).
    /usr/bin/printf '%s' "$value"
}

cmd_delete() {
    local text="${POPCLIP_TEXT:-}"
    if [ -z "$text" ]; then
        show_notify "Nothing selected"
        exit 1
    fi

    local norm_name
    norm_name="$(normalize_name "$text")"

    if ! /usr/bin/security find-generic-password -s "$norm_name" -a "$JL_ACCOUNT" >/dev/null 2>&1; then
        show_notify "Key \"${norm_name}\" not found"
        exit 1
    fi

    local result
    result="$(show_confirm "Delete key \"${norm_name}\"? This cannot be undone.")"
    if [ "$result" != "OK" ]; then
        exit 0
    fi

    if /usr/bin/security delete-generic-password -s "$norm_name" -a "$JL_ACCOUNT" >/dev/null 2>&1; then
        show_notify "Deleted ${norm_name}"
    else
        show_notify "Failed to delete ${norm_name}"
        exit 1
    fi
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
case "${1:-}" in
    save)   cmd_save ;;
    get)    cmd_get ;;
    list)   cmd_list ;;
    delete) cmd_delete ;;
    *)
        /usr/bin/printf 'Usage: %s <save|get|list|delete>\n' "$0" >&2
        exit 1
        ;;
esac
