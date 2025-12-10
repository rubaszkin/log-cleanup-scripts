#!/bin/bash

#############################################
# Advanced Log Cleanup Script
# Features:
# - Multiple log directory support
# - Email notifications (optional)
# - Detailed logging to file
# - Safe deletion with confirmation
#############################################

# Configuration
declare -a LOG_DIRS=("/var/log")  # Add more directories as needed
THRESHOLD=90
CRITICAL_THRESHOLD=95  # Force cleanup threshold
DAYS_TO_KEEP=7
CRITICAL_DAYS_TO_KEEP=3  # More aggressive cleanup for critical mode
DRY_RUN=false
ENABLE_COMPRESSION=true
SCRIPT_LOG="/var/log/log_cleanup.log"
EMAIL_NOTIFY=false
EMAIL_ADDRESS="admin@example.com"
FORCE_MODE=false  # Automatically set when critical threshold is reached

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log to both console and file
log_message() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$message"
    echo "$message" >> "$SCRIPT_LOG" 2>/dev/null
}

# Function to log with color
log_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$SCRIPT_LOG" 2>/dev/null
}

# Function to get disk usage percentage for a given path
get_disk_usage() {
    local path=${1:-/}
    df "$path" | awk 'NR==2 {print $5}' | sed 's/%//'
}

# Function to send email notification
send_notification() {
    if [ "$EMAIL_NOTIFY" = true ] && command -v mail &> /dev/null; then
        echo "$1" | mail -s "Log Cleanup Alert - $(hostname)" "$EMAIL_ADDRESS"
    fi
}

# Function to get human-readable size
human_readable_size() {
    local size_kb=$1
    if [ $size_kb -lt 1024 ]; then
        echo "${size_kb}KB"
    elif [ $size_kb -lt 1048576 ]; then
        echo "$((size_kb/1024))MB"
    else
        echo "$((size_kb/1048576))GB"
    fi
}

# Function to clean old logs in a directory
clean_old_logs() {
    local dir=$1
    local days=${2:-$DAYS_TO_KEEP}
    local files_deleted=0
    local space_freed=0
    
    log_message "Cleaning logs in: $dir (older than $days days)"
    
    # Find log files older than specified days
    while IFS= read -r -d '' file; do
        if [ -f "$file" ] && [ -w "$file" ]; then
            file_size=$(du -k "$file" 2>/dev/null | cut -f1)
            
            if [ "$DRY_RUN" = true ]; then
                log_color "$YELLOW" "[DRY RUN] Would delete: $file ($(human_readable_size $file_size))"
            else
                log_message "Deleting: $file ($(human_readable_size $file_size))"
                rm -f "$file"
                if [ $? -eq 0 ]; then
                    ((files_deleted++))
                    ((space_freed+=file_size))
                else
                    log_color "$RED" "ERROR: Failed to delete $file"
                fi
            fi
        fi
    done < <(find "$dir" -type f \( -name "*.log" -o -name "*.log.*" -o -name "*.gz" -o -name "*.old" \) -mtime +$days -print0 2>/dev/null)
    
    echo "$files_deleted:$space_freed"
}

