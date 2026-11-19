#!/usr/bin/env bash
# deploy_agent.sh - sets up, runs and archives the Student Attendance Tracker.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/templates"
PREFIX="attendance_tracker_"

DEFAULT_WARNING=75
DEFAULT_FAILURE=50

CURRENT_DEPLOY=""

info()  { printf '[INFO]  %s\n' "$*"; }
ok()    { printf '[ OK ]  %s\n' "$*"; }
warn()  { printf '[WARN]  %s\n' "$*" >&2; }
fail()  { printf '[FAIL]  %s\n' "$*" >&2; }

# Prompts set ANSWER instead of printing, so input is never read in a $(...)
# subshell, where the deploy trap would not fire.
ANSWER=""

ask() {
    local reply
    read -r -p "$1" reply || return 1
    reply="${reply#"${reply%%[![:space:]]*}"}"
    reply="${reply%"${reply##*[![:space:]]}"}"
    ANSWER="$reply"
}

yes_no() {
    while true; do
        ask "$1 [y/n]: " || return 1
        case "${ANSWER,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     echo "Please answer y or n." ;;
        esac
    done
}

check_dependencies() {
    local missing=0 cmd
    for cmd in python3 zip; do
        if command -v "$cmd" >/dev/null 2>&1; then
            ok "$cmd found"
        else
            fail "$cmd is not installed"
            missing=1
        fi
    done
    if [[ ! -d "$TEMPLATE_DIR" ]]; then
        fail "Template directory not found: $TEMPLATE_DIR"
        missing=1
    fi
    return "$missing"
}

valid_name() {
    [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]
}

valid_percent() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 0 && 10#$1 <= 100 ))
}

read_project_name() {
    while true; do
        ask "Project name (letters, digits, _ or -): " || return 1
        valid_name "$ANSWER" && return 0
        echo "Invalid name, try again."
    done
}

read_percent() {
    local label="$1" default="$2"
    while true; do
        ask "$label threshold % [$default]: " || return 1
        [[ -z "$ANSWER" ]] && ANSWER="$default"
        if valid_percent "$ANSWER"; then
            ANSWER="$((10#$ANSWER))"
            return 0
        fi
        echo "Enter a whole number from 0 to 100."
    done
}

# Ctrl+C / Ctrl+Z during deployment: zip the partial project, then remove it.
on_deploy_interrupt() {
    trap '' INT TSTP
    echo
    warn "Deployment interrupted."

    if [[ -n "$CURRENT_DEPLOY" && -d "$CURRENT_DEPLOY" ]]; then
        local base archive
        base="$(basename "$CURRENT_DEPLOY")"
        archive="${base}_archive.zip"
        info "Saving incomplete project to $archive ..."
        if (cd "$(dirname "$CURRENT_DEPLOY")" && zip -qr "$archive" "$base"); then
            rm -rf "$CURRENT_DEPLOY"
            ok "Archived to $archive and removed the incomplete directory."
        else
            fail "Could not create $archive; leaving $base in place."
        fi
    fi
    exit 130
}

update_thresholds() {
    local config="$1" warning="$2" failure="$3"
    sed -i -E \
        -e "s/(\"warning\"[[:space:]]*:[[:space:]]*)[0-9]+/\1$warning/" \
        -e "s/(\"failure\"[[:space:]]*:[[:space:]]*)[0-9]+/\1$failure/" \
        "$config"
}

write_fresh_roster() {
    local src="$1" dest="$2"
    awk -F',' 'BEGIN { OFS = "," }
        NR == 1 { print; next }
        NF >= 4 { $(NF-1) = 0; $NF = 0; print }' "$src" > "$dest"
}

