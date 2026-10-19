# Find My Files

Find My Files is an open-source Finder-inspired file browser for macOS. It pairs
a native AppKit window and filesystem bridge with a web-based interface styled
for macOS dark mode.

## Features

- Browse common locations such as Home, Applications, Desktop, Documents,
  Downloads, iCloud Drive, mounted volumes, and Macintosh HD.
- View items in list or icon view, search names in the current location, and
  sort by name, modification date, or size.
- Display macOS system icons and open files or applications with their default
  macOS handlers.
- Use native context-menu actions to open an item, reveal it in Finder, get
  information, or copy its path.
- Refresh the current location and navigate back and forward.

Some Finder locations, including Recents, AirDrop, and tags, are not yet backed
by macOS indexing and currently show an explanatory message.

## Requirements

- macOS 15 or later
- Xcode Command Line Tools, which provide Swift, the macOS SDK, and `codesign`

The app is currently built as a script-based AppKit/WebKit application by
`build.sh`; the SwiftUI files in the repository are not the active build entry
point.

## Build and run from source

```sh
./build.sh
open "build/Find My Files.app"
```

The build targets the current Mac architecture by default. To build one
architecture explicitly:

```sh
TARGET_ARCH=arm64 ./build.sh
TARGET_ARCH=x86_64 ./build.sh
```

To create a universal release DMG, push a version tag such as `v0.1.0`. GitHub
Actions compiles native Intel and Apple Silicon binaries on their respective
macOS runners, combines them, verifies both architectures, and attaches the
DMG to a GitHub Release.

## Full Disk Access

macOS protects some directories from applications. Find My Files can open
**System Settings → Privacy & Security → Full Disk Access** to let you grant
access. You control whether to enable it; the app cannot grant this permission
itself. Access remains subject to macOS privacy controls.

## Installing a release

Download the universal DMG from the repository's **Releases** page, open it,
and drag **Find My Files.app** to **Applications**.

Release builds are ad-hoc signed and are not notarized. macOS may display a
first-launch security warning for an app downloaded from the internet. Only
open software you trust; do not disable Gatekeeper globally.

## License

Find My Files is distributed under the GNU General Public License, version 3.
See [LICENSE](LICENSE) for the full license text.

###### Copyright (c) 2026 [PSANDILYA1440]

Find My Files is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published
by the Free Software Foundation, version 3.