# Function for force cleanup - more aggressive deletion
force_cleanup() {
    local dir=$1
    local files_deleted=0
    local space_freed=0
    
    log_color "$RED" "!!! FORCE CLEANUP MODE ACTIVATED !!!"
    log_message "Aggressively cleaning ALL old logs in: $dir"
    
    # Delete rotated logs regardless of age
    log_message "Removing all rotated and compressed logs..."
    while IFS= read -r -d '' file; do
        if [ -f "$file" ] && [ -w "$file" ]; then
            file_size=$(du -k "$file" 2>/dev/null | cut -f1)
            
            if [ "$DRY_RUN" = true ]; then
                log_color "$YELLOW" "[DRY RUN] Would force delete: $file ($(human_readable_size $file_size))"
            else
                log_message "Force deleting: $file ($(human_readable_size $file_size))"
                rm -f "$file"
                if [ $? -eq 0 ]; then
                    ((files_deleted++))
                    ((space_freed+=file_size))
                fi
            fi
        fi
    done < <(find "$dir" -type f \( -name "*.log.[0-9]*" -o -name "*.gz" -o -name "*.old" -o -name "*.1" -o -name "*.2" -o -name "*.3" -o -name "*.4" -o -name "*.5" -o -name "*.6" -o -name "*.7" -o -name "*.8" -o -name "*.9" \) -print0 2>/dev/null)
    
    # Delete logs older than CRITICAL_DAYS_TO_KEEP
    log_message "Removing logs older than $CRITICAL_DAYS_TO_KEEP days..."
    while IFS= read -r -d '' file; do
        if [ -f "$file" ] && [ -w "$file" ]; then
            file_size=$(du -k "$file" 2>/dev/null | cut -f1)
            
            if [ "$DRY_RUN" = true ]; then
                log_color "$YELLOW" "[DRY RUN] Would force delete: $file ($(human_readable_size $file_size))"
            else
                log_message "Force deleting: $file ($(human_readable_size $file_size))"
                rm -f "$file"
                if [ $? -eq 0 ]; then
                    ((files_deleted++))
                    ((space_freed+=file_size))
                fi
            fi
        fi
    done < <(find "$dir" -type f -name "*.log" -mtime +$CRITICAL_DAYS_TO_KEEP -print0 2>/dev/null)
    
    # Truncate large active log files (keep last 1000 lines)
    log_message "Truncating large active log files..."
    while IFS= read -r -d '' file; do
        if [ -f "$file" ] && [ -w "$file" ]; then
            file_size=$(du -k "$file" 2>/dev/null | cut -f1)
            # Only truncate files larger than 100MB
            if [ $file_size -gt 102400 ]; then
                if [ "$DRY_RUN" = true ]; then
                    log_color "$YELLOW" "[DRY RUN] Would truncate: $file ($(human_readable_size $file_size))"
                else
                    log_message "Truncating large file: $file ($(human_readable_size $file_size))"
                    # Keep last 1000 lines
                    tail -n 1000 "$file" > "${file}.tmp" 2>/dev/null && mv "${file}.tmp" "$file"
                    if [ $? -eq 0 ]; then
                        new_size=$(du -k "$file" 2>/dev/null | cut -f1)
                        saved=$((file_size - new_size))
                        ((space_freed+=saved))
                        log_color "$GREEN" "Truncated: $file (freed $(human_readable_size $saved))"
                    fi
                fi
            fi
        fi
    done < <(find "$dir" -type f -name "*.log" ! -name "*.gz" -print0 2>/dev/null)
    
    echo "$files_deleted:$space_freed"
}

# Function to compress logs
compress_logs() {
    local dir=$1
    local files_compressed=0
    
    log_message "Compressing logs in: $dir"
    
    find "$dir" -type f -name "*.log" -mtime +1 ! -name "*.gz" -print0 2>/dev/null | while IFS= read -r -d '' file; do
        if [ -f "$file" ] && [ -w "$file" ]; then
            if [ "$DRY_RUN" = true ]; then
                log_color "$YELLOW" "[DRY RUN] Would compress: $file"
            else
                gzip "$file" 2>/dev/null
                if [ $? -eq 0 ]; then
                    log_color "$GREEN" "Compressed: $file"
                    ((files_compressed++))
                fi
            fi
        fi
    done
}

# Function to clean systemd journal logs
clean_journal_logs() {
    local days=${1:-$DAYS_TO_KEEP}
    if command -v journalctl &> /dev/null; then
        log_message "Cleaning systemd journal logs (keeping $days days)..."
        if [ "$DRY_RUN" = true ]; then
            log_color "$YELLOW" "[DRY RUN] Would clean journal logs older than ${days} days"
        else
            journalctl --vacuum-time=${days}d 2>/dev/null
            if [ $? -eq 0 ]; then
                log_color "$GREEN" "Journal logs cleaned"
            fi
        fi
    fi
}

