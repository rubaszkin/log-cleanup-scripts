#!/bin/bash

#############################################
# Comprehensive Fedora/CentOS/RHEL Log Cleanup Script
# Targets ALL possible log locations for Red Hat-based systems
# With Force Mode for critical disk usage
#############################################

set -e  # Exit on error for critical operations

# Configuration
declare -a LOG_DIRS=(
    "/var/log"                          # Main system logs
    "/var/log/httpd"                    # Apache web server (RHEL/CentOS)
    "/var/log/nginx"                    # Nginx web server
    "/var/log/mariadb"                  # MariaDB database
    "/var/log/mysql"                    # MySQL database
    "/var/log/postgresql"               # PostgreSQL database
    "/var/log/pgsql"                    # PostgreSQL alternative
    "/var/log/samba"                    # Samba file sharing
    "/var/log/cups"                     # Print server
    "/var/log/yum.log"                  # YUM package manager
    "/var/log/dnf.log"                  # DNF package manager (Fedora)
    "/var/log/dnf.rpm.log"              # DNF RPM logs
    "/var/log/mail"                     # Mail server logs
    "/var/log/maillog"                  # Mail log alternative
    "/var/log/exim"                     # Exim mail server
    "/var/log/postfix"                  # Postfix mail server
    "/var/log/dovecot"                  # Dovecot IMAP/POP3
    "/var/log/vsftpd"                   # vsFTPD server
    "/var/log/proftpd"                  # ProFTPD server
    "/var/log/named"                    # BIND DNS server
    "/var/log/squid"                    # Squid proxy
    "/var/log/snort"                    # Snort IDS
    "/var/log/fail2ban"                 # Fail2ban
    "/var/log/firewalld"                # FirewallD
    "/var/log/audit"                    # Audit logs
    "/var/log/supervisor"               # Supervisor process control
    "/var/log/redis"                    # Redis database
    "/var/log/mongodb"                  # MongoDB database
    "/var/log/elasticsearch"            # Elasticsearch
    "/var/log/logstash"                 # Logstash
    "/var/log/kibana"                   # Kibana
    "/var/log/docker"                   # Docker logs
    "/var/log/gitlab"                   # GitLab
    "/var/log/jenkins"                  # Jenkins CI/CD
    "/var/log/tomcat"                   # Tomcat
    "/var/log/jboss"                    # JBoss/WildFly
    "/var/log/wildfly"                  # WildFly application server
    "/var/log/selinux"                  # SELinux logs
    "/var/log/setroubleshoot"           # SELinux troubleshooter
    "/opt/lampp/logs"                   # XAMPP logs
    "/home/*/logs"                      # User logs
    "/root/logs"                        # Root user logs
    "/tmp"                              # Temporary files
    "/var/tmp"                          # Variable temp files
    "/var/cache/yum"                    # YUM cache
    "/var/cache/dnf"                    # DNF cache
    "/var/lib/systemd/coredump"         # Core dumps
)

THRESHOLD=90
CRITICAL_THRESHOLD=95
DAYS_TO_KEEP=7
CRITICAL_DAYS_TO_KEEP=3
DRY_RUN=false
ENABLE_COMPRESSION=true
SCRIPT_LOG="/var/log/log_cleanup.log"
SUMMARY_REPORT="/var/log/log_cleanup_summary.txt"
EMAIL_NOTIFY=false
EMAIL_ADDRESS="admin@example.com"
FORCE_MODE=false
FORCE_FLAG_USED=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to log messages
log_message() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$message"
    echo "$message" >> "$SCRIPT_LOG" 2>/dev/null
}

log_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$SCRIPT_LOG" 2>/dev/null
}

# Function to get disk usage
get_disk_usage() {
    local path=${1:-/}
    df "$path" 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//'
}

