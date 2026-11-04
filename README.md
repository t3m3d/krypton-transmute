# Krypton Transmute

A native macOS converter written in **Krypton**. The window and controls are pure
Krypton on `k:okui` (Objective-K over AppKit); conversion runs through macOS
`sips`/ImageIO for images, `textutil`/`cupsfilter` for documents,
`afconvert`/`afinfo` for audio, `avconvert` for video, and the Python standard
library (through the bundled `src/toolkit.py`) for tables, structured data,
markup, e-books, subtitles, archives, 3D meshes, text encodings and fonts. No C,
Objective-C or Swift source is involved.

## Features

- **Four panels: images, documents, audio and toolbox.** The header switch (or
  ⌘1/⌘2/⌘3/⌘4) swaps panels; each keeps its own queue, settings and output
  folder.
- **Queue images one at a time or by folder.** Folder intake scans two levels
  deep for PNG, JPEG, HEIC, WebP, AVIF, TIFF, BMP and GIF inputs.
- **Export to PNG, JPEG, HEIC, AVIF, TIFF, GIF or BMP.** WebP is readable but
  not writable: macOS ImageIO has no WebP encoder, so it is not offered.
- **Quality control** (1–100) for the lossy formats: JPEG, HEIC and AVIF.
- **Resize** by longest edge in pixels, or by percentage of the original width,
  using ImageIO's high-quality resampling.
- **Filename suffix** and a choice of destination: alongside each source, or a
  folder you pick.
- **Safe output.** Existing files are never overwritten — a numbered name is
  used instead — and the source file is never replaced.
- **App icon bundles.** "Build icons" writes a macOS `.icns` (16–1024 px, all
  iconset entries) and a Windows `.ico` (six embedded sizes: 16/32/48/64/128/256)
  for every queued image. Non-square sources are center-cropped first.
- **Document conversion.** A second panel converts text documents with
  `textutil` and can print them to PDF (see below).
- **Audio conversion.** A third panel converts with `afconvert`: AAC, Apple
  Lossless, WAV, AIFF, CAF and FLAC, with an AAC bitrate control (see below).
- **Toolbox conversion.** A fourth panel covers video, tables, structured data,
  markup, e-books, subtitles, archives, 3D meshes, text encodings and fonts —
  36 target formats behind one grouped list (see Toolbox formats).
- **Queue table** with type, dimensions or kind and file size, an activity log,
  progress bar and "Reveal last output" in Finder.
- **Purple editor-style dark theme**, monospaced throughout, with menu
  shortcuts: ⌘O add image, ⌘T add document, ⌘U add audio, ⌘B add to the toolbox,
  ⌘D add folder (for the current panel), ⌘R convert images, ⌘Y convert documents,
  ⌘L convert audio, ⌘J convert the toolbox, ⌘I build icons, ⌘K clear queue,
  ⌘1/⌘2/⌘3/⌘4 switch panels.

## Document formats

The document panel reads and writes the formats macOS `textutil` supports:

| Reads | Writes |
| --- | --- |
| txt, md, rtf, rtfd, html, htm, doc, docx, odt, wordml, webarchive | TXT, RTF, RTFD, HTML, DOC, DOCX, ODT, WordML, WebArchive |

**PDF is output only, and text-only.** macOS ships no document-to-PDF filter
apart from `cupsfilter`'s plain-text path, so the app extracts the document's
text and prints that: the words survive, the layout does not. PDFs cannot be
read back, because `textutil` has no PDF reader and macOS ships no PDF toolkit
with text extraction.

## Audio formats

The audio panel uses CoreAudio's `afconvert` to write and `afinfo` to read:

| Reads | Writes |
| --- | --- |
| aiff, aif, aifc, wav, m4a, m4b, aac, caf, flac, mp3, au, snd | M4A (AAC), ALAC, WAV, AIFF, CAF, FLAC |

AAC takes the bitrate field (8–512 kbps); the other five formats are lossless
and ignore it. **MP3 is input only** — macOS ships no MP3 encoder, so `.mp3`
can be read and converted away from but never written.

## Toolbox formats

The fourth panel groups everything macOS cannot convert by itself. Video uses
Apple's `avconvert`; the rest is parsed by `src/toolkit.py` (Python standard
library only), which the build installs into
`~/Library/Application Support/Krypton Transmute/`.

| Family | Reads | Writes |
| --- | --- | --- |
| Video | mov, mp4, m4v, m4a | MP4 (H.264), MOV (ProRes 422), M4V, M4A (audio only) |
| Tables | csv, tsv, json, xlsx | CSV, TSV, JSON, XLSX |
| Structured data | json, yaml, yml, toml, xml, plist | JSON, YAML, TOML, XML |
| Markup | html, htm, md, markdown, txt | HTML, Markdown, TXT |
| E-books | epub, html, htm, md, markdown, txt | EPUB, HTML, TXT, Markdown, DOCX |
| Subtitles | srt, vtt, ass, ssa | SRT, VTT, ASS |
| Archives | zip, tar, tgz, gz | ZIP, TAR, TGZ |
| 3D models | obj, stl, ply, glb, gltf | OBJ, ASCII STL, ASCII PLY, GLB, glTF |
| Text encoding | txt, md, csv, tsv, json, yaml, xml, html, srt, vtt, ass | UTF-8, UTF-16, Latin-1, Windows-1252 (extension kept) |
| Fonts | ttf, otf | WOFF (WOFF 1.0) |

