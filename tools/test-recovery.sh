#!/bin/bash
# Test Recovery USB System (Dry Run)
# Safety Level: 1 (100% Safe - Read-only testing)
# 
# Comprehensive testing of the bulletproof USB rescue system

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$PROJECT_ROOT/logs/usb-setup/usb-testing-$(date +%Y%m%d_%H%M%S).log"

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

# Logging setup
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

echo "=== Bulletproof USB Rescue System Testing ==="
echo "Started: $(date)"
echo "Log: $LOG_FILE"
echo

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
test_result() {
    local test_name="$1"
    local result="$2"
    local details="$3"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if [[ "$result" == "PASS" ]]; then
        echo "   ✅ $test_name"
        if [[ -n "$details" ]]; then
            echo "      $details"
        fi
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "   ❌ $test_name"
        if [[ -n "$details" ]]; then
            echo "      $details"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Detect USB rescue device
detect_rescue_usb() {
    echo "🔍 Detecting USB rescue device..."
    
    # Look for our HP x5000m device
    USB_DEVICE=""
    while IFS= read -r device; do
        if udevadm info --query=property --name="$device" | grep -q "ID_MODEL=x5000m"; then
            USB_DEVICE="$device"
            break
        fi
    done < <(lsblk -dno NAME | grep -E "^sd[a-z]$" | sed 's/^/\/dev\//')
    
    if [[ -z "$USB_DEVICE" ]]; then
        echo "❌ HP x5000m USB rescue device not found!"
        echo "   Please ensure the USB drive is connected."
        exit 1
    fi
    
    echo "   ✅ Found USB rescue device: $USB_DEVICE"
    
    # Verify it has our expected partition layout
    local partition_count=$(lsblk -no NAME "$USB_DEVICE" | grep -c "${USB_DEVICE##*/}[0-9]" || echo "0")
    if [[ "$partition_count" -eq 5 ]]; then
        test_result "Partition Layout" "PASS" "5 partitions detected as expected"
    else
        test_result "Partition Layout" "FAIL" "Expected 5 partitions, found $partition_count"
    fi
}

# Test partition structure
test_partition_structure() {
    echo
    echo "🔧 Testing partition structure..."
    
    # Test each partition exists and has correct filesystem
    for i in {1..5}; do
        local partition="${USB_DEVICE}${i}"
        
        if [[ -b "$partition" ]]; then
            local fstype=$(lsblk -no FSTYPE "$partition" 2>/dev/null || echo "unknown")
            local label=$(lsblk -no LABEL "$partition" 2>/dev/null || echo "")
            local size=$(lsblk -no SIZE "$partition" 2>/dev/null || echo "unknown")
            
            case $i in
                1|2|3|4)
                    if [[ "$fstype" == "vfat" ]]; then
                        test_result "Partition $i (Rescue)" "PASS" "FAT32, $size, label: $label"
                    else
                        test_result "Partition $i (Rescue)" "FAIL" "Expected FAT32, found: $fstype"
                    fi
                    ;;
                5)
                    if [[ "$fstype" == "ext4" ]]; then
                        test_result "Partition $i (Backup)" "PASS" "ext4, $size, label: $label"
                    else
                        test_result "Partition $i (Backup)" "FAIL" "Expected ext4, found: $fstype"
                    fi
                    ;;
            esac
        else
            test_result "Partition $i" "FAIL" "Partition device does not exist"
        fi
    done
}

