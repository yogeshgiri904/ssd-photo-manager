# DriveLens Guide

DriveLens is a private native macOS media catalogue for photos and videos stored on an external SSD or local folder. It indexes media in place, stores a local catalogue beside the selected folder, and helps you browse by time, place, folder, search, video type, and recently added media.

## Core Idea

DriveLens does not import your library into the app. Your original files stay in the folder you choose.

When you build or update the catalogue, DriveLens reads metadata from your existing media files and writes a hidden catalogue folder inside the selected media root:

```text
.media-catalog/
  catalog.sqlite
  catalog.json
  thumbnails/
  video-thumbnails/
  geocoding-cache/
  temp/
```

The main metadata mapping is stored in:

```text
.media-catalog/catalog.sqlite
```

That SQLite database stores each media item's relative path, capture date, media type, dimensions, file size, camera metadata, location metadata, thumbnails, and catalogue timestamps.

## Privacy And Safety

DriveLens is designed to be local-first.

- Originals stay on your SSD or chosen folder.
- Metadata is stored locally in `.media-catalog/catalog.sqlite`.
- Thumbnails are stored locally inside `.media-catalog`.
- No cloud upload is used by the app.
- No account, telemetry, AI classification, face recognition, or object recognition is required.
- Delete actions ask for confirmation and move files to macOS Trash.

## Supported Media

DriveLens scans common photo and video formats, including:

- HEIC / HEIF
- JPEG / JPG
- PNG
- TIFF
- GIF
- DNG
- MOV
- MP4
- M4V

Unsupported files are ignored during scanning and counted in scan progress.

## Onboarding

The onboarding flow introduces how DriveLens works and helps you connect a media folder.

### Mapped Folders

The onboarding page can show mapped folders before you choose a new folder.

Mapped folders can come from two sources:

- Saved mappings: folders you previously opened and granted macOS permission for.
- Detected mappings: connected folders that already contain `.media-catalog/catalog.sqlite`.

Saved mappings can be opened directly. Detected mappings may need one macOS permission step, so DriveLens shows an Allow Access action.

### Choose Media Folder

Use Choose Media Folder to select the folder containing your photos and videos. DriveLens will create or reuse the hidden `.media-catalog` folder inside it.

### Build Catalogue

Build Catalogue performs a full scan and rebuilds the catalogue from the selected folder.

### Open Existing

Open Existing opens a selected folder's current catalogue without rebuilding it.

### Reset Folder Selection

The Change Folder option in the sidebar returns to onboarding. It forgets the active folder selection but keeps known mappings available so you can reopen them later.

## Catalogue Updates

Use Update Catalogue to rescan the selected media folder.

Update Catalogue:

- Finds new supported media.
- Refreshes changed media.
- Marks missing files so they can be repaired or removed later.
- Keeps existing metadata and thumbnails for unchanged files.
- Shows confirmation before rescanning.

Scan messages distinguish supported files scanned, new files indexed, changed files refreshed, files already indexed, missing files marked for repair, unsupported files skipped, and failures.

Use Catalogue Actions > Update Folders... to update one or more folders inside the active media folder. This is faster for large catalogues because DriveLens only checks the chosen folders and leaves the rest of the catalogue untouched.

Build Catalogue is a full rebuild. Update Catalogue and Update Folders are the faster ongoing workflows.

## Sidebar

The main app uses a native macOS sidebar with these sections:

- Timeline
- Places
- Folders
- Search
- Videos
- Recently Added
- Smart Albums
- Duplicates
- App Info

Sidebar counts summarize the current catalogue and update after scans, deletes, and filtering changes.

## Timeline

Timeline is the main browsing view.

Features:

- Linear photo grid with equal-sized thumbnail cells.
- Hidden overflow inside each thumbnail box.
- Section headers grouped by date or sort mode.
- Quick filter pills.
- Sorting controls.
- Year filtering.
- Thumbnail size slider.
- Infinite loading for large libraries.
- Inspector sidebar support.
- Keyboard selection.

Quick filters:

- All
- Photos
- Videos
- Mapped
- No Location

Sort options:

- Newest Capture
- Oldest Capture
- Recently Added
- File Name
- Largest Files

## Recently Added

Recently Added uses the same compact filter and sort system as Timeline, but focuses on media based on catalogue-added ordering.

It supports:

