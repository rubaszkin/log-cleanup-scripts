# Force Cleanup Mode - Documentation

## Overview

The advanced log cleanup script now includes a **FORCE CLEANUP MODE** that activates when disk usage reaches critical levels (95-100%). This mode performs aggressive cleanup operations to quickly free up disk space in emergency situations.

## When Force Mode Activates

Force mode is automatically triggered when:
- Disk usage reaches **95% or higher** (configurable via `CRITICAL_THRESHOLD`)
- Standard cleanup fails to reduce disk usage below 95%

You can also manually activate force mode with:
```bash
sudo ./clean_logs_advanced.sh --force
```

## What Force Mode Does

### 1. **Emergency Cleanup**
- Cleans all package manager caches (APT, YUM, DNF)
- Removes temporary files from `/tmp` and `/var/tmp` older than 1 day
- Aggressive systemd journal cleanup (keeps only 1 day)

### 2. **Aggressive Log Deletion**
- Deletes **ALL rotated logs** regardless of age:
  - `*.log.1`, `*.log.2`, etc.
  - `*.gz` (all compressed logs)
  - `*.old` (old log files)
- Deletes logs older than **3 days** (vs. 7 days in normal mode)

### 3. **Large File Truncation**
- Identifies active log files larger than 100MB
- Truncates them to keep only the last 1000 lines
- Preserves recent log data while freeing significant space

## Configuration

Edit these variables in the script:

```bash
# Normal cleanup threshold
THRESHOLD=90

# Force mode activation threshold  
CRITICAL_THRESHOLD=95

# Normal mode retention
DAYS_TO_KEEP=7

# Force mode retention (more aggressive)
CRITICAL_DAYS_TO_KEEP=3
```

## Usage Examples

### Automatic Force Mode
```bash
# Script automatically enters force mode at 95%+ disk usage
sudo ./clean_logs_advanced.sh
```

### Manual Force Mode
```bash
# Force aggressive cleanup regardless of disk usage
sudo ./clean_logs_advanced.sh --force

# Test force mode without deleting
sudo ./clean_logs_advanced.sh --force --dry-run

# Custom thresholds
sudo ./clean_logs_advanced.sh --threshold 85 --critical-threshold 93
```

### Monitoring Force Mode
```bash
# Watch the cleanup process in real-time
sudo ./clean_logs_advanced.sh --force | tee /tmp/force_cleanup.log

# Check the detailed log afterwards
sudo tail -f /var/log/log_cleanup.log
```

## Force Mode Operations Detail

### Phase 1: Emergency Cleanup
```
✓ Clean APT cache        → apt-get clean
✓ Clean YUM cache        → yum clean all  
✓ Clean DNF cache        → dnf clean all
✓ Remove /tmp files      → find /tmp -type f -atime +1 -delete
✓ Remove /var/tmp files  → find /var/tmp -type f -atime +1 -delete
✓ Journal cleanup        → journalctl --vacuum-time=1d
```

### Phase 2: Aggressive Log Cleanup
```
✓ Delete all *.log.1, *.log.2, *.log.3, etc.
✓ Delete all *.gz compressed files
✓ Delete all *.old backup files
✓ Delete logs older than 3 days
```

### Phase 3: Large File Truncation
```
✓ Find active logs > 100MB
✓ Keep last 1000 lines of each
✓ Example: 500MB log → 50KB log
```

## Safety Features

1. **Dry-run mode** - Test before executing:
   ```bash
   sudo ./clean_logs_advanced.sh --force --dry-run
   ```

2. **Detailed logging** - All actions logged to `/var/log/log_cleanup.log`

3. **Permission checks** - Only deletes files with write access

4. **Email alerts** - Notifies admin when force mode activates (if enabled)

5. **Preserves recent data** - Truncation keeps last 1000 lines

## Expected Space Recovery

| Disk Usage | Action | Expected Recovery |
|------------|--------|-------------------|
| 90-94% | Standard cleanup | 5-15% disk space |
| 95-100% | Force cleanup | 15-40% disk space |

### Example Scenario
```
Initial state:
- Disk usage: 97%
- /var/log size: 8GB

After force cleanup:
- Disk usage: 78%  
- /var/log size: 2GB
- Space freed: 6GB
- Files deleted: ~500 rotated logs
- Files truncated: 3 large active logs
```

## Warning Messages

