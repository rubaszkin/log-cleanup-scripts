# Log Cleanup Scripts

**Comprehensive automated log cleanup solution for Linux systems with Force Mode, disk usage monitoring, and detailed reporting.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Bash-4.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://www.linux.org/)

---

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Scripts Available](#scripts-available)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Usage](#usage)
- [Force Mode](#force-mode)
- [Summary Reports](#summary-reports)
- [Automation](#automation)
- [Documentation](#documentation)
- [System Compatibility](#system-compatibility)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## 🎯 Overview

Professional-grade log cleanup scripts designed to automatically manage disk space by cleaning, compressing, and organizing log files across Linux systems. Features intelligent disk usage monitoring, automatic force mode activation during critical situations, and comprehensive reporting.

**Perfect for:**
- Production servers
- Web hosting environments
- Database servers
- Container hosts (Docker, Kubernetes)
- Development environments
- CI/CD systems

---

## ✨ Features

### Core Features
- ✅ **Intelligent Disk Monitoring** - Automatic cleanup when disk usage exceeds threshold (90%)
- ✅ **Force Mode** - Aggressive cleanup for critical situations (95%+ or manual)
- ✅ **Dry-Run Mode** - Test cleanup operations without deleting files
- ✅ **Compression** - Automatic log compression to save space
- ✅ **Summary Reports** - Detailed reports with space freed and system status
- ✅ **Email Notifications** - Alert administrators of critical situations
- ✅ **Configurable Retention** - Customize log retention periods
- ✅ **Safe Operations** - Age-based deletion with permission checks

### Advanced Features
- 🔥 **Emergency Cleanup** - Automatic escalation when needed
- 📊 **Detailed Metrics** - Track space freed (KB/MB/GB)
- 🎯 **Multi-Directory Support** - Clean 40+ log locations
- 🚀 **Distribution-Specific** - Optimized for Debian, RHEL, and generic Linux
- 💾 **Package Cache Cleanup** - Clear APT, YUM, DNF caches
- 🐳 **Docker Support** - Truncate container logs
- 🔄 **Kernel Management** - Remove old kernels
- 📝 **Journal Management** - Systemd journal cleanup

---

## 📦 Scripts Available

### 1. **clean_logs_advanced.sh** (Universal)
General-purpose cleanup for any Linux distribution.
- **Best for:** Workstations, simple servers, multi-distro environments
- **Directories:** `/var/log` + systemd journal
- **Recovery:** 500MB - 2GB

### 2. **clean_logs_debian.sh** (Debian/Ubuntu)
Comprehensive cleanup for Debian-based systems.
- **Best for:** Production Debian/Ubuntu servers
- **Directories:** 42+ locations (Apache, MySQL, PostgreSQL, Docker)
- **Features:** APT cache, old kernels, Docker logs, core dumps
- **Recovery:** 2GB - 20GB+

### 3. **clean_logs_rhel.sh** (Fedora/CentOS/RHEL)
Optimized cleanup for Red Hat-based systems.
- **Best for:** Production RHEL/CentOS/Fedora servers
- **Directories:** 45+ locations (httpd, mariadb, audit logs)
- **Features:** YUM/DNF cache, old kernels, audit logs, SELinux
- **Recovery:** 2GB - 20GB+

---

## 🚀 Quick Start

```bash
# 1. Download script (choose your distribution)
wget https://raw.githubusercontent.com/yourusername/log-cleanup-scripts/main/clean_logs_advanced.sh

# 2. Make executable
chmod +x clean_logs_advanced.sh

# 3. Test first (dry-run)
sudo ./clean_logs_advanced.sh --dry-run

# 4. Run actual cleanup
sudo ./clean_logs_advanced.sh

# 5. View summary
cat /var/log/log_cleanup_summary.txt
```

**Expected Output:**
```
Files Deleted:       247
Space Freed (GB):    8 GB
Initial Usage:       92%
Final Usage:         75%
Status:              ✅ SUCCESS
```

---

## 📥 Installation

### Quick Install

```bash
# Universal script (any Linux)
sudo wget -O /usr/local/bin/clean_logs \
  https://raw.githubusercontent.com/yourusername/log-cleanup-scripts/main/clean_logs_advanced.sh
sudo chmod +x /usr/local/bin/clean_logs

# Debian/Ubuntu
sudo wget -O /usr/local/bin/clean_logs \
  https://raw.githubusercontent.com/yourusername/log-cleanup-scripts/main/clean_logs_debian.sh
sudo chmod +x /usr/local/bin/clean_logs

# Fedora/CentOS/RHEL
sudo wget -O /usr/local/bin/clean_logs \
  https://raw.githubusercontent.com/yourusername/log-cleanup-scripts/main/clean_logs_rhel.sh
sudo chmod +x /usr/local/bin/clean_logs
```

### Git Clone

```bash
git clone https://github.com/yourusername/log-cleanup-scripts.git
cd log-cleanup-scripts
chmod +x *.sh
sudo cp clean_logs_*.sh /usr/local/bin/
```

---

## 🔧 Usage

### Basic Commands

```bash
# Standard cleanup (runs if disk >= 90%)
sudo clean_logs

# Test mode (see what would be deleted)
sudo clean_logs --dry-run

# Force cleanup (bypass disk check)
sudo clean_logs --force

# Custom retention
sudo clean_logs --days 14

# Help
sudo clean_logs --help
```

### Command Options

| Option | Description | Default |
|--------|-------------|---------|
| `--dry-run` | Test mode (no deletion) | Off |
| `--force` | Aggressive cleanup regardless of disk usage | Off |
| `--days N` | Keep logs newer than N days | 7 |
| `--threshold N` | Trigger cleanup at N% disk usage | 90 |
| `--critical-threshold N` | Auto-force mode at N% | 95 |
| `--help` | Show help message | - |

---

## 🔥 Force Mode

### What is Force Mode?

Aggressive cleanup that activates when:
- Disk usage reaches 95%+ (automatic)
- User specifies `--force` flag (manual)

### Standard vs Force Mode

**Standard Mode (90-94% disk):**
- Compresses logs >1 day old
- Deletes logs >7 days old
- Cleans systemd journal

**Force Mode (95%+ or --force):**
- ✅ Deletes ALL rotated logs immediately
- ✅ Keeps only 3 days of logs
- ✅ Truncates large files (>100MB)
- ✅ Cleans package caches (APT/YUM/DNF)
- ✅ Removes old kernels
- ✅ Cleans Docker logs
- ✅ Removes core dumps
- ✅ Aggressive journal cleanup (1 day)

### Using Force Mode

```bash
# Manual force (any disk usage level)
sudo clean_logs --force

# Test force mode
sudo clean_logs --force --dry-run

# Preventive maintenance at 75% disk
sudo clean_logs --force  # Runs immediately
```

### Force Mode Use Cases

1. **Preventive Maintenance** - Clean before disk fills
2. **Before Operations** - Free space before imports/deployments
3. **Scheduled Cleaning** - Monthly comprehensive cleanup
4. **Emergency Recovery** - Immediate space recovery

---

## 📊 Summary Reports

Every cleanup generates a detailed report at `/var/log/log_cleanup_summary.txt`

### Sample Report

```
╔══════════════════════════════════════════════════════════════════╗
║              LOG CLEANUP SUMMARY REPORT                          ║
╚══════════════════════════════════════════════════════════════════╝

EXECUTION DETAILS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Timestamp:           2025-12-10 14:35:22
Hostname:            webserver01
Cleanup Mode:        FORCE CLEANUP (Auto-activated)

DISK USAGE STATISTICS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total Disk Size:     500G
Used Before:         480G (96%)
Used After:          350G (70%)
Usage Reduction:     26%

CLEANUP RESULTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Files Deleted:       1,247
Space Freed (GB):    130 GB

FINAL STATUS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Status:              ✅ SUCCESS
Final Usage:         70%
Recommendation:      System is healthy
```

### Using Reports

```bash
# View report
cat /var/log/log_cleanup_summary.txt

# Extract stats
grep "Space Freed" /var/log/log_cleanup_summary.txt
grep "Status:" /var/log/log_cleanup_summary.txt

# Email report
mail -s "Cleanup Report" admin@example.com < /var/log/log_cleanup_summary.txt
```

---

## ⏰ Automation

### Cron Setup

```bash
# Edit crontab
sudo crontab -e

# Every 6 hours
0 */6 * * * /usr/local/bin/clean_logs >> /var/log/cleanup_cron.log 2>&1

# Daily at 2 AM
0 2 * * * /usr/local/bin/clean_logs >> /var/log/cleanup_cron.log 2>&1

# Weekly force cleanup (Sunday 3 AM)
0 3 * * 0 /usr/local/bin/clean_logs --force >> /var/log/cleanup_cron.log 2>&1

# Monthly deep clean (1st day, 4 AM)
0 4 1 * * /usr/local/bin/clean_logs --force --days 3 >> /var/log/cleanup_cron.log 2>&1
```

### Systemd Timer

Create `/etc/systemd/system/log-cleanup.timer`:

```ini
[Unit]
Description=Run log cleanup every 6 hours

[Timer]
OnCalendar=00/6:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable:
```bash
sudo systemctl enable log-cleanup.timer
sudo systemctl start log-cleanup.timer
```

---

## 📚 Documentation

Complete documentation included:

| File | Description |
|------|-------------|
| `README.md` | Main documentation (this file) |
| `FORCE_MODE.md` | Detailed Force Mode guide |
| `FORCE_FLAG_GUIDE.txt` | Using --force flag |
| `SUMMARY_REPORT_GUIDE.txt` | Report usage and examples |
| `DEBIAN_LOG_LOCATIONS.txt` | All Debian log locations |
| `RHEL_CLEANUP_GUIDE.txt` | RHEL-specific guide |
| `SCRIPT_COMPARISON.txt` | Compare all scripts |
| `GITHUB_SETUP.md` | Git/GitHub guide |
| `TOKEN_GUIDE.txt` | GitHub token setup |
| `QUICK_REFERENCE.txt` | Emergency commands |
| `FLOWCHART.txt` | Logic flow diagram |

---

## 💻 System Compatibility

### Supported Systems

| Distribution | Script | Versions |
|--------------|--------|----------|
| Debian | `clean_logs_debian.sh` | 10, 11, 12 |
| Ubuntu | `clean_logs_debian.sh` | 20.04, 22.04, 24.04 |
| Linux Mint | `clean_logs_debian.sh` | 20, 21 |
| Fedora | `clean_logs_rhel.sh` | 37, 38, 39 |
| CentOS | `clean_logs_rhel.sh` | 7, 8, Stream |
| RHEL | `clean_logs_rhel.sh` | 7, 8, 9 |
| Rocky Linux | `clean_logs_rhel.sh` | 8, 9 |
| AlmaLinux | `clean_logs_rhel.sh` | 8, 9 |
| Other | `clean_logs_advanced.sh` | Most Linux |

### Requirements

- Bash 4.0+
- Root/sudo access
- Standard GNU utilities (df, du, find, gzip)

---

## 💡 Examples

### Example 1: Emergency Recovery

```bash
# Server at 98% disk - immediate action needed
sudo clean_logs --force

# Result:
# Space Freed: 25GB
# Final Usage: 72%
```

### Example 2: Production Setup

```bash
# Install
sudo wget -O /usr/local/bin/clean_logs \
  https://raw.githubusercontent.com/yourusername/log-cleanup-scripts/main/clean_logs_debian.sh
sudo chmod +x /usr/local/bin/clean_logs

# Automate
echo "0 */6 * * * /usr/local/bin/clean_logs" | sudo crontab -

# Test
sudo clean_logs --dry-run
```

### Example 3: Weekly Report

```bash
#!/bin/bash
# Send weekly cleanup report

/usr/local/bin/clean_logs --force

SPACE=$(grep "Space Freed (GB)" /var/log/log_cleanup_summary.txt | awk '{print $4}')

mail -s "Weekly Cleanup: ${SPACE}GB freed" \
  admin@example.com < /var/log/log_cleanup_summary.txt
```

---

## 🔍 Troubleshooting

### Not Freeing Enough Space?

```bash
# Check what's using space
sudo du -sh /var/log/* | sort -rh | head -20

# Use force mode
sudo clean_logs --force

# More aggressive retention
sudo clean_logs --force --days 2
```

### Docker Logs Still Large?

```bash
# Check Docker usage
docker system df

# Run force mode (includes Docker cleanup)
sudo clean_logs --force

# Manual Docker cleanup
docker system prune -a
```

### Script Says "No cleanup needed"?

```bash
# Force it to run anyway
sudo clean_logs --force

# Lower threshold
sudo clean_logs --threshold 80
```

---

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Open Pull Request

---

## 📝 License

MIT License - see [LICENSE](LICENSE) file

---

## 📞 Support

- **Issues:** [GitHub Issues](https://github.com/yourusername/log-cleanup-scripts/issues)
- **Discussions:** [GitHub Discussions](https://github.com/yourusername/log-cleanup-scripts/discussions)

---

## 📊 Project Stats

- **Scripts:** 3
- **Documentation Files:** 14
- **Lines of Code:** ~3,500
- **Supported Distributions:** 10+
- **Log Locations:** 45+
- **Typical Recovery:** 2GB - 20GB

---

## 🌟 Quick Links

- [Installation](#installation)
- [Force Mode](#force-mode)
- [Automation](#automation)
- [Troubleshooting](#troubleshooting)

---

**Made with ❤️ for the Linux community**

*Keep your servers clean, fast, and efficient!*
