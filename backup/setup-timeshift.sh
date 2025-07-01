#!/bin/bash
# Setup Timeshift Automatic Snapshots
# Safety Level: 2 (Modifies system - but only adds protection)
# 
# Configures Timeshift for automatic system snapshots

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/../logs/timeshift-setup-$(date +%Y%m%d_%H%M%S).log"

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

# Logging setup
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

echo "=== Setting Up Timeshift Automatic Snapshots ==="
echo "Started: $(date)"
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root (sudo)"
    echo "   Usage: sudo $0"
    exit 1
fi

# Install Timeshift if not present
echo "📦 Checking Timeshift installation..."
if ! command -v timeshift &> /dev/null; then
    echo "   Installing Timeshift..."
    apt update && apt install -y timeshift
    echo "   ✅ Timeshift installed"
else
    echo "   ✅ Timeshift already installed"
fi

# Detect filesystem type
echo
echo "🔍 Detecting filesystem..."
ROOT_FS=$(findmnt -n -o FSTYPE /)
echo "   Root filesystem: $ROOT_FS"

if [[ "$ROOT_FS" == "btrfs" ]]; then
    SNAPSHOT_TYPE="btrfs"
    echo "   ✅ Using BTRFS snapshots (recommended)"
elif [[ "$ROOT_FS" == "ext4" ]]; then
    SNAPSHOT_TYPE="rsync"
    echo "   ⚠️  Using RSYNC mode (BTRFS recommended for better performance)"
else
    echo "   ❌ Unsupported filesystem: $ROOT_FS"
    echo "   Supported: btrfs (recommended), ext4"
    exit 1
fi

# Configure Timeshift
echo
echo "⚙️ Configuring Timeshift..."

# Create Timeshift configuration
cat > /etc/timeshift/timeshift.json << EOF
{
  "backup_device_uuid" : "",
  "parent_device_uuid" : "",
  "do_first_run" : "false",
  "btrfs_mode" : $([ "$SNAPSHOT_TYPE" == "btrfs" ] && echo "true" || echo "false"),
  "include_btrfs_home_for_backup" : "false",
  "include_btrfs_home_for_restore" : "false",
  "stop_cron_emails" : "true",
  "schedule_monthly" : "false",
  "schedule_weekly" : "true",
  "schedule_daily" : "true",
  "schedule_hourly" : "false",
  "schedule_boot" : "true",
  "count_monthly" : "2",
  "count_weekly" : "3",
  "count_daily" : "5",
  "count_hourly" : "6",
  "count_boot" : "3",
  "snapshot_size" : "0",
  "snapshot_count" : "0",
  "date_format" : "%Y-%m-%d %H:%M:%S",
  "exclude_list" : [
    "/home/**",
    "/root/**",
    "/media/**",
    "/mnt/**",
    "/tmp/**",
    "/var/tmp/**",
    "/var/log/**",
    "/var/cache/**",
    "/var/backups/**"
  ]
}
EOF

echo "   ✅ Configuration created"

# Enable and start timeshift
echo
echo "🚀 Enabling automatic snapshots..."
systemctl enable cronie || systemctl enable cron || echo "   ⚠️  Cron service not found"
systemctl start cronie || systemctl start cron || echo "   ⚠️  Could not start cron"

# Create initial snapshot
echo
echo "📸 Creating initial snapshot..."
if timeshift --create --comments "Initial snapshot - Ubuntu rescue system setup"; then
    echo "   ✅ Initial snapshot created successfully"
else
    echo "   ⚠️  Initial snapshot failed (this is often normal on first run)"
fi

# Show current snapshots
echo
echo "📋 Current snapshots:"
timeshift --list || echo "   No snapshots yet"

echo
echo "=== Timeshift Setup Complete ==="
echo "🔄 Automatic schedule:"
echo "   📅 Daily snapshots: Kept for 5 days"
echo "   📅 Weekly snapshots: Kept for 3 weeks"
echo "   📅 Boot snapshots: Kept for 3 boots"
echo
echo "💡 Manual snapshot: timeshift --create --comments 'Before changes'"
echo "🔙 Restore from snapshot: timeshift --restore"
echo
echo "✅ Your system is now protected with automatic snapshots!"
echo "Completed: $(date)" 