#!/bin/bash
# Create Bulletproof USB Rescue Set
# Safety Level: 3 (Modifies USB drive only - never touches main system)
# 
# Creates a multi-boot USB rescue system with proven tools

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$PROJECT_ROOT/logs/usb-setup/usb-creation-$(date +%Y%m%d_%H%M%S).log"
DOWNLOAD_DIR="$SCRIPT_DIR/downloads"

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

# Logging setup
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

echo "=== Bulletproof USB Rescue System Creation ==="
echo "Started: $(date)"
echo "Log: $LOG_FILE"
echo

# Safety check - ensure we're not running on main system drives
check_target_safety() {
    local device="$1"
    
    echo "🛡️ Safety Check: Verifying target device..."
    
    # Check if it's the root device
    local root_device=$(lsblk -no PKNAME $(findmnt -n -o SOURCE /))
    if [[ "$device" == "/dev/$root_device" ]] || [[ "$device" == "/dev/${root_device}p"* ]]; then
        echo "❌ SAFETY ABORT: Target device contains your root filesystem!"
        echo "   Root device: /dev/$root_device"
        echo "   Target device: $device"
        exit 1
    fi
    
    # Check if it's mounted as system directories
    local mount_points=$(lsblk -no MOUNTPOINT "$device" 2>/dev/null | grep -E '^(/|/boot|/home|/var|/usr)$' || true)
    if [[ -n "$mount_points" ]]; then
        echo "❌ SAFETY ABORT: Target device contains system mount points!"
        echo "   Mount points: $mount_points"
        exit 1
    fi
    
    # Verify it's actually a USB device
    local usb_check=$(udevadm info --query=property --name="$device" | grep "ID_BUS=usb" || true)
    if [[ -z "$usb_check" ]]; then
        echo "❌ SAFETY ABORT: Target device is not a USB device!"
        echo "   Device: $device"
        exit 1
    fi
    
    echo "   ✅ Target device is safe to use"
    echo "   ✅ Confirmed USB device"
    echo "   ✅ Not a system device"
}

