# Ooops Media Press app icon

The icon depicts the app's core interaction: original media on the vivid left,
compressed media on the tiled right, and the draggable comparison divider in
the center. It intentionally contains no letterform or “O”.

## Rebuild the bundled icon

Run:

```sh
./scripts/build-app-icon.sh
```

The script renders `AppIcon-master.svg` at every macOS icon size and creates
`Resources/AppIcon.icns`. It requires `librsvg` (`brew install librsvg`) and the
macOS `iconutil` command.

## Apple Icon Composer import kit

Icon Composer is downloaded separately from Apple and requires an Apple
Developer sign-in. Create a new 1024×1024 icon, then import these files in
numeric order as separate layers:

1. `IconComposer/01-background.svg`
2. `IconComposer/02-media.svg`
3. `IconComposer/03-divider.svg`

Keep the background layer opaque and full bleed. Use the default system icon
shape; do not add a custom mask. Apply only a subtle depth response to the media
layer and a slightly stronger specular response to the divider. Check Default,
Dark and Mono appearances before saving the final `.icon` document.

The checked-in `.icns` is the compatibility asset for the current SwiftPM
bundle and works on macOS 11 and later. A future Xcode project can compile the
Icon Composer `.icon` document for macOS 26 while retaining this fallback.