- Quick filter pills
- Year filtering
- Sorting
- Grid size control
- Inspector
- Viewer
- Keyboard navigation

## Smart Albums

Smart Albums are generated automatically from the local catalogue database. They do not move or copy originals.

Included groups:

- Screenshots
- Large Videos
- Recently Edited
- Missing Location
- Favorites
- Camera Model groups
- Trip/location groups
- Custom albums
- People placeholder

Open a Smart Album to browse matching items in the standard DriveLens grid with the same viewer, inspector, keyboard navigation, context menu, copy, rename, and delete workflows.

## Places

Places shows media with GPS/location metadata.

Features:

- MapKit map.
- Location clusters for performance on large catalogues.
- Zoom to Media action.
- Automatic zoom to the area containing mapped images.
- Horizontal mapped-media thumbnail strip.
- Click a cluster to focus the map.
- Double-click thumbnails to open the viewer.

Location data is read from media metadata when available and stored in the catalogue database.

## Folders

Folders shows the folder structure from the selected media root.

Features:

- Folder list with item counts.
- Photo and video counts per folder.
- Sort by name, newest, or oldest.
- Open a folder to browse its media in the same grid experience.
- Reveal folders in Finder.
- Folder contents refresh after catalogue changes.

## Search

Search lets you find media by metadata.

Search supports:

- Filename
- Date-related fields
- Place metadata
- Camera metadata
- Media filters

Search filters:

- Photos
- Videos

Use Reset to clear search text and filters.

## Videos

Videos focuses the catalogue on playable video files.

It includes:

- Videos
- Viewer playback
- Inspector details
- Keyboard selection

## Image And Video Viewer

The viewer opens media in a large modal preview.

Images open in contain mode so they are not cropped. Videos also use aspect-fit playback so controls and media stay visible.

Viewer actions:

- Close
- Previous item
- Next item
- Zoom out
- Fit to window
- Zoom in
- Actual size
- Rotate image
- Reveal in Finder
- Copy original
- Share
- Show in Timeline
- Show on Map
- Show in Folder

### Image Gestures

- Pinch: zoom image
- Horizontal swipe/drag: previous or next image when fit to window
- Double-click: toggle fit and zoom

### Video Gestures

- Double-click: play or pause
- Horizontal swipe/drag: seek backward or forward

### Viewer Keyboard Controls

For images:

- Left Arrow: previous item
- Right Arrow: next item
- Up Arrow: zoom in
- Down Arrow: zoom out
- Command-Left Arrow: previous item
- Command-Right Arrow: next item
- Escape: close viewer

For videos:

- Space: play or pause
- Left Arrow: seek backward
- Right Arrow: seek forward
- Up Arrow: volume up
- Down Arrow: volume down
- Command-Left Arrow: previous item
- Command-Right Arrow: next item
- Escape: close viewer

The viewer shows small transient feedback for actions such as Next, Paused, 5s Forward, and Zoom 125%.

## Grid Keyboard Controls

In grid-based sections:

- Arrow keys: move selection
- Space: open selected media
- Delete: ask for delete confirmation
- Double-click thumbnail: open viewer

Global navigation shortcuts:

- Command-1: Timeline
- Command-2: Places
- Command-3: Folders
- Command-4: Search
- Command-5: Videos
- Command-6: Recently Added
- Command-7: Smart Albums
- Command-8: Duplicates
- Command-9: App Info
- Command-Option-I: show or hide Inspector
- Command-Plus: larger thumbnails
- Command-Minus: smaller thumbnails
- Command-Shift-R: Update Catalogue
- Command-Shift-O: Choose Different Media Folder

Timeline sort shortcuts:

- Command-Option-1: Newest Capture First
- Command-Option-2: Oldest Capture First
- Command-Option-3: Recently Added First
- Command-Option-4: File Name
- Command-Option-5: Largest Files

## Inspector

The Inspector is a reusable sidebar component used to show information about the selected item.

It includes:

- Compact preview thumbnail.
- Media type badge.
- Filename and capture date.
- View action.
- Reveal in Finder.
- Copy original.
- Share original.
- Delete with confirmation.
- Essentials metadata.
- Media metadata.
- Camera metadata.
- Extra details such as caption, keywords, and GPS.

Clicking the preview thumbnail opens the viewer.

When multiple files are selected, the Inspector changes to Batch Metadata mode.

Batch Metadata includes:

