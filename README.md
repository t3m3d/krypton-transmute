# Krypton Transmute

A native macOS image format converter written in **Krypton**. The window and
controls are pure Krypton on `k:okui` (Objective-K over AppKit); conversion runs
through macOS `sips`/ImageIO, so no C, Objective-C or Swift source is involved.

## Features

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
- **Queue table** with type, pixel dimensions and file size, an activity log,
  progress bar and "Reveal last output" in Finder.
- **Editor-style dark theme**, monospaced throughout, with menu shortcuts:
  ⌘O add image, ⌘D add folder, ⌘R convert all, ⌘K clear queue.

## Requirements

- macOS 14 or newer (Apple silicon toolchain used below)
- The Krypton compiler: `/usr/local/krypton/bootstrap/kcc_driver_macos_aarch64`
  (or any `kcc` on `PATH`; override with `KCC=/path/to/kcc`)

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
conversion to JPEG/HEIC/AVIF, longest-edge and percentage resizing,
collision-safe naming, folder scanning and the path/size helpers. Krypton's
`exit` does not propagate a status through `kcc -r`, so the shell harness fails
on the "checks failed" summary line.

## Project layout

```
src/engine.ks        Conversion engine: format table, sips commands, paths,
                     naming, metadata queries, folder scanning
src/transmute.ks     The app: palette, window layout, state, actions, menus
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
- Conversion runs synchronously on the UI thread, so very large batches hold the
  window until they finish. Progress and per-file results are reported in the
  activity log.

## Platform roadmap

`k:okui` already routes to Forge's Windows/Choc backend, so a Windows build is
the natural next shell. The engine would need a Windows codec path replacing
`sips`. Linux still needs a backend.

## License

MIT — see `LICENSE`.