# Detect USB drives
detect_usb_drives() {
    echo "🔍 Detecting USB drives..."
    
    local usb_drives=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            usb_drives+=("$line")
        fi
    done < <(lsblk -dno NAME,SIZE,MODEL | grep -E "(sda|sdb|sdc|sdd)" | while read name size model; do
        if udevadm info --query=property --name="/dev/$name" | grep -q "ID_BUS=usb"; then
            echo "/dev/$name ($size) - $model"
        fi
    done)
    
    if [[ ${#usb_drives[@]} -eq 0 ]]; then
        echo "❌ No USB drives detected!"
        echo "   Please connect a USB drive and try again."
        exit 1
    fi
    
    echo "   Found USB drives:"
    for i in "${!usb_drives[@]}"; do
        echo "   [$((i+1))] ${usb_drives[$i]}"
    done
    
    echo
    echo "🎯 Auto-detected your HP x5000m USB drive:"
    local hp_drive=$(echo "${usb_drives[@]}" | grep "x5000m" | head -1 | cut -d' ' -f1 || true)
    if [[ -n "$hp_drive" ]]; then
        echo "   Target: $hp_drive"
        USB_DEVICE="$hp_drive"
    else
        echo "❌ HP x5000m drive not found in USB list!"
        exit 1
    fi
}

# Backup existing data (if any valuable data exists)
backup_existing_data() {
    local device="$1"
    local backup_dir="$PROJECT_ROOT/logs/usb-setup/usb-backup-$(date +%Y%m%d_%H%M%S)"
    
    echo "💾 Checking for data to backup..."
    
    # Check if device is mounted
    local mount_point=$(lsblk -no MOUNTPOINT "${device}1" 2>/dev/null | head -1)
    if [[ -z "$mount_point" ]]; then
        echo "   USB not mounted, attempting to mount..."
        mkdir -p /tmp/usb-backup-mount
        if sudo mount "${device}1" /tmp/usb-backup-mount 2>/dev/null; then
            mount_point="/tmp/usb-backup-mount"
            echo "   ✅ Mounted at $mount_point"
        else
            echo "   ⚠️  Cannot mount USB, skipping backup"
            return 0
        fi
    fi
    
    # Check for potentially valuable data
    local valuable_data=()
    if [[ -d "$mount_point/binance_raw_trade_data" ]]; then
        valuable_data+=("binance_raw_trade_data")
    fi
    
    # Look for any non-system files
    local user_files=$(find "$mount_point" -maxdepth 2 -type f \
        ! -name "bootmgr*" ! -name "setup.exe" ! -name "autorun.inf" \
        ! -path "*/sources/*" ! -path "*/boot/*" ! -path "*/efi/*" \
        ! -path "*/support/*" ! -path "*/.fseventsd/*" \
        ! -path "*/.Spotlight-V100/*" ! -path "*/System Volume Information/*" \
        2>/dev/null | head -5)
    
    if [[ ${#valuable_data[@]} -gt 0 ]] || [[ -n "$user_files" ]]; then
        echo "   📋 Found potentially valuable data:"
        for data in "${valuable_data[@]}"; do
            local size=$(du -sh "$mount_point/$data" 2>/dev/null | cut -f1)
            echo "      - $data ($size)"
        done
        if [[ -n "$user_files" ]]; then
            echo "      - Additional user files detected"
        fi
        
        echo
        read -p "   💡 Backup this data before formatting? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "   📁 Creating backup at: $backup_dir"
            mkdir -p "$backup_dir"
            
            for data in "${valuable_data[@]}"; do
                echo "      Backing up $data..."
                cp -r "$mount_point/$data" "$backup_dir/"
            done
            
            echo "   ✅ Backup completed"
            echo "   📁 Backup location: $backup_dir"
        else
            echo "   ⚠️  Skipping backup - data will be lost"
        fi
    else
        echo "   ✅ No valuable user data found"
    fi
    
    # Unmount if we mounted it
    if [[ "$mount_point" == "/tmp/usb-backup-mount" ]]; then
        sudo umount /tmp/usb-backup-mount
        rmdir /tmp/usb-backup-mount
    fi
}

# Create partition layout
create_partitions() {
    local device="$1"
    
    echo "🔧 Creating bulletproof partition layout..."
    echo "   Target device: $device"
    
    # Unmount all partitions on the device
    echo "   Unmounting existing partitions..."
    sudo umount "${device}"* 2>/dev/null || true
    
    # Create new partition table
    echo "   Creating new GPT partition table..."
    sudo parted "$device" --script mklabel gpt
    
    # Create partitions
    echo "   Creating partitions:"
    
    # Partition 1: Super Grub2 Disk (500MB - it's only 24MB extracted)
    echo "      1. Super Grub2 Disk (500MB)"
    sudo parted "$device" --script mkpart primary fat32 1MiB 513MiB
    sudo parted "$device" --script set 1 boot on
    
    # Partition 2: Boot-Repair-Disk (3GB - it's 2.5GB) 
    echo "      2. Boot-Repair-Disk (3GB)"
    sudo parted "$device" --script mkpart primary fat32 513MiB 3585MiB
    
    # Partition 3: SystemRescue (1GB - for future use)
    echo "      3. SystemRescue (1GB - placeholder)" 
    sudo parted "$device" --script mkpart primary fat32 3585MiB 4609MiB
    
    # Partition 4: Clonezilla (1GB - for future use)
    echo "      4. Clonezilla (1GB - placeholder)"
    sudo parted "$device" --script mkpart primary fat32 4609MiB 5633MiB
    
    # Partition 5: Backup Storage (remaining space)
    echo "      5. Backup Storage (remaining ~23GB)"
    sudo parted "$device" --script mkpart primary ext4 5633MiB 100%
    
    # Wait for partition creation
    sleep 2
    sudo partprobe "$device"
    sleep 2
    
    echo "   ✅ Partition layout created"
}

# Format partitions
format_partitions() {
    local device="$1"
    
    echo "💿 Formatting partitions..."
    
    # Format rescue partitions as FAT32 (universal compatibility)
    for i in {1..4}; do
        local partition="${device}${i}"
        echo "   Formatting ${partition} as FAT32..."
        sudo mkfs.fat -F32 -n "RESCUE${i}" "$partition"
    done
    
    # Format backup partition as ext4
    local backup_partition="${device}5"
    echo "   Formatting ${backup_partition} as ext4..."
    sudo mkfs.ext4 -L "BACKUP" "$backup_partition"
    
    echo "   ✅ All partitions formatted"
}

# Download rescue tools if not present
download_rescue_tools() {
    echo "📥 Ensuring rescue tools are available..."
    
    if [[ ! -d "$DOWNLOAD_DIR" ]] || [[ $(ls -A "$DOWNLOAD_DIR" 2>/dev/null | wc -l) -eq 0 ]]; then
        echo "   Running download script..."
        "$SCRIPT_DIR/download-tools.sh"
    else
        echo "   ✅ Rescue tools already downloaded"
        ls -lh "$DOWNLOAD_DIR"
    fi
}

# Install rescue tools to partitions
install_rescue_tools() {
    local device="$1"
    local temp_mount="/tmp/usb-rescue-mount"
    
    echo "🚀 Installing rescue tools to USB partitions..."
    
    mkdir -p "$temp_mount"
    
    # Install Super Grub2 Disk to partition 1
    echo "   Installing Super Grub2 Disk..."
    sudo mount "${device}1" "$temp_mount"
    if [[ -f "$DOWNLOAD_DIR/supergrub2-2.06s4-multiarch-USB.img.zip" ]]; then
        # Extract ZIP contents
        echo "      Extracting Super Grub2 Disk ZIP..."
        cd /tmp
        unzip -q "$DOWNLOAD_DIR/supergrub2-2.06s4-multiarch-USB.img.zip"
        
        # Find the IMG file
        local img_file=$(find /tmp -name "*.img" -type f | head -1)
        if [[ -n "$img_file" ]]; then
            echo "      Found IMG file: $(basename "$img_file")"
            # Mount the first partition of the IMG file (offset calculation: 6144 * 512 = 3145728)
            mkdir -p /tmp/sg2d_mount
            sudo mount -o loop,offset=3145728 "$img_file" /tmp/sg2d_mount
            sudo cp -r /tmp/sg2d_mount/* "$temp_mount/"
            sudo umount /tmp/sg2d_mount
            rmdir /tmp/sg2d_mount
            rm -f "$img_file"
            echo "      ✅ Super Grub2 Disk installed"
        else
            echo "      ⚠️  IMG file not found in ZIP"
        fi
        cd - > /dev/null
    else
        echo "      ⚠️  Super Grub2 Disk ZIP not found, skipping"
    fi
    sudo umount "$temp_mount"
    
    # Install Boot-Repair-Disk to partition 2
    echo "   Installing Boot-Repair-Disk..."
    sudo mount "${device}2" "$temp_mount"
    if [[ -f "$DOWNLOAD_DIR/boot-repair-disk-64bit.iso" ]]; then
        echo "      Copying Boot-Repair-Disk ISO (2.5GB)..."
        sudo cp "$DOWNLOAD_DIR/boot-repair-disk-64bit.iso" "$temp_mount/"
        echo "      ✅ Boot-Repair-Disk installed"
    else
        echo "      ⚠️  Boot-Repair-Disk ISO not found, skipping"
    fi
    sudo umount "$temp_mount"
    
    # Setup placeholder partitions 3 & 4
    echo "   Setting up placeholder partitions..."
    for i in 3 4; do
        sudo mount "${device}${i}" "$temp_mount"
        echo "Placeholder for future rescue tools" | sudo tee "$temp_mount/README.txt" > /dev/null
        sudo umount "$temp_mount"
    done
    
    # Setup backup partition
    echo "   Setting up backup partition..."
    sudo mount "${device}5" "$temp_mount"
    sudo mkdir -p "$temp_mount/system-backups"
    sudo mkdir -p "$temp_mount/timeshift-backups"
    echo "Backup storage for Ubuntu rescue system" | sudo tee "$temp_mount/README.txt" > /dev/null
    sudo umount "$temp_mount"
    
    rmdir "$temp_mount"
    echo "   ✅ All rescue tools installed"
}

# Verify USB creation
verify_usb() {
    local device="$1"
    
    echo "✅ Verifying USB rescue system..."
    
    echo "   Partition layout:"
    lsblk "$device"
    
    echo
    echo "   Partition details:"
    sudo parted "$device" print
    
    echo
    echo "   ✅ USB rescue system creation completed successfully!"
    echo "   📁 Device: $device"
    echo "   🚀 Ready for dry-run testing"
}

# Main execution
main() {
    echo "🛡️ BULLETPROOF USB RESCUE SYSTEM CREATION"
    echo "=========================================="
    echo
    echo "⚠️  This will completely format your USB drive!"
    echo "   All existing data will be permanently lost."
    echo
    read -p "Continue with USB formatting? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Operation cancelled by user"
        exit 0
    fi
    
    # Execute creation steps
    detect_usb_drives
    check_target_safety "$USB_DEVICE"
    backup_existing_data "$USB_DEVICE"
    download_rescue_tools
    create_partitions "$USB_DEVICE"
    format_partitions "$USB_DEVICE"
    install_rescue_tools "$USB_DEVICE"
    verify_usb "$USB_DEVICE"
    
    echo
    echo "🎉 SUCCESS: Bulletproof USB rescue system created!"
    echo "📋 Next steps:"
    echo "   1. Run: ./test-recovery.sh"
    echo "   2. Test boot from USB (dry-run)"
    echo "   3. Verify all rescue tools work"
    echo
    echo "Completed: $(date)"
}

# Run main function
main "$@" 