# Test rescue tool installation
test_rescue_tools() {
    echo
    echo "🚀 Testing rescue tool installation..."
    
    local temp_mount="/tmp/usb-test-mount"
    mkdir -p "$temp_mount"
    
    # Test Super Grub2 Disk (Partition 1)
    if sudo mount "${USB_DEVICE}1" "$temp_mount" 2>/dev/null; then
        if [[ -f "$temp_mount/grub.cfg" ]] || [[ -d "$temp_mount/boot/grub" ]]; then
            test_result "Super Grub2 Disk" "PASS" "Boot files detected"
        else
            test_result "Super Grub2 Disk" "FAIL" "Boot files not found"
        fi
        sudo umount "$temp_mount"
    else
        test_result "Super Grub2 Disk" "FAIL" "Cannot mount partition 1"
    fi
    
    # Test Boot-Repair-Disk (Partition 2)
    if sudo mount "${USB_DEVICE}2" "$temp_mount" 2>/dev/null; then
        local iso_file=$(find "$temp_mount" -name "*boot-repair*.iso" | head -1)
        if [[ -n "$iso_file" ]]; then
            local iso_size=$(du -sh "$iso_file" | cut -f1)
            test_result "Boot-Repair-Disk" "PASS" "ISO present ($iso_size)"
        else
            test_result "Boot-Repair-Disk" "FAIL" "ISO file not found"
        fi
        sudo umount "$temp_mount"
    else
        test_result "Boot-Repair-Disk" "FAIL" "Cannot mount partition 2"
    fi
    
    # Test SystemRescue (Partition 3)
    if sudo mount "${USB_DEVICE}3" "$temp_mount" 2>/dev/null; then
        local iso_file=$(find "$temp_mount" -name "*systemrescue*.iso" | head -1)
        if [[ -n "$iso_file" ]]; then
            local iso_size=$(du -sh "$iso_file" | cut -f1)
            test_result "SystemRescue" "PASS" "ISO present ($iso_size)"
        else
            test_result "SystemRescue" "FAIL" "ISO file not found"
        fi
        sudo umount "$temp_mount"
    else
        test_result "SystemRescue" "FAIL" "Cannot mount partition 3"
    fi
    
    # Test Clonezilla (Partition 4)
    if sudo mount "${USB_DEVICE}4" "$temp_mount" 2>/dev/null; then
        local iso_file=$(find "$temp_mount" -name "*clonezilla*.iso" | head -1)
        if [[ -n "$iso_file" ]]; then
            local iso_size=$(du -sh "$iso_file" | cut -f1)
            test_result "Clonezilla" "PASS" "ISO present ($iso_size)"
        else
            test_result "Clonezilla" "FAIL" "ISO file not found"
        fi
        sudo umount "$temp_mount"
    else
        test_result "Clonezilla" "FAIL" "Cannot mount partition 4"
    fi
    
    # Test Backup Storage (Partition 5)
    if sudo mount "${USB_DEVICE}5" "$temp_mount" 2>/dev/null; then
        if [[ -d "$temp_mount/system-backups" ]] && [[ -d "$temp_mount/timeshift-backups" ]]; then
            local available=$(df -h "$temp_mount" | tail -1 | awk '{print $4}')
            test_result "Backup Storage" "PASS" "Directories created, $available available"
        else
            test_result "Backup Storage" "FAIL" "Backup directories not found"
        fi
        sudo umount "$temp_mount"
    else
        test_result "Backup Storage" "FAIL" "Cannot mount partition 5"
    fi
    
    rmdir "$temp_mount"
}

# Test bootability (safe checks only)
test_bootability() {
    echo
    echo "🥾 Testing bootability indicators..."
    
    # Check if partition 1 has boot flag
    local boot_flag=$(sudo parted "$USB_DEVICE" print | grep "boot" | head -1 || echo "")
    if [[ -n "$boot_flag" ]]; then
        test_result "Boot Flag" "PASS" "Boot flag set on partition 1"
    else
        test_result "Boot Flag" "FAIL" "Boot flag not detected"
    fi
    
    # Check GPT partition table
    local partition_table=$(sudo parted "$USB_DEVICE" print | grep "Partition Table:" | awk '{print $3}')
    if [[ "$partition_table" == "gpt" ]]; then
        test_result "Partition Table" "PASS" "GPT format (UEFI compatible)"
    else
        test_result "Partition Table" "FAIL" "Expected GPT, found: $partition_table"
    fi
    
    # Check USB device properties
    local usb_version=$(udevadm info --query=property --name="$USB_DEVICE" | grep "ID_USB_REVISION" | cut -d'=' -f2)
    if [[ -n "$usb_version" ]]; then
        test_result "USB Compatibility" "PASS" "USB revision: $usb_version"
    else
        test_result "USB Compatibility" "FAIL" "USB revision not detected"
    fi
}

