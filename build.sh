#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_APP="/Applications/AntigravityBar.app"
STAGING_DIR="$DIR/dist"
STAGING_APP="$STAGING_DIR/AntigravityBar.app"

echo "==> 1. Stopping any running instance ..."
pkill -x "AntigravityBar" 2>/dev/null || true
sleep 0.5

echo "==> 2. Installing CLI script to ~/.local/bin/agy-limits ..."
mkdir -p "$HOME/.local/bin"
cp "$DIR/antigravity_limits.py" "$HOME/.local/bin/agy-limits"
chmod +x "$HOME/.local/bin/agy-limits"
ln -sf "$HOME/.local/bin/agy-limits" "$HOME/.local/bin/antigravity-limits"
ln -sf "$HOME/.local/bin/agy-limits" "$HOME/.local/bin/limits"

echo "==> 3. Cleaning old installations ..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$TARGET_APP" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$HOME/Applications/AntigravityBar.app" 2>/dev/null || true
rm -rf "$TARGET_APP"
rm -rf "$HOME/Applications/AntigravityBar.app"
rm -rf "$STAGING_DIR"

echo "==> 4. Building clean app bundle in staging directory ..."
mkdir -p "$STAGING_APP/Contents/MacOS"
mkdir -p "$STAGING_APP/Contents/Resources"

# Compile Swift binary
swiftc -O -o "$STAGING_APP/Contents/MacOS/AntigravityBar" "$DIR/AntigravityBar.swift"

# Copy Info.plist and PkgInfo
cp "$DIR/Info.plist" "$STAGING_APP/Contents/Info.plist"
printf "APPL????" > "$STAGING_APP/Contents/PkgInfo"

# Copy Icon and Status Bar assets
cp "$DIR/AppIcon.icns" "$STAGING_APP/Contents/Resources/AppIcon.icns"
cp "$DIR/StatusBarIcon.png" "$STAGING_APP/Contents/Resources/StatusBarIcon.png"
cp "$DIR/StatusBarIcon@2x.png" "$STAGING_APP/Contents/Resources/StatusBarIcon@2x.png"
cp "$DIR/antigravity_limits.py" "$STAGING_APP/Contents/Resources/antigravity_limits.py"
chmod +x "$STAGING_APP/Contents/Resources/antigravity_limits.py"

echo "==> 5. Ad-hoc signing application bundle ..."
codesign --force --deep -s - "$STAGING_APP"

echo "==> 6. Installing cleanly into /Applications ..."
cp -R "$STAGING_APP" "$TARGET_APP"
rm -rf "$STAGING_DIR"

# Touch to trigger Finder update
touch "$TARGET_APP"

echo "==> 7. Registering bundle with LaunchServices ..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$TARGET_APP"

if [[ "$*" != *"--no-launch"* ]]; then
  echo "==> 8. Launching AntigravityBar ..."
  open "$TARGET_APP"
else
  echo "==> 8. Skipping launch (--no-launch flag passed)."
fi

echo "==> Clean install complete!"