### Critical Warning
When disk remains at 95%+ after force cleanup:
```
!!! CRITICAL WARNING: Disk usage STILL at 97% !!!
URGENT: Manual intervention required!
Recommendations:
  1. Check for large files: du -sh /var/* | sort -rh | head -20
  2. Check for large directories: ncdu / (if available)
  3. Consider expanding disk space
  4. Review application logs and disable verbose logging
```

## Troubleshooting Force Mode

### Force mode doesn't free enough space

1. **Check what's using space:**
   ```bash
   # Find largest directories
   sudo du -sh /var/* | sort -rh | head -20
   
   # Find largest files
   sudo find /var -type f -size +100M -exec ls -lh {} \; | sort -k5 -rh
   ```

2. **Check application-specific logs:**
   ```bash
   # Docker logs
   sudo du -sh /var/lib/docker/containers/*
   
   # Database logs
   sudo du -sh /var/lib/mysql/*
   sudo du -sh /var/lib/postgresql/*
   ```

3. **Manual cleanup options:**
   ```bash
   # Clean Docker
   docker system prune -a
   
   # Clean old kernels (Ubuntu/Debian)
   sudo apt autoremove --purge
   
   # Clean old kernels (RHEL/CentOS)
   sudo package-cleanup --oldkernels --count=2
   ```

### Force mode not activating

Check current disk usage:
```bash
df -h /
```

Manually trigger force mode:
```bash
sudo ./clean_logs_advanced.sh --force
```

Lower the threshold:
```bash
sudo ./clean_logs_advanced.sh --critical-threshold 92
```

## Best Practices

### 1. Prevention
- Set up monitoring before disk fills
- Use standard mode at 90% to avoid reaching 95%
- Schedule regular cleanups: `0 */6 * * * /usr/local/bin/clean_logs_advanced.sh`

### 2. During Crisis
- Run force mode immediately at 95%+
- Monitor in real-time: `watch df -h /`
- Review large files manually
- Consider stopping services temporarily

### 3. After Recovery
- Investigate root cause
- Adjust log rotation policies
- Consider increasing disk space
- Update cleanup schedule to run more frequently
- Review application logging verbosity

## Automation with Cron

### Automatic escalation
```bash
# Run standard cleanup every 6 hours
0 */6 * * * /usr/local/bin/clean_logs_advanced.sh >> /var/log/log_cleanup_cron.log 2>&1

# The script will automatically escalate to force mode if needed
```

### Separate force mode schedule
```bash
# Run standard cleanup every 6 hours
0 */6 * * * /usr/local/bin/clean_logs_advanced.sh >> /var/log/log_cleanup_cron.log 2>&1

# Run force cleanup daily at 3 AM if disk is very full
0 3 * * * [ $(df / | awk 'NR==2 {print $5}' | sed 's/%//') -ge 95 ] && /usr/local/bin/clean_logs_advanced.sh --force >> /var/log/force_cleanup_cron.log 2>&1
```

## Email Notifications

Enable email alerts for force mode:
```bash
# Edit script configuration
EMAIL_NOTIFY=true
EMAIL_ADDRESS="admin@example.com"
```

You'll receive emails when:
- Force mode activates automatically
- Disk remains critical after cleanup
- Force cleanup completes successfully

## Recovery Examples

### Example 1: Web Server
```
Before: 98% disk usage, 10GB /var/log
Actions:
  - Deleted 800 rotated nginx logs
  - Truncated 3 large access logs (2GB → 100KB each)
  - Cleaned APT cache (500MB)
After: 72% disk usage, 1.5GB /var/log
Result: SUCCESS - 26% space recovered
```

### Example 2: Database Server  
```
Before: 96% disk usage, 15GB /var/log
Actions:
  - Deleted 1200 rotated PostgreSQL logs
  - Truncated pg_log (5GB → 2MB)
  - Cleaned journal logs (3GB → 100MB)
After: 68% disk usage, 2GB /var/log  
Result: SUCCESS - 28% space recovered
```

### Example 3: Application Server
```
Before: 99% disk usage, 20GB /var/log
Actions:
  - Force cleanup freed 12GB
  - Still at 94% - escalated to manual intervention
  - Found: 30GB in /var/lib/docker/containers
Manual: docker system prune -a
After: 65% disk usage
Result: SUCCESS with additional manual steps
```

## See Also

- [README.md](README.md) - Main documentation
- [clean_logs_advanced.sh](clean_logs_advanced.sh) - The script itself
- System monitoring: `df`, `du`, `ncdu`
- Log rotation: `/etc/logrotate.d/`
