#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Notecast"
BUNDLE_ID="com.notecast.app"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

INSTALL_TO_APPLICATIONS=false
EXTRA_BUILD_FLAGS=()

for arg in "$@"; do
    case "$arg" in
        --install)
            INSTALL_TO_APPLICATIONS=true
            ;;
        *)
            EXTRA_BUILD_FLAGS+=("$arg")
            ;;
    esac
done

echo "Building $APP_NAME (release)..."
cd "$ROOT_DIR"
if [[ ${#EXTRA_BUILD_FLAGS[@]} -gt 0 ]]; then
    swift build -c release "${EXTRA_BUILD_FLAGS[@]}"
    BIN_DIR="$(swift build -c release "${EXTRA_BUILD_FLAGS[@]}" --show-bin-path | tail -n 1)"
else
    swift build -c release
    BIN_DIR="$(swift build -c release --show-bin-path | tail -n 1)"
fi

BIN_PATH="$BIN_DIR/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "Error: expected binary at $BIN_PATH" >&2
    exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

ICON_PLIST_ENTRY=""
ICON_TMP="$(mktemp -d "${TMPDIR:-/tmp}/notecast-icon.XXXXXX")"
ICON_GEN_SRC="$ICON_TMP/gen_icon.swift"
ICON_GEN_BIN="$ICON_TMP/gen_icon"

cat > "$ICON_GEN_SRC" << 'SWIFT'
import AppKit

let outFile = URL(fileURLWithPath: CommandLine.arguments[1])
let entries: [(String, Int)] = [
    ("icp4", 16),
    ("ic11", 32),
    ("icp5", 32),
    ("ic12", 64),
    ("ic07", 128),
    ("ic13", 256),
    ("ic08", 256),
    ("ic14", 512),
    ("ic09", 512),
    ("ic10", 1024),
]

var body = Data()

for (chunkType, px) in entries {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let size = CGFloat(px)
    let inset = size * 0.08
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = size * 0.22
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.14, green: 0.16, blue: 0.21, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 1.0)
    )!
    gradient.draw(in: path, angle: -90)

    NSColor(calibratedWhite: 1.0, alpha: 0.16).setStroke()
    path.lineWidth = max(1, size * 0.012)
    path.stroke()

    let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.44, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig)
    {
        let tinted = NSImage(size: symbol.size, flipped: false) { bounds in
            symbol.draw(in: bounds)
            NSColor(calibratedRed: 0.96, green: 0.97, blue: 1.0, alpha: 0.95).set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        let imgSize = tinted.size
        let dest = NSRect(
            x: (size - imgSize.width) * 0.5,
            y: (size - imgSize.height) * 0.5,
            width: imgSize.width,
            height: imgSize.height
        )
        tinted.draw(in: dest)
    }

    NSGraphicsContext.restoreGraphicsState()

    if let pngData = rep.representation(using: .png, properties: [:]) {
        let chunkLength = UInt32(8 + pngData.count).bigEndian
        body.append(contentsOf: chunkType.utf8)
        withUnsafeBytes(of: chunkLength) { body.append(contentsOf: $0) }
        body.append(pngData)
    }
}

var icns = Data()
let totalLength = UInt32(8 + body.count).bigEndian
icns.append(contentsOf: "icns".utf8)
withUnsafeBytes(of: totalLength) { icns.append(contentsOf: $0) }
icns.append(body)

try icns.write(to: outFile, options: [.atomic])
SWIFT

if swiftc "$ICON_GEN_SRC" -o "$ICON_GEN_BIN" -framework AppKit 2>/dev/null; then
    if "$ICON_GEN_BIN" "$RESOURCES_DIR/AppIcon.icns"; then
        ICON_PLIST_ENTRY=$'    <key>CFBundleIconFile</key>\n    <string>AppIcon</string>'
    fi
fi
rm -rf "$ICON_TMP"

cat > "$CONTENTS_DIR/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
$ICON_PLIST_ENTRY
</dict>
</plist>
PLIST

echo "Signing $APP_BUNDLE..."
codesign --force --deep --sign - "$APP_BUNDLE"

if [[ "$INSTALL_TO_APPLICATIONS" == true ]]; then
    DEST="/Applications/$APP_NAME.app"
    echo "Installing to $DEST..."
    rm -rf "$DEST"
    cp -R "$APP_BUNDLE" "$DEST"
    echo "Installed: $DEST"
else
    echo "Built: $APP_BUNDLE"
fi
