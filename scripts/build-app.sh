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

ICON_SRC="$ROOT_DIR/Assets/AppIcon.png"
if [[ ! -f "$ICON_SRC" ]]; then
    echo "Error: expected app icon asset at $ICON_SRC" >&2
    exit 1
fi

ICON_TMP="$(mktemp -d "${TMPDIR:-/tmp}/notecast-icon.XXXXXX")"
ICON_GEN_SRC="$ICON_TMP/gen_icon.swift"
ICON_GEN_BIN="$ICON_TMP/gen_icon"

cat > "$ICON_GEN_SRC" << 'SWIFT'
import AppKit
import ImageIO

guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: gen_icon <source.png> <output.icns>\n", stderr)
    exit(1)
}

let inFile = URL(fileURLWithPath: CommandLine.arguments[1])
let outFile = URL(fileURLWithPath: CommandLine.arguments[2])

guard let imageSource = CGImageSourceCreateWithURL(inFile as CFURL, nil),
      let sourceCGImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
    fputs("Error: failed to load source PNG at \(inFile.path)\n", stderr)
    exit(1)
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
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
    guard let ctx = CGContext(
        data: nil,
        width: px,
        height: px,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fputs("Error: failed to allocate \(px)x\(px) CGContext\n", stderr)
        exit(1)
    }

    ctx.interpolationQuality = .high
    ctx.clear(CGRect(x: 0, y: 0, width: px, height: px))
    ctx.draw(sourceCGImage, in: CGRect(x: 0, y: 0, width: px, height: px))

    guard let scaledImage = ctx.makeImage(),
          let pngData = NSBitmapImageRep(cgImage: scaledImage).representation(using: .png, properties: [:]) else {
        fputs("Error: failed to encode \(px)x\(px) PNG chunk\n", stderr)
        exit(1)
    }

    let chunkLength = UInt32(8 + pngData.count).bigEndian
    body.append(contentsOf: chunkType.utf8)
    withUnsafeBytes(of: chunkLength) { body.append(contentsOf: $0) }
    body.append(pngData)
}

var icns = Data()
let totalLength = UInt32(8 + body.count).bigEndian
icns.append(contentsOf: "icns".utf8)
withUnsafeBytes(of: totalLength) { icns.append(contentsOf: $0) }
icns.append(body)

try icns.write(to: outFile, options: [.atomic])
SWIFT

if ! swiftc "$ICON_GEN_SRC" -o "$ICON_GEN_BIN" -framework AppKit -framework ImageIO; then
    rm -rf "$ICON_TMP"
    echo "Error: failed to compile icon generator" >&2
    exit 1
fi

if ! "$ICON_GEN_BIN" "$ICON_SRC" "$RESOURCES_DIR/AppIcon.icns"; then
    rm -rf "$ICON_TMP"
    echo "Error: failed to generate AppIcon.icns from $ICON_SRC" >&2
    exit 1
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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