- Shared metadata summary with mixed-state feedback.
- Add keyword to every selected item.
- Set or replace the displayed caption.
- Set manual latitude, longitude, and place text.
- Mark or remove favorite.
- Add selected items to an existing or new custom album.

DriveLens stores batch metadata in the local catalogue database. Original media files are not modified.

## Delete Behavior

Deleting from the inspector or grid does not immediately destroy files.

DriveLens shows a confirmation first. If confirmed:

- The original file is moved to macOS Trash.
- The catalogue entry is removed.
- Counts and visible grids refresh.
- If the file was already missing, DriveLens removes the missing catalogue entry.

## Missing File Repair

If folders move inside the selected SSD or media folder, run Update Catalogue or Update Folders first. DriveLens marks absent catalogue rows as missing instead of deleting them.

Use Catalogue Actions > Repair Missing Files... to relink moved folders:

- Choose a missing folder group from the sheet.
- Click Relink Folder.
- Select the folder where those files live now.
- DriveLens matches files by the old relative path suffix and file size.
- Matching catalogue paths are remapped without rescanning all metadata.

Repair only changes DriveLens catalogue paths. It does not modify originals.

## Mapping Persistence

Mappings survive SSD disconnect and reconnect when the `.media-catalog` folder remains on the drive.

The catalogue itself is stored beside your media folder, not only inside the app. The app also saves a macOS security-scoped bookmark in UserDefaults so it can reopen the folder after relaunch when permission is still valid.

Mapping usually survives:

- Disconnecting and reconnecting the SSD.
- Restarting the app.
- Reopening the same folder.
- Returning to onboarding and opening a saved mapping.

Mapping may require re-selection when:

- macOS invalidates folder permission.
- The SSD or folder path changes significantly.
- The saved bookmark becomes stale.
- The app is reset or moved between machines.

Mapping is lost if:

- `.media-catalog` is deleted.
- `.media-catalog/catalog.sqlite` is deleted or corrupted.

## Storage Details

Inside `catalog.sqlite`, DriveLens stores records for media items, folders, scan runs, and metadata needed by the app.

Important stored fields include:

- Relative file path
- Folder path
- Filename
- Media type
- Capture date
- Date source
- Dimensions
- Duration
- File size
- Modified date
- Camera make and model
- Lens model
- Caption
- Keywords
- Latitude and longitude
- City, state, country
- Location source
- Thumbnail path
- Video thumbnail path
- Added and updated timestamps

Because paths are relative to the selected media root, the catalogue is more resilient when the SSD mount name changes.

## Recommended Workflow

1. Connect the SSD.
2. Open DriveLens.
3. Choose an existing mapped folder from onboarding, or choose a media folder manually.
4. Run Build Catalogue the first time.
5. Use Timeline and Recently Added for fast browsing.
6. Use Places for GPS-based browsing.
7. Use Search when looking for filenames, dates, locations, cameras, or media types.
8. Use Inspector for item details and file actions.
9. Use Update Catalogue after adding, removing, or changing files on the SSD.

## Troubleshooting

### The SSD mapping is visible but disabled

Reconnect the SSD. If it still does not enable, choose the folder again so macOS can refresh permission.

### A detected mapping asks for access

This is expected. DriveLens can see that a catalogue exists, but macOS still requires user permission before the app can open and manage that folder.

### Counts look stale

Run Update Catalogue. If files were changed outside DriveLens, an update refreshes changed, new, and missing entries.

### Files were moved to another folder

Run Update Catalogue or Update Folders, then use Catalogue Actions > Repair Missing Files... to relink the moved folder. Choose the current folder location inside the active media folder.

### A preview does not load

Use Reveal in Finder from the inspector or viewer to confirm the original file still exists and is readable.

### Map has no items

Only media with GPS/location metadata appears on the map. Media without coordinates remains visible in Timeline, Folders, Search, Videos, and Recently Added.

### Delete did not permanently remove a file

DriveLens moves deleted files to macOS Trash. Empty Trash from Finder if you want permanent deletion.

## Notes For Development

This app is written in SwiftUI with native macOS frameworks:

- SwiftUI for UI
- AppKit for Finder, sharing, file panels, and Trash behavior
- ImageIO for photo metadata
- AVFoundation / AVKit for video metadata, thumbnails, and playback
- MapKit for Places
- SQLite for the local catalogue

The project is intentionally local and dependency-light.
