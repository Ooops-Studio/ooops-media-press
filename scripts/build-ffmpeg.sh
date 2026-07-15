#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/work/ffmpeg-build"
PREFIX="$WORK/prefix"
SOURCES="$WORK/sources"
JOBS="$(sysctl -n hw.ncpu)"
export MACOSX_DEPLOYMENT_TARGET=11.0
export CFLAGS="-arch arm64 -mmacosx-version-min=11.0 -O3"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-arch arm64 -mmacosx-version-min=11.0"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

for tool in git curl shasum tar cmake make pkg-config nasm autoconf automake glibtoolize; do
  command -v "$tool" >/dev/null || { echo "Missing build tool: $tool" >&2; exit 1; }
done

mkdir -p "$SOURCES" "$PREFIX"

download() {
  local url="$1" output="$2" checksum="$3"
  if [[ ! -f "$output" ]]; then curl --fail --location "$url" --output "$output"; fi
  echo "$checksum  $output" | shasum -a 256 -c -
}

download "https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz" "$SOURCES/ffmpeg.tar.xz" "464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c"
download "https://bitbucket.org/multicoreware/x265_git/downloads/x265_4.2.tar.gz" "$SOURCES/x265.tar.gz" "40b1ea0453e0309f0eba934e0ddf533f8f6295966679e8894e8f1c1c8d5e1210"
download "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz" "$SOURCES/webp.tar.gz" "e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564"
download "https://github.com/sekrit-twc/zimg/archive/refs/tags/release-3.0.6.tar.gz" "$SOURCES/zimg.tar.gz" "be89390f13a5c9b2388ce0f44a5e89364a20c1c57ce46d382b1fcc3967057577"
download "https://media.xiph.org/opus/models/opus_data-735117b.tar.gz" "$SOURCES/opus_data-735117b.tar.gz" "8f34305a299183509d22c7ba66790f67916a0fc56028ebd4c8f7b938458f2801"

if [[ ! -d "$SOURCES/x264/.git" ]]; then
  git clone https://code.videolan.org/videolan/x264.git "$SOURCES/x264"
fi
git -C "$SOURCES/x264" checkout --detach b35605ace3ddf7c1a5d67a2eb553f034aef41d55

if [[ ! -d "$SOURCES/aom/.git" ]]; then
  git clone https://aomedia.googlesource.com/aom.git "$SOURCES/aom"
fi
git -C "$SOURCES/aom" checkout --detach 03087864cf4bea6abb0d28f95cf7843511413d8f

if [[ ! -d "$SOURCES/libvpx/.git" ]]; then
  git clone https://chromium.googlesource.com/webm/libvpx "$SOURCES/libvpx"
fi
git -C "$SOURCES/libvpx" checkout --detach d168454ecd099805c675d4a98c66f4891373302a

if [[ ! -d "$SOURCES/opus/.git" ]]; then
  git clone https://gitlab.xiph.org/xiph/opus.git "$SOURCES/opus"
fi
git -C "$SOURCES/opus" checkout --detach ddbe48383984d56acd9e1ab6a090c54ca6b735a6

rm -rf "$WORK/src-ffmpeg" "$WORK/src-x265" "$WORK/src-webp" "$WORK/src-zimg" \
  "$WORK/x265-10" "$WORK/x265-8" "$WORK/aom"
mkdir -p "$WORK/src-ffmpeg" "$WORK/src-x265" "$WORK/src-webp" "$WORK/src-zimg"
tar -xf "$SOURCES/ffmpeg.tar.xz" -C "$WORK/src-ffmpeg" --strip-components=1
tar -xf "$SOURCES/x265.tar.gz" -C "$WORK/src-x265" --strip-components=1
tar -xf "$SOURCES/webp.tar.gz" -C "$WORK/src-webp" --strip-components=1
tar -xf "$SOURCES/zimg.tar.gz" -C "$WORK/src-zimg" --strip-components=1

pushd "$SOURCES/x264"
make distclean >/dev/null 2>&1 || true
./configure --prefix="$PREFIX" --host=aarch64-apple-darwin --enable-static --disable-cli --extra-cflags="$CFLAGS" --extra-ldflags="$LDFLAGS"
make -j"$JOBS" && make install
popd