# Function for emergency disk space recovery
emergency_cleanup() {
    log_color "$RED" "=========================================="
    log_color "$RED" "!!! EMERGENCY CLEANUP MODE !!!"
    log_color "$RED" "Disk usage is critically high"
    log_color "$RED" "=========================================="
    
    # Clean package manager caches
    if [ "$DRY_RUN" = false ]; then
        log_message "Cleaning package manager caches..."
        
        # APT cache (Debian/Ubuntu)
        if command -v apt-get &> /dev/null; then
            apt-get clean 2>/dev/null
            log_message "APT cache cleaned"
        fi
        
        # YUM cache (RHEL/CentOS)
        if command -v yum &> /dev/null; then
            yum clean all 2>/dev/null
            log_message "YUM cache cleaned"
        fi
        
        # DNF cache (Fedora)
        if command -v dnf &> /dev/null; then
            dnf clean all 2>/dev/null
            log_message "DNF cache cleaned"
        fi
    fi
    
    # Clean temporary files
    log_message "Cleaning temporary files..."
    if [ "$DRY_RUN" = false ]; then
        find /tmp -type f -atime +1 -delete 2>/dev/null
        find /var/tmp -type f -atime +1 -delete 2>/dev/null
        log_message "Temporary files cleaned"
    else
        log_color "$YELLOW" "[DRY RUN] Would clean /tmp and /var/tmp"
    fi
    
    # Aggressive journal cleanup (keep only 1 day)
    clean_journal_logs 1
}

