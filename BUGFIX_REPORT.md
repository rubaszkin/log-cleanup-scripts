# Bug Audit - Debian/Ubuntu Log Cleanup Scripts

Audit date: 2026-08-24
Scripts reviewed: `clean_logs_debian.sh`, `clean_logs_advanced.sh` (and by
inheritance `clean_logs_rhel.sh`, which was derived from the same template)

Tooling: `bash -n`, `shellcheck`, plus live execution in a Debian container
and a sandboxed log tree.

**Headline: none of the three scripts could complete a single run.** Every
code path aborted with an arithmetic syntax error within a second of
starting. Three separate defects contributed; any one of them alone would
have been enough.

---

## Critical

### C1. Functions log to stdout and return their result on stdout

The single worst defect, and the direct cause of every observed crash.

`clean_old_logs()` and `force_cleanup()` return their counters by echoing
`"files:kb"` on stdout, and the caller captures that:

```bash
result=$(force_cleanup "$dir")
files_deleted=$(echo "$result" | cut -d: -f1)
total_files_deleted=$((total_files_deleted + files_deleted))
```

But those same functions also call `log_message` and `log_color`, which
write to stdout. So `$result` is not `"12:4096"` - it is every log line
the function emitted, ANSI colour codes and all, with the counter tacked
on the end. `cut -d: -f1` then splits on the colon in the timestamp.

Two consequences:

1. **Every per-file log line is invisible.** All the "Deleting: ...",
   "[DRY RUN] Would delete: ..." output was swallowed by the command
   substitution and never reached the terminal or the log file.
2. **The script dies.** The garbage fed into `$(( ))` is not a number.

Reproduced verbatim:

```
$ ./clean_logs_debian.sh --force --dry-run
...
./clean_logs_debian.sh: line 381: 0: syntax error: operand expected
    (error token is "!!! FORCE CLEANUP in ...")
```

Same failure at line 411 in normal mode, and at line 442 in
`clean_logs_advanced.sh`. It fires on the first directory processed, so
in practice only `/var/log` was ever touched before the script died.

**Fix:** counters are now globals (`TOTAL_FILES_DELETED`, `TOTAL_KB_FREED`)
updated in place. Nothing is captured from stdout, so logging is free to
go to stdout where it belongs.

---

### C2. `create_summary_report` is defined after `exit 0`

In `clean_logs_debian.sh`:

```
line 526:  main
line 528:  exit 0
line 530:  # Function to create detailed summary report
line 531:  create_summary_report() {
```

Function definitions are executed statements in bash. Since `exit 0` runs
first, the function is never defined. The call at line 456 would fail with
`command not found`, and under `set -e` that also aborts the script.

`shellcheck` flags the entire block from line 540 onward as SC2317
(unreachable code).

Net effect: **the summary report feature never worked at all.** The file
`/var/log/log_cleanup_summary.txt` was never created on any run.

(`clean_logs_advanced.sh` got this right - the function sits at line 262,
before `main`. Only the Debian and RHEL scripts are affected.)

**Fix:** function moved above `main`.

---

### C3. `set -e` is incompatible with the script's own error-handling style

`clean_logs_debian.sh` opens with `set -e`, then uses this pattern roughly
a dozen times:

```bash
gzip "$file" 2>/dev/null
if [ $? -eq 0 ]; then ...
```

A standalone command that fails triggers `set -e` immediately - the `if`
is never reached. `gzip` fails routinely (target `.gz` already exists),
as do `journalctl --vacuum-time` on a non-systemd host and `apt-get` when
dpkg is locked.

Confirmed:

```
$ bash -c 'set -e; gzip /nonexistent 2>/dev/null; if [ $? -eq 0 ]; then echo ok; fi; echo reached'
$ echo $?
1        # "reached" never printed
```

Related: `((n++))` returns exit status 1 when `n` was 0, because the
value of the post-increment expression is the old value. Under `set -e`
that kills the shell:

```
$ bash -c 'set -e; n=0; ((n++)); echo "reached, n=$n"'
$ echo $?
1
```

There are 9 such increments in the Debian script and 8 in the advanced one.

**Fix:** `set -e` removed (a disk-emergency script should push through
best-effort failures, not abort at 98% usage). `set -o pipefail` kept.
All `cmd; if [ $? -eq 0 ]` rewritten as `if cmd; then`. All `((n++))`
rewritten as `n=$((n+1))`.

---

### C4. Blanket `*.1` through `*.9` and `*.gz` patterns delete non-log files

```bash
find "$dir" -type f \( -name "*.gz" -o -name "*.1" -o -name "*.2" ... \)
```

No age filter in force mode. Combined with C5 below this matched, among
other things:

- `libfoo.so.1` and any other versioned shared object
- `important-backup.tar.gz`, `db-dump.tar.gz` - any archive parked in a
  log directory