cmake -S "$WORK/src-x265/source" -B "$WORK/x265-10" -G "Unix Makefiles" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
  -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF
cmake --build "$WORK/x265-10" -j "$JOBS"
cp "$WORK/x265-10/libx265.a" "$PREFIX/lib/libx265_main10.a"
cmake -S "$WORK/src-x265/source" -B "$WORK/x265-8" -G "Unix Makefiles" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
  -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DEXTRA_LIB=x265_main10 -DEXTRA_LINK_FLAGS="-L$PREFIX/lib" -DLINKED_10BIT=ON
cmake --build "$WORK/x265-8" -j "$JOBS" --target install
sed -i '' 's/^Libs.private:/Libs.private: -lx265_main10/' "$PREFIX/lib/pkgconfig/x265.pc"

cmake -S "$SOURCES/aom" -B "$WORK/aom" -G "Unix Makefiles" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
  -DBUILD_SHARED_LIBS=OFF -DENABLE_TESTS=OFF -DENABLE_EXAMPLES=OFF -DENABLE_DOCS=OFF
cmake --build "$WORK/aom" -j "$JOBS" --target install

pushd "$SOURCES/libvpx"
make clean >/dev/null 2>&1 || true
./configure --prefix="$PREFIX" --target=arm64-darwin20-gcc \
  --disable-examples --disable-tools --disable-docs --disable-unit-tests \
  --disable-shared --enable-static --enable-vp9-highbitdepth \
  --extra-cflags="$CFLAGS"
make -j"$JOBS" && make install
popd

pushd "$SOURCES/opus"
make distclean >/dev/null 2>&1 || true
cp "$SOURCES/opus_data-735117b.tar.gz" .
./autogen.sh
./configure --prefix="$PREFIX" --disable-shared --enable-static \
  --disable-doc --disable-extra-programs
make -j"$JOBS" && make install
popd

pushd "$WORK/src-webp"
./configure --prefix="$PREFIX" --disable-shared --enable-static --disable-dependency-tracking
make -j"$JOBS" && make install
popd

pushd "$WORK/src-zimg"
./autogen.sh
./configure --prefix="$PREFIX" --disable-shared --enable-static
make -j"$JOBS" && make install
popd

pushd "$WORK/src-ffmpeg"
./configure \
  --prefix="$PREFIX" --arch=arm64 --target-os=darwin --cc=clang \
  --enable-gpl --enable-version3 --enable-static --disable-shared --disable-doc --disable-ffplay \
  --disable-network --disable-xlib --disable-libxcb --disable-sdl2 --enable-videotoolbox --enable-audiotoolbox \
  --enable-libx264 --enable-libx265 --enable-libvpx --enable-libopus --enable-libwebp --enable-libaom --enable-libzimg \
  --pkg-config-flags=--static --extra-cflags="-I$PREFIX/include $CFLAGS" \
  --extra-ldflags="-L$PREFIX/lib $LDFLAGS"
make -j"$JOBS" && make install
popd

TOOLS="$ROOT/Sources/OoopsMediaPress/Resources/Tools"
install -m 755 "$PREFIX/bin/ffmpeg" "$TOOLS/ffmpeg"
install -m 755 "$PREFIX/bin/ffprobe" "$TOOLS/ffprobe"
file "$TOOLS/ffmpeg" "$TOOLS/ffprobe"
otool -L "$TOOLS/ffmpeg"
if otool -L "$TOOLS/ffmpeg" | grep -qE '/opt/homebrew|/usr/local'; then
  echo "FFmpeg contains a non-system dynamic dependency" >&2
  exit 1
fi

{
  echo "ffmpeg 8.1.2"
  echo "x264 b35605ace3ddf7c1a5d67a2eb553f034aef41d55"
  echo "x265 4.2"
  echo "libwebp 1.6.0"
  echo "libaom 03087864cf4bea6abb0d28f95cf7843511413d8f"
  echo "libvpx d168454ecd099805c675d4a98c66f4891373302a (v1.15.2)"
  echo "libopus ddbe48383984d56acd9e1ab6a090c54ca6b735a6 (v1.5.2)"
  echo "libopus model 735117b"
  echo "zimg 3.0.6"
} > "$WORK/source-revisions.txt"

echo "Self-contained tools installed in $TOOLS"
