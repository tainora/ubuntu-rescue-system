#!/bin/bash
# Download Essential Rescue Tools
# Safety Level: 1 (Safe - Downloads only)
# 
# Downloads all proven rescue tools for bulletproof dual-boot strategy

set -euo pipefail

# Configuration
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOAD_DIR="$TOOLS_DIR/downloads"
LOG_FILE="$TOOLS_DIR/../logs/download-$(date +%Y%m%d_%H%M%S).log"

# Create directories
mkdir -p "$DOWNLOAD_DIR" "$(dirname "$LOG_FILE")"

# Logging setup
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

echo "=== Downloading Bulletproof Rescue Tools ==="
echo "Download Directory: $DOWNLOAD_DIR"
echo "Started: $(date)"
echo

# Function to download with verification
download_tool() {
    local name="$1"
    local url="$2"
    local filename="$3"
    
    echo "📥 Downloading $name..."
    
    if [[ -f "$DOWNLOAD_DIR/$filename" ]]; then
        echo "   ✅ Already exists: $filename"
        local size=$(du -sh "$DOWNLOAD_DIR/$filename" | cut -f1)
        echo "   📁 Size: $size"
        return 0
    fi
    
    # Download with progress and retry
    echo "   🌐 URL: $url"
    if wget --progress=bar:force --tries=3 --timeout=30 -O "$DOWNLOAD_DIR/$filename" "$url"; then
        echo "   ✅ Downloaded successfully"
        local size=$(du -sh "$DOWNLOAD_DIR/$filename" | cut -f1)
        echo "   📁 Size: $size"
    else
        echo "   ❌ Download failed!"
        rm -f "$DOWNLOAD_DIR/$filename"
        return 1
    fi
}

# Download Super Grub2 Disk (Bulletproof boot recovery)
echo "🛡️ Super Grub2 Disk 2.06s4 (SecureBoot compatible)"
download_tool \
    "Super Grub2 Disk" \
    "https://sourceforge.net/projects/supergrub2/files/2.06s4/super_grub2_disk_2.06s4/supergrub2-2.06s4-multiarch-USB.img.zip/download" \
    "supergrub2-2.06s4-multiarch-USB.img.zip"

# Download Boot-Repair-Disk (One-click boot repair)
echo
echo "🔧 Boot-Repair-Disk (Automated boot fixing)"
download_tool \
    "Boot-Repair-Disk" \
    "https://sourceforge.net/projects/boot-repair-cd/files/boot-repair-disk-64bit.iso/download" \
    "boot-repair-disk-64bit.iso"

# Download SystemRescue (Complete rescue environment) - using alternative mirror
echo
echo "🚑 SystemRescue (Complete rescue toolkit)"
download_tool \
    "SystemRescue" \
    "https://mirror.aarnet.edu.au/pub/systemrescue/releases/11.01/systemrescue-11.01-amd64.iso" \
    "systemrescue-11.01-amd64.iso"

# Download Clonezilla (Full system imaging) - using alternative mirror
echo
echo "💾 Clonezilla (System imaging and cloning)"
download_tool \
    "Clonezilla" \
    "https://mirror.aarnet.edu.au/pub/clonezilla-live/stable/3.1.2-22/clonezilla-live-3.1.2-22-amd64.iso" \
    "clonezilla-live-3.1.2-22-amd64.iso"

echo
echo "=== Download Summary ==="
echo "📁 Downloaded files:"
if [[ -d "$DOWNLOAD_DIR" ]] && [[ $(ls -A "$DOWNLOAD_DIR" 2>/dev/null | wc -l) -gt 0 ]]; then
    ls -lh "$DOWNLOAD_DIR"
    echo
    echo "💾 Total size: $(du -sh "$DOWNLOAD_DIR" | cut -f1)"
    
    # Count successful downloads
    local download_count=$(ls -1 "$DOWNLOAD_DIR" | wc -l)
    echo "📊 Downloaded: $download_count/4 tools"
    
    if [[ $download_count -eq 4 ]]; then
        echo "✅ All tools downloaded successfully!"
    elif [[ $download_count -gt 0 ]]; then
        echo "⚠️  Partial download - some tools may be missing"
    else
        echo "❌ No tools downloaded successfully"
    fi
else
    echo "❌ No files downloaded"
fi

echo
echo "🔄 Next steps:"
echo "   1. Run: ./create-usb-set.sh"
echo "   2. Test: ./test-recovery.sh"
echo "   3. Store USBs safely"
echo
echo "Completed: $(date)" 