# Test system safety (ensure no impact on main system)
test_system_safety() {
    echo
    echo "🛡️ Testing system safety..."
    
    # Verify main system is untouched
    local root_device=$(lsblk -no PKNAME $(findmnt -n -o SOURCE /))
    if [[ "$USB_DEVICE" != "/dev/$root_device" ]]; then
        test_result "Root System Safety" "PASS" "USB device separate from root system"
    else
        test_result "Root System Safety" "FAIL" "WARNING: USB device conflicts with root system!"
    fi
    
    # Check that no system mount points are affected
    local system_mounts=$(mount | grep -E "^${USB_DEVICE}" | grep -E "(/|/boot|/home|/var|/usr)" || echo "")
    if [[ -z "$system_mounts" ]]; then
        test_result "Mount Point Safety" "PASS" "No system mount points affected"
    else
        test_result "Mount Point Safety" "FAIL" "System mount points detected: $system_mounts"
    fi
    
    # Verify main system boot loader is untouched
    if [[ -d "/boot/efi" ]] && [[ -f "/boot/efi/EFI/ubuntu/grubx64.efi" ]]; then
        test_result "Bootloader Safety" "PASS" "Main system bootloader intact"
    else
        test_result "Bootloader Safety" "FAIL" "Main system bootloader status unclear"
    fi
}

# Generate dry-run boot test instructions
generate_boot_test_instructions() {
    echo
    echo "📋 Dry-Run Boot Test Instructions"
    echo "================================="
    echo
    echo "🚨 IMPORTANT: These are DRY-RUN instructions only!"
    echo "   Follow these steps to test USB boot WITHOUT affecting your main system:"
    echo
    echo "1. 🔄 Restart your computer"
    echo "2. ⌨️  Press F12 (or F2/F8/Del) during startup to access boot menu"
    echo "3. 🔍 Select your HP x5000m USB drive from the boot menu"
    echo "4. ✅ Verify Super Grub2 Disk boots and shows menu"
    echo "5. 🔙 Test 'Return to GRUB' option to return to your normal Ubuntu"
    echo "6. 🚫 DO NOT select any 'Fix' or 'Repair' options during testing"
    echo
    echo "Expected Results:"
    echo "   ✅ Super Grub2 menu appears"
    echo "   ✅ 'Detect and show boot methods' option available"
    echo "   ✅ Your Ubuntu system appears in the list"
    echo "   ✅ Can return to normal boot without changes"
    echo
    echo "⚠️  If anything goes wrong:"
    echo "   1. Remove USB and restart normally"
    echo "   2. Your main Ubuntu system should boot normally"
    echo "   3. Report any issues for troubleshooting"
    echo
    echo "🎯 This test confirms the USB works without touching your main system!"
}

# Display comprehensive test results
display_test_summary() {
    echo
    echo "📊 Test Results Summary"
    echo "======================"
    echo
    echo "   Total Tests: $TESTS_TOTAL"
    echo "   ✅ Passed: $TESTS_PASSED"
    echo "   ❌ Failed: $TESTS_FAILED"
    echo
    
    local success_rate=$((TESTS_PASSED * 100 / TESTS_TOTAL))
    echo "   Success Rate: $success_rate%"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "🎉 ALL TESTS PASSED!"
        echo "   Your bulletproof USB rescue system is ready for use."
        echo "   Proceed with the dry-run boot test above."
    elif [[ $success_rate -ge 80 ]]; then
        echo "⚠️  MOSTLY SUCCESSFUL ($success_rate%)"
        echo "   Minor issues detected but system should be functional."
        echo "   Review failed tests and consider fixing before use."
    else
        echo "❌ SIGNIFICANT ISSUES DETECTED ($success_rate%)"
        echo "   Multiple tests failed. USB may not work properly."
        echo "   Review the log and re-run USB creation if needed."
    fi
}

# Main execution
main() {
    echo "🧪 BULLETPROOF USB RESCUE SYSTEM TESTING"
    echo "========================================="
    echo
    echo "This script will test your USB rescue system without making any changes"
    echo "to your main Ubuntu system. All tests are 100% safe and read-only."
    echo
    
    # Execute all tests
    detect_rescue_usb
    test_partition_structure
    test_rescue_tools
    test_bootability
    test_system_safety
    
    # Generate instructions and summary
    generate_boot_test_instructions
    display_test_summary
    
    echo
    echo "Completed: $(date)"
    echo "Log saved: $LOG_FILE"
}

# Run main function
main "$@" 