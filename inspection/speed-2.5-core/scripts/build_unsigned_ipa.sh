#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS_DIR="$ROOT/pip_swift"
OUT_DIR="$ROOT/dist"
DIAG_DIR="$ROOT/build/diagnostics"
RESULT_BUNDLE="$DIAG_DIR/Speed.xcresult"
BUILD_LOG="$DIAG_DIR/xcodebuild.log"
APP_NAME="Speed"
IPA_NAME="Speed-unsigned.ipa"
PROJECT="$IOS_DIR/pip_swift.xcodeproj"
SCHEME="pip_swift"

command -v xcodebuild >/dev/null || { echo "xcodebuild is required (macOS/Xcode)." >&2; exit 2; }
command -v xcrun >/dev/null || { echo "xcrun is required (macOS/Xcode)." >&2; exit 2; }

# The source intentionally targets iOS 26+. Fail before build work if CI
# selected an older Xcode whose iPhoneOS SDK cannot type-check the project.
IOS_SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
python3 - "$IOS_SDK_VERSION" <<'PYSDK'
import sys
try:
    major = int(sys.argv[1].split('.', 1)[0])
except (ValueError, IndexError):
    raise SystemExit(f"Unable to parse iPhoneOS SDK version: {sys.argv[1]!r}")
if major < 26:
    raise SystemExit(f"iPhoneOS 26+ SDK required; selected SDK is {sys.argv[1]}")
PYSDK
echo "Using $(xcodebuild -version | tr '\n' ' ') / iPhoneOS SDK $IOS_SDK_VERSION"

"$ROOT/scripts/verify_project.sh"

echo "Preflight Xcode project and scheme"
xcodebuild -list -project "$PROJECT"
xcodebuild -showBuildSettings \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" >/tmp/speed-build-settings.txt
grep -E "^[[:space:]]*(PRODUCT_NAME|PRODUCT_BUNDLE_IDENTIFIER|SDKROOT|IPHONEOS_DEPLOYMENT_TARGET|TARGETED_DEVICE_FAMILY|SWIFT_VERSION)[[:space:]]*=" /tmp/speed-build-settings.txt || true

cd "$IOS_DIR"
rm -rf "$ROOT/build" "$OUT_DIR"
mkdir -p "$OUT_DIR/Payload" "$DIAG_DIR"

echo "Starting Xcode build; diagnostics: $DIAG_DIR"
set +e
xcodebuild \
  -project pip_swift.xcodeproj \
  -scheme pip_swift \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$ROOT/build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  -resultBundlePath "$RESULT_BUNDLE" \
  clean build 2>&1 | tee "$BUILD_LOG"
XCODE_STATUS=${PIPESTATUS[0]}
set -e
if (( XCODE_STATUS != 0 )); then
  echo "xcodebuild failed with status $XCODE_STATUS. Preserved log: $BUILD_LOG" >&2
  [[ -d "$RESULT_BUNDLE" ]] && echo "Preserved result bundle: $RESULT_BUNDLE" >&2
  echo "===== Xcode compiler error summary =====" >&2
  grep -nE ':[0-9]+:[0-9]+: error:|(^|[[:space:]])error:' "$BUILD_LOG" | tail -n 120 >&2 || true
  echo "===== End compiler error summary =====" >&2
  exit "$XCODE_STATUS"
fi

BUILT_APP="$ROOT/build/DerivedData/Build/Products/Release-iphoneos/${APP_NAME}.app"
[[ -d "$BUILT_APP" ]] || { echo "Built .app not found: $BUILT_APP" >&2; exit 3; }
cp -R "$BUILT_APP" "$OUT_DIR/Payload/"

cd "$OUT_DIR"
/usr/bin/zip -qry "$IPA_NAME" Payload
rm -rf Payload

echo "IPA: $OUT_DIR/$IPA_NAME"