# Function to send notification
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
    
    # Check if directory exists
    if [ ! -d "$dir" ]; then
        return
    fi
    
    log_message "Cleaning logs in: $dir (older than $days days)"
    
    # Find and delete old log files
    while IFS= read -r -d '' file; do
        if [ -f "$file" ] && [ -w "$file" ]; then
            file_size=$(du -k "$file" 2>/dev/null | cut -f1)
            
            if [ "$DRY_RUN" = true ]; then
                log_color "$YELLOW" "[DRY RUN] Would delete: $file ($(human_readable_size $file_size))"
            else
                log_message "Deleting: $file ($(human_readable_size $file_size))"
                rm -f "$file" 2>/dev/null
                if [ $? -eq 0 ]; then
                    ((files_deleted++))
                    ((space_freed+=file_size))
                fi
            fi
        fi
    done < <(find "$dir" -type f \( -name "*.log" -o -name "*.log.*" -o -name "*.gz" -o -name "*.old" -o -name "*.1" -o -name "*.2" -o -name "*.3" -o -name "*.4" -o -name "*.5" -o -name "*.6" -o -name "*.7" -o -name "*.8" -o -name "*.9" \) -mtime +$days -print0 2>/dev/null)
    
    echo "$files_deleted:$space_freed"
}

# Function for force cleanup
force_cleanup() {
    local dir=$1
    local files_deleted=0
    local space_freed=0
    
    if [ ! -d "$dir" ]; then
        return
    fi
    
    log_color "$RED" "!!! FORCE CLEANUP in: $dir !!!"
    
    # Delete ALL rotated and compressed logs
    while IFS= read -r -d '' file; do
        if [ -f "$file" ] && [ -w "$file" ]; then
            file_size=$(du -k "$file" 2>/dev/null | cut -f1)
            
            if [ "$DRY_RUN" = true ]; then
                log_color "$YELLOW" "[DRY RUN] Would force delete: $file ($(human_readable_size $file_size))"
            else
                rm -f "$file" 2>/dev/null
                if [ $? -eq 0 ]; then
                    ((files_deleted++))
                    ((space_freed+=file_size))
                fi
            fi
        fi
    done < <(find "$dir" -type f \( -name "*.log.[0-9]*" -o -name "*.gz" -o -name "*.old" -o -name "*.1" -o -name "*.2" -o -name "*.3" -o -name "*.4" -o -name "*.5" -o -name "*.6" -o -name "*.7" -o -name "*.8" -o -name "*.9" \) -print0 2>/dev/null)
    
    # Delete logs older than CRITICAL_DAYS_TO_KEEP
    while IFS= read -r -d '' file; do
        if [ -f "$file" ] && [ -w "$file" ]; then
            file_size=$(du -k "$file" 2>/dev/null | cut -f1)
            
            if [ "$DRY_RUN" = true ]; then
                log_color "$YELLOW" "[DRY RUN] Would force delete: $file ($(human_readable_size $file_size))"
            else
                rm -f "$file" 2>/dev/null
                if [ $? -eq 0 ]; then
                    ((files_deleted++))
                    ((space_freed+=file_size))
                fi
            fi
        fi
    done < <(find "$dir" -type f -name "*.log" -mtime +$CRITICAL_DAYS_TO_KEEP -print0 2>/dev/null)
    
    # Truncate large active logs
    while IFS= read -r -d '' file; do
        if [ -f "$file" ] && [ -w "$file" ]; then
            file_size=$(du -k "$file" 2>/dev/null | cut -f1)
            if [ $file_size -gt 102400 ]; then  # >100MB
                if [ "$DRY_RUN" = true ]; then
                    log_color "$YELLOW" "[DRY RUN] Would truncate: $file ($(human_readable_size $file_size))"
                else
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
    
    if [ ! -d "$dir" ]; then
        return
    fi
    
    log_message "Compressing logs in: $dir"
    
    find "$dir" -type f -name "*.log" -mtime +1 ! -name "*.gz" -print0 2>/dev/null | while IFS= read -r -d '' file; do
        if [ -f "$file" ] && [ -w "$file" ]; then
            if [ "$DRY_RUN" = true ]; then
                log_color "$YELLOW" "[DRY RUN] Would compress: $file"
            else
                gzip "$file" 2>/dev/null
                if [ $? -eq 0 ]; then
                    log_color "$GREEN" "Compressed: $file"
                fi
            fi
        fi
    done
}