- in `/tmp` and `/var/tmp`: **every `.gz` file on the system belonging to
  any user**, regardless of age

Verified in a sandbox against v1 patterns: `libcustom.so.1` and
`important-backup.tar.gz` were both deleted.

**Fix:** patterns narrowed to real rotation artefacts (`*.log.[0-9]*`,
`*.log-[0-9]*`, `*[0-9].gz`, `*.old`, `*.[0-9]`), with explicit
exclusions for `*.so.*`, `*.tar.*`, `*.tgz`, and for the script's own log
and summary files. Sandbox re-test: rotated logs including dateext
(`syslog-20250101.gz`) removed, archives and shared libraries untouched.

---

### C5. `/tmp`, `/var/tmp` and the APT cache were in the log-pattern array

`LOG_DIRS` contained `/tmp`, `/var/tmp` and `/var/cache/apt/archives`.
Those were then handed to the same rotated-log matcher as `/var/log`,
which is how C4 escalated from "deletes a versioned .so" to "deletes
users' gzipped files".

**Fix:** removed from the array. `/tmp` and `/var/tmp` are now handled by
a dedicated function that filters on access time (`-atime +7`) and skips
`systemd-*`, `.X11-unix`, `.font-unix` and snap runtime paths. The APT
cache is handled by `apt-get clean`, which is what that command is for.

---

### C6. Old-kernel removal could purge the running kernel

```bash
dpkg -l 'linux-*' | sed '/^ii/!d;/'"$(uname -r | sed "s/\(.*\)-\([^0-9]\+\)/\1/")"'/d;...' \
  | xargs sudo apt-get -y purge 2>/dev/null
```

Three problems:

- If the `uname -r` regex fails to match (it does on Ubuntu HWE kernels
  and on `-cloud`/`-aws` flavours), the exclusion pattern is empty and
  the **currently booted kernel is included in the purge list**. Result:
  an unbootable machine on next reboot.
- `xargs` without `-r` runs `apt-get -y purge` with no arguments when the
  list is empty.
- `sudo` is called from a script that already requires root. On a minimal
  Debian install `sudo` is not present, so the whole thing silently fails.

**Fix:** replaced with `apt-get -y autoremove --purge`, which is the
supported mechanism and never removes the booted kernel.

---

## High

### H1. Truncation replaces the inode, so no space is actually freed

```bash
tail -n 1000 "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
```

`mv` unlinks the original inode and puts a new one in its place. Every
daemon holding the file open - rsyslog, nginx, mysqld, anything not using
`O_APPEND` reopen semantics - keeps writing to the now-unlinked inode.
The disk space is **not released** until the process is restarted, and the
visible log appears frozen. This is the classic "I deleted the logs but
`df` didn't change" failure.

It also silently discards the original ownership, permission bits and any
ACL or SELinux label, replacing them with root-owned defaults derived from
umask.

**Fix:** `tail` to a temp file, then `cat tmp > file`. The redirect
truncates in place and preserves the inode, mode, owner and label. Verified
in the sandbox - inode is identical before and after.

---

### H2. Glob entries in the array never expanded

`"/home/*/logs"` and `"/var/log/ufw.log*"` are quoted strings, so
`[ -d "$dir" ]` is always false. The code then routed them past the
directory check anyway:

```bash
if [ -d "$dir" ] || [[ "$dir" == *"*"* ]]; then
```

so the function was called with a literal glob, hit its own `[ ! -d ]`
guard, and returned nothing - producing an empty `$result` that silently
contributed 0 to the totals. So `/home/*/logs` was reported as processed
and never was.

`/var/log/ufw.log*` is also conceptually wrong - it is a file pattern in a
list of directories, and `/var/log` is already covered recursively.

**Fix:** dedicated `expand_glob_roots()` expands the patterns to real
directories before the loop.

---

### H3. Every subdirectory was processed twice

`find` recurses. Listing `/var/log` and then `/var/log/nginx`,
`/var/log/mysql`, `/var/log/apache2` and 20 others separately meant each
was walked twice. Harmless for correctness but it doubled the runtime on
large log trees, and inflated the "42 locations processed" figure in the
summary into something meaningless.

**Fix:** array reduced to genuine roots that are not already under
`/var/log`.

---

### H4. Summary report showed the wrong disk numbers

```bash
disk_info=$(df -h / | awk 'NR==2 {print $2, $3, $4}')
used_size=$(echo $disk_info | awk '{print $2}')      # Used
available_size=$(echo $disk_info | awk '{print $3}') # Avail
...
Used Before:  $used_size (${initial_usage}%)
Used After:   $available_size (${final_usage}%)
```

`df` runs once, at report time, after cleanup. So "Used Before" is
actually the used figure *after* cleanup, and "Used After" is the
*available* column, not used at all. Both lines were wrong.

