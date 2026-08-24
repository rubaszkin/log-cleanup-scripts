#!/bin/bash
#
# clean_logs_debian.sh - Comprehensive log cleanup for Debian / Ubuntu
# Version: 2.0 (bugfix release)
#
# v2.0 fixes 14 defects found in v1.x, including three that made every
# run abort partway through. See BUGFIX_REPORT.md for details.
#
# NOTE: deliberately does NOT use "set -e". The script is full of
# best-effort operations that are allowed to fail (gzip on a busy file,
# journalctl on a system without systemd, apt-get on a locked dpkg).
# Under "set -e" any of those aborts the whole cleanup, which is the
# opposite of what you want at 98% disk usage. Errors are checked
# explicitly instead.

set -o pipefail

#############################################
# Configuration
#############################################

# Log roots. "find" recurses, so listing /var/log covers every
# subdirectory under it - do NOT list /var/log/nginx etc. separately.
declare -a LOG_ROOTS=(
    "/var/log"
    "/opt/lampp/logs"
    "/usr/local/apache2/logs"
    "/root/logs"
)

# Globs expanded at runtime (see expand_glob_roots).
declare -a LOG_ROOT_GLOBS=(
    "/home/*/logs"
    "/srv/*/logs"
)

THRESHOLD=90
CRITICAL_THRESHOLD=95
DAYS_TO_KEEP=7
CRITICAL_DAYS_TO_KEEP=3
TMP_ATIME_DAYS=7               # /tmp files untouched for this long
TRUNCATE_ABOVE_KB=102400       # truncate active logs bigger than 100 MB
TRUNCATE_KEEP_LINES=1000

DRY_RUN=false
ENABLE_COMPRESSION=true
FORCE_MODE=false
FORCE_FLAG_USED=false

SCRIPT_LOG="/var/log/log_cleanup.log"
SUMMARY_REPORT="/var/log/log_cleanup_summary.txt"
LOCK_FILE="/var/lock/log_cleanup.lock"

EMAIL_NOTIFY=false
EMAIL_ADDRESS="admin@example.com"

# Global counters. Functions update these directly. They are NOT
# returned via stdout - that was the v1 bug that ate all log output.
TOTAL_FILES_DELETED=0
TOTAL_KB_FREED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
[ -t 1 ] || { RED=''; GREEN=''; YELLOW=''; NC=''; }

#############################################
# Logging
#############################################

log_message() {
    local ts msg
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    msg="[$ts] $1"
    printf '%s\n' "$msg"
    printf '%s\n' "$msg" >> "$SCRIPT_LOG" 2>/dev/null
}

log_color() {
    local color=$1 message=$2 ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    printf '%b%s%b\n' "$color" "$message" "$NC"
    printf '%s\n' "[$ts] $message" >> "$SCRIPT_LOG" 2>/dev/null
}

die() {
    log_color "$RED" "FATAL: $1"
    exit 1
}

#############################################
# Helpers
#############################################

# -P forces POSIX single-line output. Without it, long device names
# wrap onto a second line and "NR==2 {print $5}" returns garbage.
get_disk_usage() {
    local path=${1:-/}
    df -P "$path" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}'
}

get_disk_field() {
    local field=$1 path=${2:-/}
    df -Ph "$path" 2>/dev/null | awk -v f="$field" 'NR==2 {print $f}'
}

is_number() {
    [[ $1 =~ ^[0-9]+$ ]]
}

human_readable_size() {
    local kb=${1:-0}
    is_number "$kb" || kb=0
    if   [ "$kb" -lt 1024 ];    then echo "${kb}KB"
    elif [ "$kb" -lt 1048576 ]; then echo "$((kb/1024))MB"
    else                             echo "$((kb/1048576))GB"
    fi
}

file_size_kb() {
    local size
    size=$(du -k "$1" 2>/dev/null | cut -f1)
    is_number "$size" || size=0
    echo "$size"
}

send_notification() {
    if [ "$EMAIL_NOTIFY" = true ] && command -v mail >/dev/null 2>&1; then
        printf '%s\n' "$1" | mail -s "Log Cleanup Alert - $(hostname)" "$EMAIL_ADDRESS"
    fi
}

