#!/bin/bash

#############################################
# Log Cleanup Script
# Cleans old logs from /var/log when disk 
# usage exceeds 90%
#############################################

# Configuration
LOG_DIR="/var/log"
THRESHOLD=90
DAYS_TO_KEEP=7  # Delete logs older than this many days
DRY_RUN=false   # Set to true to see what would be deleted without actually deleting

# Function to get disk usage percentage
get_disk_usage() {
    df -h / | awk 'NR==2 {print $5}' | sed 's/%//'
}

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to clean old logs
clean_old_logs() {
    local files_deleted=0
    local space_freed=0
    
    log_message "Starting log cleanup process..."
    log_message "Looking for log files older than $DAYS_TO_KEEP days in $LOG_DIR"
    
    # Find and process old log files
    while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            file_size=$(du -k "$file" | cut -f1)
            
            if [ "$DRY_RUN" = true ]; then
                log_message "[DRY RUN] Would delete: $file (${file_size}KB)"
            else
                log_message "Deleting: $file (${file_size}KB)"
                rm -f "$file"
                if [ $? -eq 0 ]; then
                    ((files_deleted++))
                    ((space_freed+=file_size))
                else
                    log_message "ERROR: Failed to delete $file"
                fi
            fi
        fi
    done < <(find "$LOG_DIR" -type f \( -name "*.log" -o -name "*.log.*" -o -name "*.gz" \) -mtime +$DAYS_TO_KEEP -print0 2>/dev/null)
    
    if [ "$DRY_RUN" = true ]; then
        log_message "[DRY RUN] Would have deleted $files_deleted files"
        log_message "[DRY RUN] Would have freed approximately $((space_freed/1024))MB"
    else
        log_message "Cleanup complete: Deleted $files_deleted files"
        log_message "Space freed: approximately $((space_freed/1024))MB"
    fi
}

# Function to compress recent logs
compress_logs() {
    log_message "Compressing uncompressed log files older than 1 day..."
    
    find "$LOG_DIR" -type f -name "*.log" -mtime +1 ! -name "*.gz" -print0 2>/dev/null | while IFS= read -r -d '' file; do
        if [ "$DRY_RUN" = true ]; then
            log_message "[DRY RUN] Would compress: $file"
        else
            log_message "Compressing: $file"
            gzip "$file" 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "Successfully compressed: $file"
            else
                log_message "WARNING: Failed to compress $file"
            fi
        fi
    done
}

# Main script execution
main() {
    log_message "=== Log Cleanup Script Started ==="
    
    # Check if script is run as root
    if [ "$EUID" -ne 0 ]; then 
        log_message "WARNING: This script should be run as root for full access to /var/log"
        log_message "Some files may not be accessible or deletable"
    fi
    
    # Check if log directory exists
    if [ ! -d "$LOG_DIR" ]; then
        log_message "ERROR: Log directory $LOG_DIR does not exist"
        exit 1
    fi
    
    # Get current disk usage
    current_usage=$(get_disk_usage)
    log_message "Current disk usage: ${current_usage}%"
    
    # Check if cleanup is needed
    if [ "$current_usage" -ge "$THRESHOLD" ]; then
        log_message "Disk usage (${current_usage}%) exceeds threshold (${THRESHOLD}%)"
        log_message "Initiating cleanup process..."
        
        # First, try compressing logs
        compress_logs
        
        # Check usage again
        current_usage=$(get_disk_usage)
        log_message "Disk usage after compression: ${current_usage}%"
        
        # If still above threshold, delete old logs
        if [ "$current_usage" -ge "$THRESHOLD" ]; then
            clean_old_logs
            
            # Final check
            current_usage=$(get_disk_usage)
            log_message "Final disk usage: ${current_usage}%"
            
            if [ "$current_usage" -ge "$THRESHOLD" ]; then
                log_message "WARNING: Disk usage still at ${current_usage}% after cleanup"
                log_message "Consider manual intervention or adjusting DAYS_TO_KEEP"
            else
                log_message "SUCCESS: Disk usage reduced below threshold"
            fi
        else
            log_message "SUCCESS: Disk usage reduced below threshold after compression"
        fi
    else
        log_message "Disk usage (${current_usage}%) is below threshold (${THRESHOLD}%)"
        log_message "No cleanup needed at this time"
    fi
    
    log_message "=== Log Cleanup Script Completed ==="
}

# Run main function
main

exit 0