**Fix:** `df` sampled before and after, values passed into the report.

---

### H5. `df` output parsed without `-P`

`df / | awk 'NR==2 {print $5}'` breaks whenever the device name is long
enough that `df` wraps it onto its own line - common with LVM, iSCSI and
long `/dev/mapper/` paths. `$5` on the wrapped line is not the percentage.

**Fix:** `df -P`, which guarantees one line per filesystem.

---

## Medium

### M1. No argument validation

`--days` with no value left `$2` empty, producing `find -mtime +` (error).
`--days abc` produced `-mtime +abc`. `shift 2` with only one argument left
raised "shift count out of range".

**Fix:** numeric validation on all three numeric options, and a sanity
check that `--threshold` does not exceed `--critical-threshold`. Exit
code 3 on bad input.

### M2. No locking

The documentation recommends both a daily cron job and a weekly `--force`
job. On Sunday they overlap. Two concurrent runs double-count freed space
and race each other on truncation.

**Fix:** `flock` on `/var/lock/log_cleanup.lock`, exit 3 if already held.

### M3. The script could delete its own log

`/var/log/log_cleanup.log` lives inside `/var/log` and matches the
`*.log` truncation pass, which had no age filter. A large enough
`log_cleanup.log` would be truncated mid-write.

**Fix:** `SCRIPT_LOG` and `SUMMARY_REPORT` explicitly excluded from all
`find` invocations.

### M4. `find /tmp -atime +1 -delete` was too aggressive

One day is short enough to hit active session data. Also worth knowing:
on most modern Debian and Ubuntu installs `/tmp` is a tmpfs, so cleaning
it frees RAM, not disk - it does nothing for the problem the script is
trying to solve.

**Fix:** raised to `-atime +7`, runtime paths excluded, `-maxdepth 3`.

### M5. Docker log pattern too broad

`find /var/lib/docker/containers -name "*.log"` also matches files that
are not container stdout logs. The actual filename is
`<container-id>-json.log`.

**Fix:** pattern narrowed to `*-json.log`. Also gated on
`/var/lib/docker/containers` existing, since the docker CLI can be
installed while pointing at a remote host.

### M6. Always exits 0

`exit 0` unconditionally, even when the disk is still critical after
cleanup. Cron and monitoring cannot distinguish success from "still at
99%".

**Fix:** 0 = success, 1 = still above threshold, 2 = still above critical,
3 = bad arguments or lock held.

### M7. ANSI colour codes emitted when not on a terminal

Cron mail and redirected logs were full of `\033[0;31m`.

**Fix:** colours disabled when stdout is not a TTY.

---

## Summary

| ID | Severity | Effect if unfixed |
|----|----------|-------------------|
| C1 | Critical | Script aborts on first directory; all log output invisible |
| C2 | Critical | Summary report never generated (Debian + RHEL) |
| C3 | Critical | Script aborts on any routine command failure |
| C4 | Critical | Deletes shared libraries and user archives |
| C5 | Critical | Deletes arbitrary `.gz` files from `/tmp` |
| C6 | Critical | Can purge the running kernel; unbootable system |
| H1 | High | Truncation frees no space; loses file ownership/labels |
| H2 | High | `/home/*/logs` never cleaned but reported as cleaned |
| H3 | High | Double traversal; misleading directory counts |
| H4 | High | Summary report shows wrong before/after figures |
| H5 | High | Misparsed disk usage on LVM/long device names |
| M1 | Medium | Silent misbehaviour on malformed arguments |
| M2 | Medium | Overlapping cron runs race |
| M3 | Medium | Script truncates its own log |
| M4 | Medium | `/tmp` cleanup too aggressive, often pointless (tmpfs) |
| M5 | Medium | Docker pattern too broad |
| M6 | Medium | Monitoring cannot detect failure |
| M7 | Medium | Escape codes in cron mail |

`clean_logs_debian.sh` v2.0 fixes all of the above. `shellcheck -S warning`
is clean. All three previously-crashing code paths now run to completion.

---

## Still outstanding

`clean_logs_advanced.sh` and `clean_logs_rhel.sh` carry C1, C3, C4, H1, H2,
H3, H4, H5 and most of the Medium items unchanged, plus C2 in the RHEL
script. They need the same treatment before use.

Two things worth considering beyond the bug fixes:

- On a systemd host, `logrotate` plus `journalctl --vacuum-size=` handles
  most of this natively and is aware of which files daemons hold open. A
  drop-in `/etc/logrotate.d/` config is lower risk than a deletion script
  for the routine case. The script earns its place as an emergency tool.
- Nothing here checks for deleted-but-open files, which is the most common
  reason `df` and `du` disagree during a disk emergency.
  `lsof +L1` or `find /proc/*/fd -ls | grep deleted` would be a useful
  diagnostic to add before the cleanup runs.