# Turn "/home/*/logs" into real directories. In v1 these stayed as
# literal strings, so [ -d ] was always false and they were skipped
# while still being counted as "processed".
expand_glob_roots() {
    local pattern d
    for pattern in "${LOG_ROOT_GLOBS[@]}"; do
        for d in $pattern; do
            [ -d "$d" ] && LOG_ROOTS+=("$d")
        done
    done
}

#############################################
# Cleanup primitives
#############################################

# Rotated-log matcher. v1 used a blanket "*.1 *.2 ... *.9 *.gz" which
# matched things like libfoo.so.1 and any user tarball. This matches
# only real rotation artefacts and refuses to touch the script's own
# log or summary file.
find_rotated_logs() {
    local dir=$1
    shift
    find "$dir" -type f \
        ! -path "$SCRIPT_LOG" \
        ! -path "$SUMMARY_REPORT" \
        ! -name "*.so.*" \
        ! -name "*.tar.gz" \
        ! -name "*.tgz" \
        ! -name "*.tar.*" \
        \( -name "*.log.[0-9]*" \
           -o -name "*.log-[0-9]*" \
           -o -name "*[0-9].gz" \
           -o -name "*.old" \
           -o -name "*.[0-9]" \
        \) "$@" -print0 2>/dev/null
}

find_active_logs() {
    local dir=$1
    shift
    find "$dir" -type f \
        ! -path "$SCRIPT_LOG" \
        ! -path "$SUMMARY_REPORT" \
        -name "*.log" "$@" -print0 2>/dev/null
}

delete_file() {
    local file=$1 size
    [ -f "$file" ] || return 1
    [ -w "$file" ] || return 1
    size=$(file_size_kb "$file")

    if [ "$DRY_RUN" = true ]; then
        log_color "$YELLOW" "[DRY RUN] Would delete: $file ($(human_readable_size "$size"))"
        TOTAL_FILES_DELETED=$((TOTAL_FILES_DELETED + 1))
        TOTAL_KB_FREED=$((TOTAL_KB_FREED + size))
        return 0
    fi

    if rm -f "$file" 2>/dev/null; then
        log_message "Deleted: $file ($(human_readable_size "$size"))"
        TOTAL_FILES_DELETED=$((TOTAL_FILES_DELETED + 1))
        TOTAL_KB_FREED=$((TOTAL_KB_FREED + size))
        return 0
    fi
    return 1
}

# Truncate in place. v1 did "tail > tmp && mv tmp file", which replaces
# the inode: every daemon holding the file open (rsyslog, nginx, mysql)
# keeps writing to the now-unlinked old inode, so the space is never
# actually released and the visible log stops growing until restart.
# It also dropped ownership, mode and any ACL/SELinux label.
truncate_file_in_place() {
    local file=$1 before after saved tmp
    before=$(file_size_kb "$file")
    [ "$before" -gt "$TRUNCATE_ABOVE_KB" ] || return 1

    if [ "$DRY_RUN" = true ]; then
        log_color "$YELLOW" "[DRY RUN] Would truncate: $file ($(human_readable_size "$before"))"
        return 0
    fi

    tmp=$(mktemp "${TMPDIR:-/tmp}/logclean.XXXXXX") || return 1
    if ! tail -n "$TRUNCATE_KEEP_LINES" "$file" > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        return 1
    fi
    # ">" keeps the inode, so open file descriptors stay valid.
    if ! cat "$tmp" > "$file" 2>/dev/null; then
        rm -f "$tmp"
        return 1
    fi
    rm -f "$tmp"

    after=$(file_size_kb "$file")
    saved=$((before - after))
    [ "$saved" -gt 0 ] || saved=0
    TOTAL_KB_FREED=$((TOTAL_KB_FREED + saved))
    log_color "$GREEN" "Truncated: $file (freed $(human_readable_size "$saved"))"
    return 0
}

clean_old_logs() {
    local dir=$1
    local days=${2:-$DAYS_TO_KEEP}
    local file

    [ -d "$dir" ] || return 0
    log_message "Cleaning logs in: $dir (older than $days days)"

    while IFS= read -r -d '' file; do
        delete_file "$file"
    done < <(find_rotated_logs "$dir" -mtime "+$days")
}

