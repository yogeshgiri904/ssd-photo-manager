# DriveLens

DriveLens is a private native macOS catalogue for photographs and videos stored on an external SSD. It indexes existing media in place, keeps originals untouched, and creates only a hidden .media-catalog folder inside the selected media root.

## What It Does

- Builds a local SQLite catalogue of supported photos and videos.
- Stores relative paths so the catalogue survives SSD mount-name changes.
- Generates small grid thumbnails and video poster frames.
- Reads existing metadata from ImageIO and AVFoundation.
- Browses by Timeline, Places, Folders, Search, Videos, Recently Added, and Smart Albums.
- Opens originals only when the user enters the viewer.
- Uses security-scoped bookmarks for persistent folder access.

## Privacy And Safety

DriveLens does not use telemetry, analytics, cloud upload, accounts, subscriptions, AI classification, face recognition, object recognition, or paid services. It never formats the SSD and never moves, renames, edits, or deletes originals.

The app writes only here inside the selected SSD folder:

~~~text
.media-catalog/
  catalog.sqlite
  catalog.json
  thumbnails/
  video-thumbnails/
  geocoding-cache/
  temp/
~~~

## Supported Media

Prioritized formats:

- HEIC / HEIF
- JPEG / JPG
- PNG
- TIFF
- GIF
- DNG
- MOV
- MP4
- M4V

Unsupported files are ignored during scanning and counted in the scan summary.

## Build Requirements

- Apple Silicon Mac recommended
- macOS 14 or later
- Free Xcode installation from Apple
- No Apple Developer Program membership
- No Homebrew, Docker, Node.js, Python, server, or paid dependency

## Build And Run

1. Open DriveLens.xcodeproj in Xcode.
2. Select the DriveLens scheme.
3. In Signing & Capabilities, choose your local team if Xcode asks. A free Apple ID is enough for running locally.
4. Press Command-R to build and run.
5. On first launch, choose the folder on your SSD that contains your media.
6. Choose Build Catalogue.

## Copy To Applications

After building in Xcode:

1. In Xcode, open Product > Show Build Folder in Finder.
2. Open the build products folder for the active configuration.
3. Copy DriveLens.app to /Applications.
4. Launch it locally. macOS may ask for confirmation because this is a personal unsigned/not-notarized build.

## Current Implementation Notes

This first implementation provides the native app foundation, catalogue database, scanner, metadata extraction, thumbnail cache on disk, onboarding, browsing screens, viewer, and inspector. Future hardening should add deeper pagination controls, clustered MapKit annotations, optional reverse geocoding cache UI, and broader stress testing against very large libraries.