# Function to clean systemd journal
clean_journal_logs() {
    local days=${1:-$DAYS_TO_KEEP}
    if command -v journalctl &> /dev/null; then
        log_message "Cleaning systemd journal (keeping $days days)..."
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

# Function for RHEL/Fedora-specific cleanup
rhel_specific_cleanup() {
    log_message "--- RHEL/Fedora-Specific Cleanup ---"
    
    # Clean YUM cache (CentOS/RHEL 7)
    if command -v yum &> /dev/null; then
        if [ "$DRY_RUN" = false ]; then
            log_message "Cleaning YUM cache..."
            yum clean all 2>/dev/null && log_color "$GREEN" "YUM cache cleaned"
        else
            log_color "$YELLOW" "[DRY RUN] Would clean YUM cache"
        fi
    fi
    
    # Clean DNF cache (Fedora/RHEL 8+)
    if command -v dnf &> /dev/null; then
        if [ "$DRY_RUN" = false ]; then
            log_message "Cleaning DNF cache..."
            dnf clean all 2>/dev/null && log_color "$GREEN" "DNF cache cleaned"
        else
            log_color "$YELLOW" "[DRY RUN] Would clean DNF cache"
        fi
    fi
    
    # Clean old kernels (keep current + 1)
    if [ "$FORCE_MODE" = true ] && [ "$DRY_RUN" = false ]; then
        log_message "Cleaning old kernels..."
        if command -v dnf &> /dev/null; then
            # Fedora/RHEL 8+
            dnf remove --oldinstallonly --setopt installonly_limit=2 -y 2>/dev/null
            log_color "$GREEN" "Old kernels cleaned (DNF)"
        elif command -v package-cleanup &> /dev/null; then
            # CentOS/RHEL 7
            package-cleanup --oldkernels --count=2 -y 2>/dev/null
            log_color "$GREEN" "Old kernels cleaned (YUM)"
        fi
    fi
    
    # Clean PackageKit cache
    if [ "$FORCE_MODE" = true ] && [ "$DRY_RUN" = false ]; then
        log_message "Cleaning PackageKit cache..."
        rm -rf /var/cache/PackageKit/* 2>/dev/null
        log_color "$GREEN" "PackageKit cache cleaned"
    fi
    
    # Clean thumbnail cache
    if [ "$FORCE_MODE" = true ] && [ "$DRY_RUN" = false ]; then
        log_message "Cleaning thumbnail cache..."
        rm -rf /home/*/.cache/thumbnails/* 2>/dev/null
        rm -rf /root/.cache/thumbnails/* 2>/dev/null
        log_color "$GREEN" "Thumbnail cache cleaned"
    fi
    
    # Clean Docker logs if Docker is installed
    if command -v docker &> /dev/null; then
        log_message "Cleaning Docker logs..."
        if [ "$DRY_RUN" = false ]; then
            find /var/lib/docker/containers/ -name "*.log" -type f -exec truncate -s 0 {} \; 2>/dev/null
            log_color "$GREEN" "Docker logs cleaned"
        else
            log_color "$YELLOW" "[DRY RUN] Would clean Docker logs"
        fi
    fi
    
    # Clean core dumps
    if [ "$FORCE_MODE" = true ] && [ "$DRY_RUN" = false ]; then
        log_message "Cleaning core dumps..."
        rm -f /var/lib/systemd/coredump/* 2>/dev/null
        rm -f /var/crash/* 2>/dev/null
        log_color "$GREEN" "Core dumps cleaned"
    fi
    
    # Clean audit logs (if very old)
    if [ "$FORCE_MODE" = true ] && [ "$DRY_RUN" = false ]; then
        log_message "Cleaning old audit logs..."
        find /var/log/audit -name "audit.log.*" -mtime +30 -delete 2>/dev/null
        log_color "$GREEN" "Old audit logs cleaned"
    fi
    
    # Rotate audit logs manually if needed
    if [ "$FORCE_MODE" = true ] && [ "$DRY_RUN" = false ]; then
        if [ -f /var/log/audit/audit.log ]; then
            audit_size=$(du -k /var/log/audit/audit.log 2>/dev/null | cut -f1)
            if [ $audit_size -gt 1048576 ]; then  # >1GB
                log_message "Rotating large audit.log..."
                service auditd rotate 2>/dev/null || systemctl kill -s SIGUSR1 auditd.service 2>/dev/null
                log_color "$GREEN" "Audit log rotated"
            fi
        fi
    fi
}

# Function for emergency cleanup
emergency_cleanup() {
    log_color "$RED" "=========================================="
    log_color "$RED" "!!! EMERGENCY CLEANUP MODE !!!"
    log_color "$RED" "=========================================="
    
    # RHEL-specific cleanup
    rhel_specific_cleanup
    
    # Clean temporary files
    if [ "$DRY_RUN" = false ]; then
        log_message "Cleaning temporary files..."
        find /tmp -type f -atime +1 -delete 2>/dev/null
        find /var/tmp -type f -atime +1 -delete 2>/dev/null
        log_message "Temporary files cleaned"
    else
        log_color "$YELLOW" "[DRY RUN] Would clean temporary files"
    fi
    
    # Aggressive journal cleanup
    clean_journal_logs 1
}

# Function to create detailed summary report
create_summary_report() {
    local initial_usage=$1
    local final_usage=$2
    local files_deleted=$3
    local space_freed_kb=$4
    
    local space_freed_mb=$((space_freed_kb / 1024))
    local space_freed_gb=$((space_freed_kb / 1048576))
    local reduction=$((initial_usage - final_usage))
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hostname=$(hostname)
    
    # Get disk information
    local disk_info=$(df -h / | awk 'NR==2 {print $2, $3, $4}')
    local total_size=$(echo $disk_info | awk '{print $1}')
    local used_size=$(echo $disk_info | awk '{print $2}')
    local available_size=$(echo $disk_info | awk '{print $3}')
    
    # Determine cleanup mode
    local cleanup_mode="Standard Cleanup"
    if [ "$FORCE_MODE" = true ]; then
        if [ "$FORCE_FLAG_USED" = true ]; then
            cleanup_mode="FORCE CLEANUP (Manual Override)"
        else
            cleanup_mode="FORCE CLEANUP (Auto-activated)"
        fi
    fi
    
    # Detect OS
    local os_info="Unknown"
    if [ -f /etc/fedora-release ]; then
        os_info=$(cat /etc/fedora-release)
    elif [ -f /etc/redhat-release ]; then
        os_info=$(cat /etc/redhat-release)
    elif [ -f /etc/centos-release ]; then
        os_info=$(cat /etc/centos-release)
    fi
    
    # Count directories cleaned
    local dirs_checked=0
    local dirs_cleaned=0
    for dir in "${LOG_DIRS[@]}"; do
        ((dirs_checked++))
        if [ -d "$dir" ]; then
            ((dirs_cleaned++))
        fi
    done
    
    # Create summary report
    cat > "$SUMMARY_REPORT" << EOF
╔══════════════════════════════════════════════════════════════════════╗
║      FEDORA/CENTOS/RHEL LOG CLEANUP SUMMARY REPORT                   ║
╚══════════════════════════════════════════════════════════════════════╝

EXECUTION DETAILS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Timestamp:           $timestamp
Hostname:            $hostname
Operating System:    $os_info
Script:              $(basename $0)
Cleanup Mode:        $cleanup_mode
Dry Run:             $DRY_RUN

DISK USAGE STATISTICS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total Disk Size:     $total_size
Used Before:         $used_size (${initial_usage}%)
Used After:          $available_size (${final_usage}%)
Usage Reduction:     ${reduction}%

CLEANUP RESULTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Files Deleted:       $files_deleted
Space Freed (KB):    ${space_freed_kb} KB
Space Freed (MB):    ${space_freed_mb} MB
Space Freed (GB):    ${space_freed_gb} GB
Human Readable:      $(human_readable_size $space_freed_kb)

DIRECTORIES PROCESSED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total Checked:       $dirs_checked locations
Successfully Found:  $dirs_cleaned locations

THRESHOLDS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Standard Threshold:  ${THRESHOLD}%
Critical Threshold:  ${CRITICAL_THRESHOLD}%
Days Retained:       $([ "$FORCE_MODE" = true ] && echo "$CRITICAL_DAYS_TO_KEEP" || echo "$DAYS_TO_KEEP") days

LOG DIRECTORIES CLEANED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

    # Add directories that were cleaned
    for dir in "${LOG_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            echo "  ✓ $dir" >> "$SUMMARY_REPORT"
        fi
    done
    
    # Add RHEL-specific cleanup details
    cat >> "$SUMMARY_REPORT" << EOF

RHEL/FEDORA-SPECIFIC CLEANUP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

    if command -v yum &> /dev/null; then
        echo "  ✓ YUM cache cleaned" >> "$SUMMARY_REPORT"
    fi
    
    if command -v dnf &> /dev/null; then
        echo "  ✓ DNF cache cleaned" >> "$SUMMARY_REPORT"
    fi
    
    if [ "$FORCE_MODE" = true ]; then
        echo "  ✓ Old kernels removed" >> "$SUMMARY_REPORT"
        echo "  ✓ PackageKit cache cleaned" >> "$SUMMARY_REPORT"
        echo "  ✓ Thumbnail cache cleaned" >> "$SUMMARY_REPORT"
        echo "  ✓ Core dumps removed" >> "$SUMMARY_REPORT"
        echo "  ✓ Old audit logs cleaned" >> "$SUMMARY_REPORT"
    fi
    
    if command -v docker &> /dev/null; then
        echo "  ✓ Docker logs truncated" >> "$SUMMARY_REPORT"
    fi
    
    # Add final status
    cat >> "$SUMMARY_REPORT" << EOF

FINAL STATUS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

    if [ "$final_usage" -ge "$CRITICAL_THRESHOLD" ]; then
        cat >> "$SUMMARY_REPORT" << EOF
Status:              ⚠️  CRITICAL - Manual intervention needed
Final Usage:         ${final_usage}% (Still above ${CRITICAL_THRESHOLD}%)
Recommendation:      Check for large files, consider disk expansion

Actions to take:
  1. Find largest files: du -sh /var/* | sort -rh | head -20
  2. Check Docker usage: docker system df
  3. Check database logs: du -sh /var/log/mysql /var/log/mariadb
  4. Check audit logs: du -sh /var/log/audit
  5. Consider expanding disk space
EOF
    elif [ "$final_usage" -ge "$THRESHOLD" ]; then
        cat >> "$SUMMARY_REPORT" << EOF
Status:              ⚠️  WARNING - Still above threshold
Final Usage:         ${final_usage}% (Above ${THRESHOLD}%)
Recommendation:      Monitor closely, consider more aggressive cleanup
EOF
    else
        cat >> "$SUMMARY_REPORT" << EOF
Status:              ✅ SUCCESS
Final Usage:         ${final_usage}% (Below ${THRESHOLD}%)
Recommendation:      System is healthy, continue regular maintenance
EOF
    fi
    
    # Add footer
    cat >> "$SUMMARY_REPORT" << EOF

REPORT LOCATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
This report:         $SUMMARY_REPORT
Detailed log:        $SCRIPT_LOG

╔══════════════════════════════════════════════════════════════════════╗
║                         End of Report                                ║
╚══════════════════════════════════════════════════════════════════════╝
EOF
    
    log_color "$GREEN" "Summary report created: $SUMMARY_REPORT"
    echo ""
    echo "📊 Summary report: $SUMMARY_REPORT"
}

# Main function
main() {
    log_message "=========================================="
    log_message "Fedora/CentOS/RHEL Log Cleanup Started"
    log_message "=========================================="
    
    # Root check
    if [ "$EUID" -ne 0 ]; then 
        log_color "$YELLOW" "WARNING: Running without root privileges"
        log_message "Some operations may fail"
    fi
    
    # Get initial disk usage
    initial_usage=$(get_disk_usage /)
    log_message "Initial disk usage: ${initial_usage}%"
    
    # If --force flag was used manually, skip disk usage check
    if [ "$FORCE_FLAG_USED" = true ]; then
        log_color "$YELLOW" "Force mode activated manually - bypassing disk usage check"
        log_message "Running cleanup regardless of disk usage"
        FORCE_MODE=true
    # Check if critical cleanup is needed based on disk usage
    elif [ "$initial_usage" -ge "$CRITICAL_THRESHOLD" ]; then
        log_color "$RED" "!!! CRITICAL: ${initial_usage}% !!!"
        FORCE_MODE=true
        send_notification "CRITICAL: Disk at ${initial_usage}% - Force cleanup initiated"
    elif [ "$initial_usage" -ge "$THRESHOLD" ]; then
        log_color "$RED" "Disk usage ${initial_usage}% exceeds ${THRESHOLD}%"
    else
        log_color "$GREEN" "Disk usage ${initial_usage}% is below ${THRESHOLD}%"
        log_message "No cleanup needed"
        exit 0
    fi
    
    total_files_deleted=0
    total_space_freed=0
    
    # FORCE MODE
    if [ "$FORCE_MODE" = true ]; then
        log_message "--- FORCE MODE: Emergency Cleanup ---"
        
        emergency_cleanup
        
        for dir in "${LOG_DIRS[@]}"; do
            if [ -d "$dir" ] || [[ "$dir" == *"*"* ]]; then
                result=$(force_cleanup "$dir")
                files_deleted=$(echo "$result" | cut -d: -f1)
                space_freed=$(echo "$result" | cut -d: -f2)
                total_files_deleted=$((total_files_deleted + files_deleted))
                total_space_freed=$((total_space_freed + space_freed))
            fi
        done
        
        current_usage=$(get_disk_usage /)
        log_message "Disk usage after force cleanup: ${current_usage}%"
        
    else
        # NORMAL MODE
        if [ "$ENABLE_COMPRESSION" = true ]; then
            log_message "--- Phase 1: Compression ---"
            for dir in "${LOG_DIRS[@]}"; do
                if [ -d "$dir" ]; then
                    compress_logs "$dir"
                fi
            done
            
            current_usage=$(get_disk_usage /)
            log_message "Disk usage after compression: ${current_usage}%"
        fi
        
        current_usage=$(get_disk_usage /)
        if [ "$current_usage" -ge "$THRESHOLD" ]; then
            log_message "--- Phase 2: Deletion ---"
            for dir in "${LOG_DIRS[@]}"; do
                if [ -d "$dir" ] || [[ "$dir" == *"*"* ]]; then
                    result=$(clean_old_logs "$dir")
                    files_deleted=$(echo "$result" | cut -d: -f1)
                    space_freed=$(echo "$result" | cut -d: -f2)
                    total_files_deleted=$((total_files_deleted + files_deleted))
                    total_space_freed=$((total_space_freed + space_freed))
                fi
            done
            
            clean_journal_logs $DAYS_TO_KEEP
            
            # Check if escalation needed
            current_usage=$(get_disk_usage /)
            if [ "$current_usage" -ge "$CRITICAL_THRESHOLD" ]; then
                log_color "$RED" "Escalating to FORCE MODE"
                FORCE_MODE=true
                
                emergency_cleanup
                
                for dir in "${LOG_DIRS[@]}"; do
                    if [ -d "$dir" ] || [[ "$dir" == *"*"* ]]; then
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
    
    # Create detailed summary report
    create_summary_report "$initial_usage" "$final_usage" "$total_files_deleted" "$total_space_freed"
    
    if [ "$final_usage" -ge "$CRITICAL_THRESHOLD" ]; then
        log_color "$RED" "!!! CRITICAL: Still at ${final_usage}% !!!"
        log_message "Manual intervention required!"
        send_notification "CRITICAL: Still at ${final_usage}% after cleanup"
    elif [ "$final_usage" -ge "$THRESHOLD" ]; then
        log_color "$YELLOW" "WARNING: Still at ${final_usage}%"
        send_notification "Cleanup completed but usage still at ${final_usage}%"
    else
        log_color "$GREEN" "SUCCESS: Reduced to ${final_usage}%"
        if [ "$FORCE_MODE" = true ]; then
            send_notification "Force cleanup successful - ${final_usage}%"
        fi
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            log_message "DRY RUN MODE"
            shift
            ;;
        --force)
            FORCE_MODE=true
            FORCE_FLAG_USED=true
            log_message "FORCE MODE enabled (manual override)"
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
            echo "Comprehensive Fedora/CentOS/RHEL log cleanup"
            echo ""
            echo "Options:"
            echo "  --dry-run                Test mode (show what would be deleted)"
            echo "  --force                  Force cleanup mode (ignores disk usage check)"
            echo "  --days N                 Keep N days (default: 7)"
            echo "  --threshold N            Trigger at N% (default: 90)"
            echo "  --critical-threshold N   Auto-force mode at N% (default: 95)"
            echo "  --help                   Show this help"
            echo ""
            echo "Behavior:"
            echo "  - Normal: Runs cleanup only if disk usage >= threshold"
            echo "  - With --force: Runs aggressive cleanup regardless of disk usage"
            echo "  - Auto-force: Activates at critical threshold (95%+)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main

exit 0