force_cleanup() {
    local dir=$1 file

    [ -d "$dir" ] || return 0
    log_color "$RED" "FORCE CLEANUP in: $dir"

    # 1. every rotated artefact, regardless of age
    while IFS= read -r -d '' file; do
        delete_file "$file"
    done < <(find_rotated_logs "$dir")

    # 2. active logs older than the critical retention
    while IFS= read -r -d '' file; do
        delete_file "$file"
    done < <(find_active_logs "$dir" -mtime "+$CRITICAL_DAYS_TO_KEEP")

    # 3. truncate whatever is still huge and still in use
    while IFS= read -r -d '' file; do
        truncate_file_in_place "$file"
    done < <(find_active_logs "$dir")
}

compress_logs() {
    local dir=$1 file
    [ -d "$dir" ] || return 0
    log_message "Compressing logs in: $dir"

    while IFS= read -r -d '' file; do
        [ -w "$file" ] || continue
        if [ "$DRY_RUN" = true ]; then
            log_color "$YELLOW" "[DRY RUN] Would compress: $file"
        elif gzip -f "$file" 2>/dev/null; then
            log_color "$GREEN" "Compressed: $file"
        fi
    done < <(find_active_logs "$dir" -mtime +1)
}

clean_journal_logs() {
    local days=${1:-$DAYS_TO_KEEP}
    command -v journalctl >/dev/null 2>&1 || return 0

    log_message "Cleaning systemd journal (keeping $days days)..."
    if [ "$DRY_RUN" = true ]; then
        log_color "$YELLOW" "[DRY RUN] Would vacuum journal older than ${days}d"
        return 0
    fi
    if journalctl --vacuum-time="${days}d" >/dev/null 2>&1; then
        log_color "$GREEN" "Journal vacuumed"
    else
        log_color "$YELLOW" "Journal vacuum failed (skipped)"
    fi
}

# /tmp is deliberately NOT part of LOG_ROOTS. v1 listed it there, so the
# rotated-log matcher deleted every *.gz in /tmp - user tarballs
# included. Here it is handled separately, by access time, with the
# runtime directories excluded.
clean_temp_dirs() {
    local dir
    for dir in /tmp /var/tmp; do
        [ -d "$dir" ] || continue
        if [ "$DRY_RUN" = true ]; then
            log_color "$YELLOW" "[DRY RUN] Would clean $dir (atime +$TMP_ATIME_DAYS days)"
            continue
        fi
        log_message "Cleaning $dir (untouched for $TMP_ATIME_DAYS+ days)..."
        find "$dir" -mindepth 1 -maxdepth 3 -type f \
            ! -path "*/systemd-*" \
            ! -path "*/.X11-unix/*" \
            ! -path "*/snap*" \
            ! -path "*/.font-unix/*" \
            ! -path "*/logclean.*" \
            -atime "+$TMP_ATIME_DAYS" -delete 2>/dev/null
    done
    log_color "$GREEN" "Temporary files cleaned"
}