deploy() {
    check_dependencies || { fail "Fix the problems above, then try again."; return 1; }

    local name dir
    read_project_name || return 1
    name="$ANSWER"
    dir="$SCRIPT_DIR/${PREFIX}${name}"

    if [[ -e "$dir" ]]; then
        warn "$(basename "$dir") already exists."
        if yes_no "Overwrite it?"; then
            rm -rf "$dir"
        else
            info "Deployment cancelled."
            return 0
        fi
    fi

    CURRENT_DEPLOY="$dir"
    trap on_deploy_interrupt INT TSTP

    info "Creating directory structure ..."
    mkdir -p "$dir/Helpers" "$dir/reports" "$dir/archives"

    cp "$TEMPLATE_DIR/attendance_checker.py" "$dir/"
    cp "$TEMPLATE_DIR/config.json" "$dir/Helpers/config.json"

    echo "Roster options:"
    echo "  1) Use the template roster (keeps existing counts)"
    echo "  2) Start every student at zero"
    while true; do
        ask "Choose 1 or 2: " || return 1
        case "$ANSWER" in
            1) cp "$TEMPLATE_DIR/assets.csv" "$dir/Helpers/assets.csv"; break ;;
            2) write_fresh_roster "$TEMPLATE_DIR/assets.csv" "$dir/Helpers/assets.csv"; break ;;
            *) echo "Please enter 1 or 2." ;;
        esac
    done

    if yes_no "Change thresholds from the defaults (warning $DEFAULT_WARNING%, failure $DEFAULT_FAILURE%)?"; then
        local warning failure
        while true; do
            read_percent "Warning" "$DEFAULT_WARNING" || return 1
            warning="$ANSWER"
            read_percent "Failure" "$DEFAULT_FAILURE" || return 1
            failure="$ANSWER"
            if (( failure <= warning )); then
                break
            fi
            echo "Failure threshold must not be higher than the warning threshold."
        done
        update_thresholds "$dir/Helpers/config.json" "$warning" "$failure"
        ok "Thresholds set: warning=$warning, failure=$failure"
    else
        info "Keeping default thresholds."
    fi

    chmod +x "$dir/attendance_checker.py"
    chmod 600 "$dir/Helpers/config.json"

    trap - INT TSTP
    CURRENT_DEPLOY=""

    ok "Deployed $(basename "$dir")"
    run_app "$name"
}

find_project() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        read_project_name || return 1
        name="$ANSWER"
    fi
    local dir="$SCRIPT_DIR/${PREFIX}${name}"
    if [[ ! -d "$dir" ]]; then
        fail "No deployed project called '$name'."
        return 1
    fi
    ANSWER="$dir"
}

run_app() {
    local dir
    find_project "${1:-}" || return 1
    dir="$ANSWER"
    info "Starting attendance checker in $(basename "$dir") ..."
    (cd "$dir" && python3 attendance_checker.py)
    local status=$?
    if (( status == 0 )); then
        ok "Attendance session finished."
    else
        warn "Attendance checker exited with status $status."
    fi
}

archive_logs() {
    local dir
    find_project || return 1
    dir="$ANSWER"

    local stamp log kind dest
    stamp="$(date +%Y%m%d_%H%M%S)"
    for kind in attendance absent; do
        log="$dir/reports/${kind}.log"
        if [[ -f "$log" ]]; then
            dest="$dir/archives/$kind"
            mkdir -p "$dest"
            cp "$log" "$dest/${kind}_${stamp}.log"
            ok "Archived ${kind}.log -> archives/$kind/${kind}_${stamp}.log"
        else
            warn "${kind}.log not found, nothing to archive."
        fi
    done
}

main() {
    while true; do
        echo
        echo "===== Attendance Tracker Deployment Agent ====="
        echo "1) Deploy application"
        echo "2) Run application"
        echo "3) Archive logs"
        echo "4) Exit"
        ask "Select an option: " || { echo; exit 0; }
        case "$ANSWER" in
            1) deploy ;;
            2) run_app ;;
            3) archive_logs ;;
            4) info "Goodbye."; exit 0 ;;
            *) warn "Unknown option: $ANSWER" ;;
        esac
    done
}

main "$@"
