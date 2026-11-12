#!/bin/sh
#
# Builds Libbox.xcframework, the sing-box core that CryoByte's tunnel
# extensions link, from sing-box's source at a pinned release. Run it by hand
# when the pin changes; CI and local-app.py only download the result
# (scripts/fetch-libbox.sh).
#
# Needs Xcode, git and any Go (`brew install go`); the Go command fetches the
# exact toolchain below. Everything lands outside the checkout, in
# ~/Library/Caches/CryoByte/libbox:
#   src/sing-box-<version>/               the source
#   go<version>/                          a private copy of that Go toolchain
#   bin/                                  gomobile and gobind (sing-box's fork)
#   <version>/Libbox.xcframework(.zip)    the result
set -eu
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

VERSION=1.14.4
COMMIT=c005f35300ce76427dc285481ec5695f5b179cd2
# What sing-box's own release builds use: `build_apple_library` in its
# .github/workflows/build.yml, and `lib_install` in its Makefile.
GO_VERSION=1.26.10
GOMOBILE=v0.1.13

# The iPhone, the Simulator and the Mac. Both Simulator and Mac architectures,
# because a build for a generic destination compiles both.
TARGET=ios/arm64,iossimulator/arm64,iossimulator/amd64,macos/arm64,macos/amd64

# sing-box's own Apple build (cmd/internal/build_libbox) also compiles in
# NaiveProxy (Chromium's network stack), Tailscale, WireGuard, OpenVPN,
# OpenConnect and USB/IP as protocols. CryoByte's exits are Hysteria2
# (with_quic) and VLESS Reality (with_utls), so those stay out; every other
# flag below is theirs. Libbox's own shell-session code still pulls in
# Tailscale's library (experimental/libbox/native_shell_session.go), which is
# what the ts_omit_ flags keep small.
TAGS=with_gvisor,with_quic,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0
TAGS=$TAGS,ts_omit_logtail,ts_omit_ssh,ts_omit_drive,ts_omit_taildrop,ts_omit_webclient,ts_omit_doctor
TAGS=$TAGS,ts_omit_capture,ts_omit_kube,ts_omit_aws,ts_omit_synology,ts_omit_bird
TAGS=$TAGS,with_dhcp,grpcnotrace
LDFLAGS="-X github.com/sagernet/sing-box/constant.Version=$VERSION -X runtime.godebugDefault=multipathtcp=0,tlssha1=1 -checklinkname=0 -s -w -buildid="

CACHE="$HOME/Library/Caches/CryoByte/libbox"
SRC="$CACHE/src/sing-box-$VERSION"
GO="$CACHE/go$GO_VERSION"
OUT="$CACHE/$VERSION"
mkdir -p "$CACHE/src" "$OUT"

# The source, exactly the pinned commit and nothing on top.
if [ ! -d "$SRC/.git" ]; then
  git clone --quiet --depth 1 --branch "v$VERSION" https://github.com/SagerNet/sing-box.git "$SRC"
fi
if [ "$(git -C "$SRC" rev-parse HEAD)" != "$COMMIT" ] || ! git -C "$SRC" diff --quiet HEAD; then
  echo "$SRC is not sing-box $VERSION ($COMMIT) as released" >&2
  exit 1
fi

# Go never detects the iPhone's AES and SHA instructions, so TLS and QUIC
# would run several times slower there. sing-box patches its build's Go for
# that (.github/patch_go_for_ios.sh); the same patch goes onto a copy here,
# and the Go that Homebrew installed stays as it is.
if [ ! -x "$GO/bin/go" ]; then
  rm -rf "$GO.partial"
  cp -R "$(GOTOOLCHAIN="go$GO_VERSION" go env GOROOT)" "$GO.partial"
  chmod -R u+w "$GO.partial"
  (cd "$GO.partial" && patch -s -p1 < "$SRC/.github/go_ios_cpu_features.patch")
  mv "$GO.partial" "$GO"
fi
unset GOROOT
export PATH="$GO/bin:$CACHE/bin:$PATH" GOTOOLCHAIN=local
case "$(GOOS=ios GOARCH=arm64 CGO_ENABLED=0 go list -f '{{.GoFiles}}' internal/cpu)" in
  *cpu_arm64_ios.go*) ;;
  *) echo "The iPhone patch is not in effect in $GO" >&2; exit 1 ;;
esac

GOBIN="$CACHE/bin" go install \
  "github.com/sagernet/gomobile/cmd/gomobile@$GOMOBILE" "github.com/sagernet/gomobile/cmd/gobind@$GOMOBILE"

# gomobile compiles every slice at once; together they stay within 10 jobs.
SLICES=$(echo "$TARGET" | tr ',' '\n' | wc -l)
JOBS=$((10 / SLICES))
[ "$JOBS" -ge 1 ] || JOBS=1

rm -rf "$OUT/Libbox.xcframework" "$OUT/Libbox.xcframework.zip"
cd "$SRC"
nice -n 10 env GOMAXPROCS="$JOBS" GOFLAGS="-p=$JOBS" gomobile bind -v \
  -target "$TARGET" -libname=box -tags-not-macos=with_low_memory \
  -iosversion=15.0 -macosversion=13.0 \
  -trimpath -buildvcs=false -ldflags "$LDFLAGS" -tags "$TAGS" \
  -o "$OUT/Libbox.xcframework" ./experimental/libbox

cd "$OUT"
ditto -c -k --keepParent Libbox.xcframework Libbox.xcframework.zip
echo
echo "sing-box $VERSION ($COMMIT), $(go version | cut -d' ' -f3), gomobile $GOMOBILE"
echo "tags: $TAGS"
size() { echo "$(($(stat -L -f %z "$1") / 1048576)) MB"; }
for slice in Libbox.xcframework/*/; do
  library="${slice}Libbox.framework/Libbox"
  echo "$(basename "$slice"): $(xcrun lipo -archs "$library"), $(size "$library")"
done
echo "$(size Libbox.xcframework.zip)  $OUT/Libbox.xcframework.zip"
echo "sha256 $(shasum -a 256 Libbox.xcframework.zip | cut -d' ' -f1)"