debian_specific_cleanup() {
    log_message "--- Debian/Ubuntu-specific cleanup ---"

    if [ "$DRY_RUN" = true ]; then
        log_color "$YELLOW" "[DRY RUN] Would clean APT cache and autoremove packages"
    else
        if command -v apt-get >/dev/null 2>&1; then
            log_message "Cleaning APT cache..."
            apt-get clean >/dev/null 2>&1     && log_color "$GREEN" "APT cache cleaned"
            apt-get autoclean >/dev/null 2>&1 && log_color "$GREEN" "APT autoclean done"

            # v1 built a dpkg|sed|xargs pipeline that could purge the
            # RUNNING kernel if "uname -r" parsing missed, called sudo
            # from an already-root script, and ran apt-get with no
            # arguments when the list came back empty. autoremove
            # --purge is the supported way and never touches the
            # booted kernel.
            if [ "$FORCE_MODE" = true ]; then
                log_message "Removing orphaned packages and old kernels..."
                if DEBIAN_FRONTEND=noninteractive \
                   apt-get -y autoremove --purge >/dev/null 2>&1; then
                    log_color "$GREEN" "Old kernels and orphans removed"
                else
                    log_color "$YELLOW" "autoremove failed (dpkg lock?) - skipped"
                fi
            fi
        fi
    fi

    if [ "$FORCE_MODE" = true ] && [ "$DRY_RUN" = false ]; then
        log_message "Cleaning thumbnail caches..."
        find /home /root -maxdepth 4 -type d -path "*/.cache/thumbnails" \
            -exec rm -rf {} + 2>/dev/null
        log_color "$GREEN" "Thumbnail caches cleaned"

        log_message "Cleaning core dumps..."
        find /var/lib/systemd/coredump /var/crash -type f -delete 2>/dev/null
        log_color "$GREEN" "Core dumps cleaned"
    fi

    if command -v docker >/dev/null 2>&1 && [ -d /var/lib/docker/containers ]; then
        if [ "$DRY_RUN" = true ]; then
            log_color "$YELLOW" "[DRY RUN] Would truncate Docker container logs"
        else
            log_message "Truncating Docker container logs..."
            find /var/lib/docker/containers -name "*-json.log" -type f \
                -exec truncate -s 0 {} + 2>/dev/null
            log_color "$GREEN" "Docker logs truncated"
        fi
    fi
}

emergency_cleanup() {
    log_color "$RED" "=========================================="
    log_color "$RED" "EMERGENCY CLEANUP MODE"
    log_color "$RED" "=========================================="
    debian_specific_cleanup
    clean_temp_dirs
    clean_journal_logs 1
}

#############################################
# Summary report
#############################################
# Defined BEFORE main is invoked. In v1 this lived after the final
# "exit 0", so it was never defined and the call site failed with
# "command not found" - the summary file was never written at all.

create_summary_report() {
    local initial_usage=$1 final_usage=$2
    local files_deleted=$3 kb_freed=$4
    local used_before=$5 used_after=$6

    local mb=$((kb_freed / 1024))
    local gb=$((kb_freed / 1048576))
    local reduction=$((initial_usage - final_usage))
    local total_size avail_after mode dirs=0 d

    total_size=$(get_disk_field 2 /)
    avail_after=$(get_disk_field 4 /)

    mode="Standard cleanup"
    if [ "$FORCE_MODE" = true ]; then
        if [ "$FORCE_FLAG_USED" = true ]; then
            mode="FORCE cleanup (manual override)"
        else
            mode="FORCE cleanup (auto-activated)"
        fi
    fi

    for d in "${LOG_ROOTS[@]}"; do
        [ -d "$d" ] && dirs=$((dirs + 1))
    done

    {
        echo "======================================================================"
        echo "        DEBIAN / UBUNTU LOG CLEANUP - SUMMARY REPORT"
        echo "======================================================================"
        echo
        echo "EXECUTION"
        echo "----------------------------------------------------------------------"
        printf "%-22s %s\n" "Timestamp:"     "$(date '+%Y-%m-%d %H:%M:%S')"
        printf "%-22s %s\n" "Hostname:"      "$(hostname)"
        printf "%-22s %s\n" "Script:"        "$(basename "$0") v2.0"
        printf "%-22s %s\n" "Mode:"          "$mode"
        printf "%-22s %s\n" "Dry run:"       "$DRY_RUN"
        echo
        echo "DISK USAGE"
        echo "----------------------------------------------------------------------"
        printf "%-22s %s\n" "Filesystem size:" "$total_size"
        printf "%-22s %s\n" "Used before:"     "$used_before (${initial_usage}%)"
        printf "%-22s %s\n" "Used after:"      "$used_after (${final_usage}%)"
        printf "%-22s %s\n" "Available now:"   "$avail_after"
        printf "%-22s %s\n" "Usage reduction:" "${reduction} percentage points"
        echo
        echo "SPACE RECLAIMED"
        echo "----------------------------------------------------------------------"
        printf "%-22s %s\n" "Files deleted:"   "$files_deleted"
        printf "%-22s %s\n" "Freed (KB):"      "$kb_freed"
        printf "%-22s %s\n" "Freed (MB):"      "$mb"
        printf "%-22s %s\n" "Freed (GB):"      "$gb"
        printf "%-22s %s\n" "Human readable:"  "$(human_readable_size "$kb_freed")"
        echo
        echo "SETTINGS"
        echo "----------------------------------------------------------------------"
        printf "%-22s %s\n" "Warn threshold:"     "${THRESHOLD}%"
        printf "%-22s %s\n" "Critical threshold:" "${CRITICAL_THRESHOLD}%"
        printf "%-22s %s\n" "Days retained:" \
            "$([ "$FORCE_MODE" = true ] && echo "$CRITICAL_DAYS_TO_KEEP" || echo "$DAYS_TO_KEEP")"
        echo
        echo "LOG ROOTS PROCESSED ($dirs found)"
        echo "----------------------------------------------------------------------"
        for d in "${LOG_ROOTS[@]}"; do
            [ -d "$d" ] && echo "  [x] $d"
        done
        echo
        echo "STATUS"
        echo "----------------------------------------------------------------------"
        if [ "$final_usage" -ge "$CRITICAL_THRESHOLD" ]; then
            printf "%-22s %s\n" "Result:" "CRITICAL - manual intervention required"
        elif [ "$final_usage" -ge "$THRESHOLD" ]; then
            printf "%-22s %s\n" "Result:" "WARNING - still above threshold"
        else
            printf "%-22s %s\n" "Result:" "OK"
        fi
        printf "%-22s %s\n" "Final usage:" "${final_usage}%"
        echo
        echo "======================================================================"
    } > "$SUMMARY_REPORT" 2>/dev/null

    if [ -f "$SUMMARY_REPORT" ]; then
        log_color "$GREEN" "Summary report written: $SUMMARY_REPORT"
    else
        log_color "$YELLOW" "Could not write summary report to $SUMMARY_REPORT"
    fi
}