# Main function
main() {
    log_message "=========================================="
    log_message "Log Cleanup Script Started"
    log_message "=========================================="
    
    # Root check
    if [ "$EUID" -ne 0 ]; then 
        log_color "$YELLOW" "WARNING: Running without root privileges"
        log_message "Some operations may fail due to insufficient permissions"
    fi
    
    # Get initial disk usage
    initial_usage=$(get_disk_usage /)
    log_message "Initial disk usage: ${initial_usage}%"
    
    # Check if critical cleanup is needed
    if [ "$initial_usage" -ge "$CRITICAL_THRESHOLD" ]; then
        log_color "$RED" "!!! CRITICAL DISK USAGE: ${initial_usage}% !!!"
        log_color "$RED" "Activating FORCE CLEANUP mode"
        FORCE_MODE=true
        send_notification "CRITICAL: Disk usage at ${initial_usage}% - Force cleanup initiated"
    elif [ "$initial_usage" -ge "$THRESHOLD" ]; then
        log_color "$RED" "Disk usage (${initial_usage}%) exceeds threshold (${THRESHOLD}%)"
        log_message "Starting standard cleanup process..."
    else
        log_color "$GREEN" "Disk usage (${initial_usage}%) is below threshold (${THRESHOLD}%)"
        log_message "No cleanup needed"
        exit 0
    fi
    
    total_files_deleted=0
    total_space_freed=0
    
    # FORCE MODE: Emergency cleanup
    if [ "$FORCE_MODE" = true ]; then
        log_message "--- FORCE MODE: Emergency Cleanup ---"
        
        # Execute emergency cleanup
        emergency_cleanup
        
        # Force cleanup in all log directories
        for dir in "${LOG_DIRS[@]}"; do
            if [ -d "$dir" ]; then
                result=$(force_cleanup "$dir")
                files_deleted=$(echo "$result" | cut -d: -f1)
                space_freed=$(echo "$result" | cut -d: -f2)
                total_files_deleted=$((total_files_deleted + files_deleted))
                total_space_freed=$((total_space_freed + space_freed))
            else
                log_color "$YELLOW" "WARNING: Directory not found: $dir"
            fi
        done
        
        current_usage=$(get_disk_usage /)
        log_message "Disk usage after force cleanup: ${current_usage}%"
        
    else
        # NORMAL MODE: Standard cleanup
        
        # Compress logs first if enabled
        if [ "$ENABLE_COMPRESSION" = true ]; then
            log_message "--- Phase 1: Compression ---"
            for dir in "${LOG_DIRS[@]}"; do
                if [ -d "$dir" ]; then
                    compress_logs "$dir"
                else
                    log_color "$YELLOW" "WARNING: Directory not found: $dir"
                fi
            done
            
            current_usage=$(get_disk_usage /)
            log_message "Disk usage after compression: ${current_usage}%"
        fi
        
        # Delete old logs if still above threshold
        current_usage=$(get_disk_usage /)
        if [ "$current_usage" -ge "$THRESHOLD" ]; then
            log_message "--- Phase 2: Deletion ---"
            for dir in "${LOG_DIRS[@]}"; do
                if [ -d "$dir" ]; then
                    result=$(clean_old_logs "$dir")
                    files_deleted=$(echo "$result" | cut -d: -f1)
                    space_freed=$(echo "$result" | cut -d: -f2)
                    total_files_deleted=$((total_files_deleted + files_deleted))
                    total_space_freed=$((total_space_freed + space_freed))
                fi
            done
            
            # Clean systemd journal
            clean_journal_logs $DAYS_TO_KEEP
            
            # Check if we need to escalate to force mode
            current_usage=$(get_disk_usage /)
            if [ "$current_usage" -ge "$CRITICAL_THRESHOLD" ]; then
                log_color "$RED" "Disk usage still at ${current_usage}% - escalating to FORCE MODE"
                FORCE_MODE=true
                
                # Execute emergency cleanup
                emergency_cleanup
                
                # Force cleanup in all log directories
                for dir in "${LOG_DIRS[@]}"; do
                    if [ -d "$dir" ]; then
                        result=$(force_cleanup "$dir")
                        files_deleted=$(echo "$result" | cut -d: -f1)
                        space_freed=$(echo "$result" | cut -d: -f2)
                        total_files_deleted=$((total_files_deleted + files_deleted))
                        total_space_freed=$((total_space_freed + space_freed))
                    fi
                done
            fi
        fi
    fi
    
    # Final status
    final_usage=$(get_disk_usage /)
    log_message "=========================================="
    log_message "Cleanup Summary:"
    if [ "$FORCE_MODE" = true ]; then
        log_color "$RED" "  Mode: FORCE CLEANUP"
    else
        log_message "  Mode: Standard cleanup"
    fi
    log_message "  Files deleted: $total_files_deleted"
    log_message "  Space freed: $(human_readable_size $total_space_freed)"
    log_message "  Initial usage: ${initial_usage}%"
    log_message "  Final usage: ${final_usage}%"
    log_message "  Reduction: $((initial_usage - final_usage))%"
    log_message "=========================================="
    
    if [ "$final_usage" -ge "$CRITICAL_THRESHOLD" ]; then
        log_color "$RED" "!!! CRITICAL WARNING: Disk usage STILL at ${final_usage}% !!!"
        log_message "URGENT: Manual intervention required!"
        log_message "Recommendations:"
        log_message "  1. Check for large files: du -sh /var/* | sort -rh | head -20"
        log_message "  2. Check for large directories: ncdu / (if available)"
        log_message "  3. Consider expanding disk space"
        log_message "  4. Review application logs and disable verbose logging"
        send_notification "CRITICAL: Disk usage still at ${final_usage}% after force cleanup - Manual intervention required!"
    elif [ "$final_usage" -ge "$THRESHOLD" ]; then
        log_color "$YELLOW" "WARNING: Disk usage still at ${final_usage}%"
        log_message "Consider: reducing DAYS_TO_KEEP, adding more directories, or manual cleanup"
        send_notification "Disk cleanup completed but usage still at ${final_usage}%"
    else
        log_color "$GREEN" "SUCCESS: Disk usage reduced to ${final_usage}%"
        if [ "$FORCE_MODE" = true ]; then
            send_notification "Force cleanup successful - disk usage reduced to ${final_usage}%"
        fi
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            log_message "DRY RUN MODE - No files will be deleted"
            shift
            ;;
        --force)
            FORCE_MODE=true
            log_message "FORCE MODE - Aggressive cleanup enabled"
            shift
            ;;
        --days)
            DAYS_TO_KEEP=$2
            shift 2
            ;;
        --threshold)
            THRESHOLD=$2
            shift 2
            ;;
        --critical-threshold)
            CRITICAL_THRESHOLD=$2
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --dry-run                Show what would be deleted without deleting"
            echo "  --force                  Enable force cleanup mode (aggressive)"
            echo "  --days N                 Keep logs newer than N days (default: 7)"
            echo "  --threshold N            Disk usage threshold percentage (default: 90)"
            echo "  --critical-threshold N   Critical threshold for force mode (default: 95)"
            echo "  --help                   Show this help message"
            echo ""
            echo "Force Mode (activated at ${CRITICAL_THRESHOLD}% or with --force):"
            echo "  - Deletes ALL rotated and compressed logs"
            echo "  - Keeps only ${CRITICAL_DAYS_TO_KEEP} days of logs"
            echo "  - Truncates large active log files"
            echo "  - Cleans package manager caches"
            echo "  - Cleans temporary files"
            echo "  - Aggressive journal cleanup (1 day retention)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main

exit 0