The target format is one grouped list (`Tables · CSV`, `Video · MP4`, …); the
family follows from that choice. Files from another family are skipped and
reported instead of being forced through a converter. Video takes a maximum
height (480/720/1080); EPUB takes a title.

**Not offered, and why:** MP3/OGG encoding, MKV/WebM and video-to-GIF need
FFmpeg, which is not installed; 7Z needs p7zip; WOFF2 needs fontTools'
`woff2_compress`. The panel's tooltip names these instead of shipping
half-working converters. DOCX is written through macOS `textutil`, and WOFF is
built from the font's own tables. YAML/TOML cover the ordinary configuration
subset (mappings, sequences, scalars, tables), and XLSX round-trips cell values
without formulas or styling.

## Requirements

- macOS 14 or newer (Apple silicon toolchain used below)
- The Krypton compiler: `/usr/local/krypton/bootstrap/kcc_driver_macos_aarch64`
  (or any `kcc` on `PATH`; override with `KCC=/path/to/kcc`)
- Python 3 for the toolbox families — the system `/usr/bin/python3` from the
  Xcode Command Line Tools is enough; the build copies `toolkit.py` where the
  app looks for it.

## Build and run

```bash
./scripts/build-app.sh
open "dist/Krypton Transmute.app"
```

The bundle is ad-hoc signed. Drag it to `/Applications` if you want it around.

For a quick syntax/run check without packaging:

```bash
kcc -r src/transmute.ks
```

## Tests

```bash
./scripts/test.sh
```

The checks build a real PNG fixture from `assets/AppIcon.icns`, then verify
every offered image format, longest-edge and percentage resizing, collision-safe
naming, folder scanning, `.icns`/`.ico` icon bundles (including a non-square
source and the ICO's six-size header), every document format plus the PDF
header, RTF→DOCX text fidelity, document scanning, every audio format plus an
AAC bitrate comparison and audio scanning, every toolbox family (CSV/TSV/JSON/
XLSX round trips, JSON↔YAML/TOML/XML, Markdown↔HTML↔TXT, EPUB build and
re-extract, EPUB→DOCX text fidelity, SRT↔VTT↔ASS timings, ZIP↔TAR↔TGZ contents,
OBJ↔STL↔PLY↔GLB geometry, UTF-8→Latin-1/UTF-16 bytes, a real TTF→WOFF build),
the video preset mapping, and the path/size helpers — 200 checks. Krypton's
`exit` does not propagate a status through `kcc -r`, so the shell harness fails
on the "checks failed" summary line.

## Project layout

```
src/engine.ks        Conversion engine: image, document, audio and toolbox
                     format tables, sips/textutil/afconvert/avconvert commands,
                     paths, naming, metadata queries, folder scanning,
                     .icns/.ico assembly
src/transmute.ks     The app: palette, window layout, all four panels, state,
                     actions, menus
src/toolkit.py       Python stdlib parsers for tables, data, markup, e-books,
                     subtitles, archives, meshes, text encodings and WOFF
                     fonts (installed by the build)
src/engine_test.ks   Engine checks
assets/AppIcon.icns  App icon asset
scripts/build-app.sh Compiles with kcc and assembles the .app bundle
scripts/test.sh      Runs the engine checks
```

## Theming

The palette is nine colour functions near the top of `src/transmute.ks`
(`cCanvas`, `cSurface`, `cText`, `cMuted`, `cFaint`, `cBlue`, `cPurple`,
`cGreen`, `cAmber`, `cRed`). Every view reads from them, so re-skinning is a
single-file edit.

## Known limits

- No drag and drop: OKUI exposes file panels, not drop targets. Add image or
  add folder are the intake paths.
- No metadata stripping yet; `sips` does not offer a "strip everything" flag.
- PDF output is text-only and PDF input is not supported (see Document
  formats).
- MP3 output is unavailable on macOS (see Audio formats); lossless audio keeps
the source's sample rate and channel count.
- Fonts convert to WOFF 1.0 only: WOFF2 needs fontTools' `woff2_compress`, and
  7Z needs p7zip; neither is installed. Video is limited to `avconvert`'s
  presets, so MKV/WebM/GIF output would need FFmpeg.
- Toolbox parsing is single-threaded and the e-book reader flattens a book's
  chapters into one document; EPUB images and CSS are not carried across.
  DOCX keeps the text and basic styling that `textutil` understands.
- glTF/GLB carry vertex positions and triangles; node translations, rotations,
  scales and matrices are applied on import. Materials, normals and textures are
  dropped, and instanced meshes are merged into one object.
- Encoding conversion detects UTF-8/UTF-16 by BOM and replaces characters the
  chosen target cannot represent (for example an em dash in Latin-1).
- XLSX and YAML/TOML support the common subset: cell values, mappings,
  sequences and scalars, not formulas, styling or spec corner cases.
- Icon output ignores the format, quality and resize settings: icons always use
  fixed size ladders and a center-cropped square master.
- Conversion runs synchronously on the UI thread, so very large batches hold the
  window until they finish. Progress and per-file results are reported in the
  activity log.

## Platform roadmap

`k:okui` already routes to Forge's Windows/Choc backend, so a Windows build is
the natural next shell. The engine would need a Windows codec path replacing
`sips`. Linux still needs a backend.

## License

MIT — see `LICENSE`.