#############################################
# Main
#############################################

main() {
    local initial_usage final_usage current_usage
    local used_before used_after dir

    log_message "=========================================="
    log_message "Debian/Ubuntu Log Cleanup v2.0 started"
    log_message "=========================================="

    if [ "$(id -u)" -ne 0 ]; then
        log_color "$YELLOW" "WARNING: not running as root - most locations will be skipped"
    fi

    expand_glob_roots

    initial_usage=$(get_disk_usage /)
    is_number "$initial_usage" || die "cannot read disk usage for /"
    used_before=$(get_disk_field 3 /)
    log_message "Initial disk usage: ${initial_usage}%"

    if [ "$FORCE_FLAG_USED" = true ]; then
        log_color "$YELLOW" "--force given: bypassing disk usage check"
        FORCE_MODE=true
    elif [ "$initial_usage" -ge "$CRITICAL_THRESHOLD" ]; then
        log_color "$RED" "CRITICAL: ${initial_usage}%"
        FORCE_MODE=true
        send_notification "CRITICAL: disk at ${initial_usage}% - force cleanup started"
    elif [ "$initial_usage" -ge "$THRESHOLD" ]; then
        log_color "$RED" "Disk usage ${initial_usage}% exceeds ${THRESHOLD}%"
    else
        log_color "$GREEN" "Disk usage ${initial_usage}% is below ${THRESHOLD}% - nothing to do"
        return 0
    fi

    if [ "$FORCE_MODE" = true ]; then
        log_message "--- FORCE MODE ---"
        emergency_cleanup
        for dir in "${LOG_ROOTS[@]}"; do
            force_cleanup "$dir"
        done
    else
        if [ "$ENABLE_COMPRESSION" = true ]; then
            log_message "--- Phase 1: compression ---"
            for dir in "${LOG_ROOTS[@]}"; do
                compress_logs "$dir"
            done
            log_message "Disk usage after compression: $(get_disk_usage /)%"
        fi

        current_usage=$(get_disk_usage /)
        if [ "$current_usage" -ge "$THRESHOLD" ]; then
            log_message "--- Phase 2: deletion ---"
            for dir in "${LOG_ROOTS[@]}"; do
                clean_old_logs "$dir"
            done
            clean_journal_logs "$DAYS_TO_KEEP"

            current_usage=$(get_disk_usage /)
            if [ "$current_usage" -ge "$CRITICAL_THRESHOLD" ]; then
                log_color "$RED" "--- Phase 3: escalating to FORCE MODE ---"
                FORCE_MODE=true
                emergency_cleanup
                for dir in "${LOG_ROOTS[@]}"; do
                    force_cleanup "$dir"
                done
            fi
        fi
    fi

    final_usage=$(get_disk_usage /)
    is_number "$final_usage" || final_usage=$initial_usage
    used_after=$(get_disk_field 3 /)

    log_message "=========================================="
    log_message "Cleanup summary:"
    log_message "  Mode:           $([ "$FORCE_MODE" = true ] && echo FORCE || echo standard)"
    log_message "  Files deleted:  $TOTAL_FILES_DELETED"
    log_message "  Space freed:    $(human_readable_size "$TOTAL_KB_FREED")"
    log_message "  Initial usage:  ${initial_usage}%"
    log_message "  Final usage:    ${final_usage}%"
    log_message "  Reduction:      $((initial_usage - final_usage)) points"
    log_message "=========================================="

    create_summary_report "$initial_usage" "$final_usage" \
        "$TOTAL_FILES_DELETED" "$TOTAL_KB_FREED" "$used_before" "$used_after"

    if [ "$final_usage" -ge "$CRITICAL_THRESHOLD" ]; then
        log_color "$RED" "CRITICAL: still at ${final_usage}% - manual intervention required"
        send_notification "CRITICAL: still at ${final_usage}% after cleanup"
        return 2
    elif [ "$final_usage" -ge "$THRESHOLD" ]; then
        log_color "$YELLOW" "WARNING: still at ${final_usage}%"
        send_notification "Cleanup done but usage still at ${final_usage}%"
        return 1
    fi

    log_color "$GREEN" "SUCCESS: reduced to ${final_usage}%"
    return 0
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Comprehensive log cleanup for Debian and Ubuntu systems.

Options:
  --dry-run                Show what would be removed, change nothing
  --force                  Aggressive cleanup, ignores the disk usage check
  --days N                 Keep N days of logs (default: $DAYS_TO_KEEP)
  --threshold N            Start cleaning at N% (default: $THRESHOLD)
  --critical-threshold N   Auto-enable force mode at N% (default: $CRITICAL_THRESHOLD)
  --no-compress            Skip the compression phase
  --help                   Show this help

Exit codes:
  0  success, or nothing to do
  1  cleanup ran but usage is still above --threshold
  2  cleanup ran but usage is still above --critical-threshold
  3  invalid arguments or another instance is running
EOF
}

