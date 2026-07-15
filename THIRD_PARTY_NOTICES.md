# Third-party notices

Release builds bundle FFmpeg and FFprobe built under GPLv3 because the build
enables libx264 and libx265. Exact source archives, configure flags, patches,
and dependency licenses must be attached to every binary release.

The bundled media tools also include libvpx and libopus for WebM VP9/Opus
encoding. Their exact pinned revisions are recorded by `scripts/build-ffmpeg.sh`
and included in the corresponding release source archive.

Sparkle is Copyright (c) 2006-2026 Andy Matuschak and contributors and is
distributed under its permissive license. See <https://github.com/sparkle-project/Sparkle>.

SVGO 4.0.1 is bundled as an offline JavaScript resource for SVG optimization.
SVGO is copyright its contributors and licensed under the MIT License. The full
license text is included in the app resources and at
`Sources/OoopsMediaPress/Resources/SVGO/LICENSE.txt`.
