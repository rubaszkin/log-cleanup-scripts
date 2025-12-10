# Log Cleanup Scripts

Two bash scripts for cleaning old logs when disk usage exceeds a threshold.

## Scripts

### 1. clean_logs.sh (Basic Version)
Simple script with core functionality:
- Monitors disk usage
- Compresses old logs
- Deletes logs older than specified days
- Supports dry-run mode

### 2. clean_logs_advanced.sh (Advanced Version)
Enhanced version with additional features:
- Multiple directory support
- Color-coded console output
- Detailed logging to file
- Email notifications (optional)
- Systemd journal cleanup
- Command-line arguments
- **🆕 FORCE MODE** - Aggressive cleanup for critical disk usage (95-100%)
  - Auto-activates at 95%+ disk usage
  - Deletes ALL rotated logs regardless of age
  - Truncates large active log files (>100MB) to last 1000 lines
  - Cleans package manager caches (APT/YUM/DNF)
  - Emergency cleanup of temp files
  - More aggressive retention (3 days vs 7 days)

## Installation

1. Copy the script to a suitable location:
```bash
sudo cp clean_logs.sh /usr/local/bin/
# or
sudo cp clean_logs_advanced.sh /usr/local/bin/
```

2. Make it executable:
```bash
sudo chmod +x /usr/local/bin/clean_logs.sh
```

## Usage

### Basic Script
```bash
# Run with default settings
sudo ./clean_logs.sh

# Edit the script to configure:
# - THRESHOLD: disk usage percentage (default: 90)
# - DAYS_TO_KEEP: age of logs to delete (default: 7)
# - DRY_RUN: set to true to test without deleting
```

### Advanced Script
```bash
# Run with default settings
sudo ./clean_logs_advanced.sh

# Dry run (see what would be deleted)
sudo ./clean_logs_advanced.sh --dry-run

# Keep logs for 14 days instead of 7
sudo ./clean_logs_advanced.sh --days 14

# Set threshold to 80%
sudo ./clean_logs_advanced.sh --threshold 80

# Manually trigger force mode (aggressive cleanup)
sudo ./clean_logs_advanced.sh --force

# Test force mode without actually deleting
sudo ./clean_logs_advanced.sh --force --dry-run

# Set custom critical threshold for force mode
sudo ./clean_logs_advanced.sh --critical-threshold 93

# Combine options
sudo ./clean_logs_advanced.sh --dry-run --days 14 --threshold 85

# Show help
./clean_logs_advanced.sh --help
```

## Force Cleanup Mode (95-100% Disk Usage)

When disk usage reaches **95% or higher**, the script automatically activates **FORCE MODE** for aggressive cleanup:

**What it does:**
- Deletes ALL rotated/compressed logs (*.gz, *.log.1, *.log.2, etc.)
- Keeps only 3 days of logs (instead of 7)
- Truncates large active logs (>100MB) to last 1000 lines
- Cleans package manager caches
- Removes old temp files
- Aggressive journal cleanup (1 day retention)

**Manual activation:**
```bash
# Force aggressive cleanup regardless of disk usage
sudo ./clean_logs_advanced.sh --force

# Test what force mode would do
sudo ./clean_logs_advanced.sh --force --dry-run
```

**📖 See [FORCE_MODE.md](FORCE_MODE.md) for detailed documentation**

## Configuration

### Basic Script
Edit these variables at the top of the script:
```bash
LOG_DIR="/var/log"          # Directory containing logs
THRESHOLD=90                 # Disk usage percentage trigger
DAYS_TO_KEEP=7              # Delete logs older than this
DRY_RUN=false               # Set to true for testing
```

### Advanced Script
```bash
LOG_DIRS=("/var/log")       # Array of directories
THRESHOLD=90                 # Disk usage percentage trigger
CRITICAL_THRESHOLD=95        # Force mode activation threshold
DAYS_TO_KEEP=7              # Delete logs older than this
CRITICAL_DAYS_TO_KEEP=3     # Force mode retention (more aggressive)
DRY_RUN=false               # Set to true for testing
ENABLE_COMPRESSION=true      # Compress before deleting
SCRIPT_LOG="/var/log/log_cleanup.log"  # Script's own log file
EMAIL_NOTIFY=false          # Enable email alerts
EMAIL_ADDRESS="admin@example.com"  # Email recipient
```