#############################################
# Argument parsing
#############################################

require_number() {
    is_number "$2" || { echo "Error: $1 requires a number, got '${2:-<missing>}'" >&2; exit 3; }
}

while [ $# -gt 0 ]; do
    case $1 in
        --dry-run)  DRY_RUN=true; shift ;;
        --force)    FORCE_MODE=true; FORCE_FLAG_USED=true; shift ;;
        --no-compress) ENABLE_COMPRESSION=false; shift ;;
        --days)     require_number "$1" "${2:-}"; DAYS_TO_KEEP=$2; shift 2 ;;
        --threshold) require_number "$1" "${2:-}"; THRESHOLD=$2; shift 2 ;;
        --critical-threshold) require_number "$1" "${2:-}"; CRITICAL_THRESHOLD=$2; shift 2 ;;
        --help|-h)  usage; exit 0 ;;
        *)          echo "Unknown option: $1" >&2; usage >&2; exit 3 ;;
    esac
done

if [ "$THRESHOLD" -gt "$CRITICAL_THRESHOLD" ]; then
    echo "Error: --threshold ($THRESHOLD) must not exceed --critical-threshold ($CRITICAL_THRESHOLD)" >&2
    exit 3
fi

# Single instance only. Two overlapping cron runs (the daily job and the
# weekly --force job land on the same minute) would double-count freed
# space and race on truncation.
mkdir -p "$(dirname "$LOCK_FILE")" 2>/dev/null
if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE" 2>/dev/null
    if [ -e /dev/fd/9 ] && ! flock -n 9; then
        echo "Another cleanup run is already in progress ($LOCK_FILE)" >&2
        exit 3
    fi
fi

main
exit $?
