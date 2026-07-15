# Ooops Media Press

An arm64-only, local macOS image and video compressor with a draggable
before/after comparison view. The app targets macOS 11 and adopts native
Liquid Glass when running on macOS 26.

SVG files are optimized locally with the bundled SVGO engine. Safe, Balanced
and Aggressive modes provide metadata cleanup, decimal precision, multipass and
optional path simplification controls. Scriptable and external SVG content is
removed before preview and export.

## Development

Requirements: Swift 6.2+ and Xcode 26 for app archives. Development and release
builds use the self-contained FFmpeg/FFprobe binaries placed in
`Sources/OoopsMediaPress/Resources/Tools`.

Video output supports MP4 with H.264 or HEVC and WebM with VP9/Opus. WebM is
encoded locally through the bundled, pinned libvpx and libopus dependencies.

The checked-in SVGO browser bundle is a runtime resource and requires no Node.js
installation. Maintainers only need Node/npm when refreshing the pinned bundle
with `scripts/update-svgo.sh`.

```sh
swift build
swift test
```

Run `scripts/package-app.sh` after a release build to create the signed
`build/Ooops-Media-Press-<version>.zip`. The app is kept inside the ZIP because
cloud-backed Documents folders may attach metadata that invalidates an ad-hoc
signature on a directly stored `.app` bundle.

## First launch

Public builds are ad-hoc signed and not notarized. After copying the app into
Applications, Control-click it in Finder, choose **Open**, then confirm once.

## Privacy

All media processing is local. The only network feature is Sparkle's update
check. There is no telemetry or analytics.