## Automation with Cron

### Option 1: Run hourly
```bash
# Edit root's crontab
sudo crontab -e

# Add this line to run every hour
0 * * * * /usr/local/bin/clean_logs.sh >> /var/log/log_cleanup_cron.log 2>&1
```

### Option 2: Run daily
```bash
# Run at 2 AM every day
0 2 * * * /usr/local/bin/clean_logs_advanced.sh >> /var/log/log_cleanup_cron.log 2>&1
```

### Option 3: Run every 6 hours
```bash
# Run at midnight, 6 AM, noon, and 6 PM
0 */6 * * * /usr/local/bin/clean_logs.sh >> /var/log/log_cleanup_cron.log 2>&1
```

### Option 4: Create systemd service and timer

Create service file `/etc/systemd/system/log-cleanup.service`:
```ini
[Unit]
Description=Log Cleanup Service
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/clean_logs_advanced.sh
StandardOutput=journal
StandardError=journal
```

Create timer file `/etc/systemd/system/log-cleanup.timer`:
```ini
[Unit]
Description=Run log cleanup hourly
Requires=log-cleanup.service

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable log-cleanup.timer
sudo systemctl start log-cleanup.timer

# Check status
sudo systemctl status log-cleanup.timer
sudo systemctl list-timers
```

## Testing

Always test with dry-run first:

```bash
# Basic script - edit DRY_RUN=true in the script
sudo ./clean_logs.sh

# Advanced script - use command line flag
sudo ./clean_logs_advanced.sh --dry-run
```

## What Gets Cleaned

The script targets these file patterns in /var/log:
- `*.log` - Standard log files
- `*.log.*` - Rotated logs (e.g., `syslog.1`, `syslog.2`)
- `*.gz` - Compressed logs
- `*.old` - Old log files (advanced script only)

## Safety Features

1. **Dry-run mode**: Test before actual deletion
2. **Age-based deletion**: Only removes files older than DAYS_TO_KEEP
3. **Permission checks**: Verifies write access before deletion
4. **Detailed logging**: Records all actions
5. **Compression first**: Tries to free space by compression before deletion
6. **Root warning**: Alerts if not running with sufficient privileges

## Troubleshooting

### Script doesn't delete anything
- Check if running as root: `sudo ./clean_logs.sh`
- Verify disk usage is above threshold
- Check file ages with: `find /var/log -type f -name "*.log" -mtime +7`

### Permission denied errors
- Run with sudo: `sudo ./clean_logs.sh`
- Check file ownership: `ls -la /var/log/`

### Disk still full after running
- Reduce DAYS_TO_KEEP to more aggressive cleanup
- Add more directories to LOG_DIRS (advanced script)
- Check for other large files: `du -sh /var/log/*`
- Consider cleaning systemd journal: `journalctl --vacuum-time=7d`

## Monitoring

View the script's log file:
```bash
# Basic script output
tail -f /var/log/log_cleanup_cron.log

# Advanced script's detailed log
tail -f /var/log/log_cleanup.log
```

Check disk usage:
```bash
df -h /
du -sh /var/log
```

## Best Practices

1. **Start conservatively**: Use higher DAYS_TO_KEEP value initially
2. **Test first**: Always use --dry-run before production use
3. **Monitor logs**: Check script output regularly
4. **Regular schedule**: Run at least daily on busy systems
5. **Alert thresholds**: Set EMAIL_NOTIFY=true for critical systems
6. **Backup important logs**: Before aggressive cleanup, archive important logs

## Examples

```bash
# Quick test - see what would be deleted
sudo ./clean_logs_advanced.sh --dry-run

# Aggressive cleanup - keep only 3 days
sudo ./clean_logs_advanced.sh --days 3

# Lower threshold for systems with less space
sudo ./clean_logs_advanced.sh --threshold 80

# Check current disk usage
df -h / | grep -v Filesystem
```
