#!/bin/bash
# pinch_deploy.sh: Build pinch_post and deploy the gesture synthesizer
# toolchain to the Tart VM.
#
# Extracts libeventtapevent.dylib and LuaSkin.framework from Hammerspoon
# (which must be installed on the host), compiles pinch_post.m for arm64,
# and copies everything to the VM.
#
# Usage: script/pinch_deploy.sh
#
# After deploying, use pinch_post in the VM:
#   /Users/admin/teststrip-vm/gesture/pinch_post <pid> <from> <to> [steps] [delay]

set -euo pipefail

VM_IP="${VM_IP:-192.168.65.2}"
VM_USER="${VM_USER:-admin}"
VM_GESTURE_DIR="/Users/admin/teststrip-vm/gesture"
HAMMERSON="/Applications/Hammerspoon.app"

if [ ! -d "$HAMMERSON" ]; then
  echo "Error: Hammerspoon not found at $HAMMERSON"
  echo "Install Hammerspoon to provide libeventtapevent.dylib"
  exit 1
fi

DYLIB_SRC="$HAMMERSON/Contents/Frameworks/hs/libeventtapevent.dylib"
LUASKIN_SRC="$HAMMERSON/Contents/Frameworks/LuaSkin.framework"

if [ ! -f "$DYLIB_SRC" ]; then
  echo "Error: libeventtapevent.dylib not found in Hammerspoon"
  exit 1
fi

echo "=== Building pinch_post (arm64) ==="
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
clang -arch arm64 -fobjc-arc \
  -framework Foundation -framework CoreGraphics -framework AppKit \
  -framework ApplicationServices \
  -o /tmp/pinch_post "$SCRIPT_DIR/pinch_post.m"
echo "Built /tmp/pinch_post"

echo "=== Extracting arm64 slice of libeventtapevent.dylib ==="
lipo -thin arm64 "$DYLIB_SRC" -output /tmp/libeventtapevent.dylib
echo "Extracted arm64 slice"

echo "=== Deploying to VM ($VM_IP) ==="
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

# Create gesture dir in VM
ssh $SSH_OPTS $VM_USER@$VM_IP "mkdir -p $VM_GESTURE_DIR"

# Copy files
scp $SSH_OPTS /tmp/pinch_post $VM_USER@$VM_IP:$VM_GESTURE_DIR/pinch_post
scp $SSH_OPTS /tmp/libeventtapevent.dylib $VM_USER@$VM_IP:$VM_GESTURE_DIR/libeventtapevent.dylib
scp $SSH_OPTS -r "$LUASKIN_SRC" $VM_USER@$VM_IP:$VM_GESTURE_DIR/LuaSkin.framework

# Make binary executable
ssh $SSH_OPTS $VM_USER@$VM_IP "chmod +x $VM_GESTURE_DIR/pinch_post"

echo "=== Deployed to $VM_GESTURE_DIR ==="
echo "Files:"
ssh $SSH_OPTS $VM_USER@$VM_IP "ls -la $VM_GESTURE_DIR/pinch_post $VM_GESTURE_DIR/libeventtapevent.dylib $VM_GESTURE_DIR/LuaSkin.framework/Versions/A/LuaSkin"
echo ""
echo "Usage in VM:"
echo "  $VM_GESTURE_DIR/pinch_post <pid> <from_scale> <to_scale> [steps] [delay_ms]"
