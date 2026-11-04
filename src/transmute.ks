// src/transmute.ks — Krypton Transmute, a native macOS image converter.
//
// Pure Krypton. The window, controls and callbacks come from `k:okui`
// (Objective-K over AppKit); conversion lives in engine.ks and runs through
// macOS `sips`/ImageIO, so no C, Obj-C or Swift source is involved.

import "k:okui"
import "k:objk"
import "engine.ks"

// ── Palette ──────────────────────────────────────────────────────────
// Editor-style dark theme. Change these nine values to re-skin the app.

func cCanvas()  { emit rgb(25, 28, 34) }
func cSurface() { emit rgb(33, 37, 45) }
func cText()    { emit rgb(214, 219, 228) }
func cMuted()   { emit rgb(154, 163, 178) }
func cFaint()   { emit rgb(107, 115, 131) }
func cBlue()    { emit rgb(99, 179, 245) }
func cPurple()  { emit rgb(199, 146, 234) }
func cGreen()   { emit rgb(158, 206, 106) }
func cAmber()   { emit rgb(230, 192, 123) }
func cRed()     { emit rgb(240, 113, 120) }

// ── State ────────────────────────────────────────────────────────────

let g_win = ""
let g_list = ""
let g_log = ""
let g_status = ""
let g_progress = ""
let g_queueLabel = ""
let g_format = ""
let g_quality = ""
let g_resize = ""
let g_size = ""
let g_suffix = ""
let g_dest = ""
let g_folder = ""
let g_convert = ""
let g_reveal = ""

let g_files = ""
let g_count = 0
let g_bytes = 0
let g_lastOut = ""

// ── Small helpers ────────────────────────────────────────────────────

func logLine(line) {
    doAppend(g_log, line + "\n")
    emit "1"
}

func setStatus(line) {
    doText(g_status, line)
    emit "1"
}

func styleLabel(view, color, size) {
    doTextColor(view, color)
    doFont(view, mono(size))
    emit view
}

func styleField(view) {
    doTextColor(view, cText())
    doBackground(view, cSurface())
    doFont(view, mono(12))
    emit view
}

func refreshList() {
    doText(g_queueLabel, "IMAGES   " + g_count + "   ·   " + humanBytes(g_bytes))

    let body = ""
    if g_count == 0 {
        body = "Queue is empty.\n\nAdd a single image, or point the app at a folder.\n" +
            "Every image inside is queued and converted together."
    } else {
        body = padRight("NAME", 34) + " " + padRight("TYPE", 6) + " " +
            padRight("PIXELS", 13) + "SIZE\n" +
            "────────────────────────────────────────────────────────────\n"
        let i = 0
        while i < lineCount(g_files) {
            let p = getLine(g_files, i)
            if len(p) > 0 {
                let name = clip(baseName(p), 33)
                let kind = toUpper(extOf(baseName(p)))
                let dims = imageDimensions(p)
                let size = humanBytes(fileBytes(p))
                body = body + padRight(name, 34) + " " + padRight(kind, 6) + " " +
                    padRight(dims, 13) + size + "\n"
            }
            i += 1
        }
    }
    doTextBox(g_list, body)

    if g_count > 0 { doEnable(g_convert) } else { doDisable(g_convert) }
    emit "1"
}

func queueContains(path) {
    let hay = nl() + g_files + nl()
    let needle = nl() + path + nl()
    if contains(hay, needle) == 1 { emit 1 }
    emit 0
}

func addPath(path) {
    let p = trim(path)
    if len(p) == 0 { emit 0 }
    if queueContains(p) == 1 { emit 0 }
    if g_files == "" { g_files = p } else { g_files = g_files + "\n" + p }
    g_count = g_count + 1
    g_bytes = g_bytes + fileBytes(p)
    emit 1
}

func resetQueue() {
    g_files = ""
    g_count = 0
    g_bytes = 0
    g_lastOut = ""
    doTextBox(g_log, "")
    doProgress(g_progress, 0)
    doDisable(g_reveal)
    refreshList()
    setStatus("Queue cleared.")
    emit "1"
}

// ── Actions ──────────────────────────────────────────────────────────

func addFromPanel() {
    let p = chooseFile("Add an image")
    if len(p) == 0 { emit "1" }
    if addPath(p) == 1 {
        logLine("+ " + baseName(p))
        setStatus("Added " + baseName(p))
    } else {
        setStatus("Already in the queue.")
    }
    refreshList()
    emit "1"
}

func addFolderFromPanel() {
    let dir = chooseFolder("Add every image in a folder")
    if len(dir) == 0 { emit "1" }

    let found = scanFolder(dir)
    let added = 0
    let i = 0
    while i < lineCount(found) {
        let p = trim(getLine(found, i))
        if len(p) > 0 {
            if addPath(p) == 1 { added = added + 1 }
        }
        i += 1
    }

    refreshList()
    logLine("+ folder " + baseName(dir) + " (" + added + " images)")
    setStatus("Added " + added + " images from " + baseName(dir))
    emit "1"
}

func chooseOutputFolder() {
    let dir = chooseFolder("Choose the output folder")
    if len(dir) == 0 { emit "1" }
    doText(g_folder, dir)
    doChoose(g_dest, 1)
    setStatus("Output folder set.")
    emit "1"
}

func revealOutput() {
    if len(g_lastOut) == 0 { emit "1" }
    doReveal(g_lastOut)
    emit "1"
}

func onAdd(self, cmd, sender) { emit addFromPanel() }
func onAddFolder(self, cmd, sender) { emit addFolderFromPanel() }
func onChooseFolder(self, cmd, sender) { emit chooseOutputFolder() }
func onReveal(self, cmd, sender) { emit revealOutput() }

func onClear(self, cmd, sender) {
    emit resetQueue()
}

func onConvert(self, cmd, sender) {
    if g_count == 0 {
        alert("Krypton Transmute", "Add at least one image first.")
        emit "1"
    }

    let format = toInt(choiceIndex(g_format))
    let resizeMode = toInt(choiceIndex(g_resize))
    let destinationMode = toInt(choiceIndex(g_dest))
    let folder = trim(text(g_folder))

    if destinationMode == 1 && len(folder) == 0 {
        alert("Output folder", "Choose an output folder, or switch destination to Alongside.")
        emit "1"
    }

    let quality = toInt(trim(text(g_quality)))
    if quality < 1 { quality = 1 }
    if quality > 100 { quality = 100 }

    let sizeValue = trim(text(g_size))
    if resizeMode == 1 && toInt(sizeValue) < 1 {
        alert("Resize", "Enter the longest edge in pixels (for example 2048).")
        emit "1"
    }
    if resizeMode == 2 && toInt(sizeValue) < 1 {
        alert("Resize", "Enter a percentage between 1 and 400.")
        emit "1"
    }

    let suffix = text(g_suffix)
    let total = lineCount(g_files)

    doDisable(g_convert)
    doDisable(g_reveal)
    doProgress(g_progress, 0)
    setStatus("Converting " + g_count + " images to " + formatName(format) + "…")
    logLine("")
    logLine("Convert → " + formatName(format) + (formatIsLossy(format) == 1 ? "  quality " + quality : ""))

    let i = 0
    let converted = 0
    let failed = 0

    while i < total {
        let source = getLine(g_files, i)
        if len(source) > 0 {
            let dir = outputDirectoryFor(source, destinationMode, folder)
            if len(dir) == 0 {
                failed = failed + 1
                logLine("  fail   " + baseName(source))
            } else {
                let out = convertFile(source, format, "" + quality, resizeMode, sizeValue, dir, suffix)
                if len(out) == 0 {
                    failed = failed + 1
                    logLine("  fail   " + baseName(source))
                } else {
                    converted = converted + 1
                    g_lastOut = out
                    logLine("  ok     " + baseName(out) + "   " + humanBytes(fileBytes(out)))
                }
            }
            doProgress(g_progress, (i + 1) * 100 / total)
        }
        i += 1
    }

    doProgress(g_progress, 100)
    doEnable(g_convert)
    if len(g_lastOut) > 0 { doEnable(g_reveal) }
    setStatus("Converted " + converted + "  ·  failed " + failed + "  ·  " + formatName(format))
    logLine("Done. " + converted + " converted, " + failed + " failed.")

    if failed > 0 {
        alert("Krypton Transmute", "" + failed + " image(s) failed. Check the activity log.")
    }
    emit "1"
}

// ── Menus ────────────────────────────────────────────────────────────

func setupMenus() {
    let bar = menuBar()

    let application = menu(bar, "Krypton Transmute")
    menuSelector(application, "Quit", "q", "terminate:")

    let file = menu(bar, "File")
    menuAction(file, "Add Image…", "o", funcptr(onAdd))
    menuAction(file, "Add Folder…", "d", funcptr(onAddFolder))
    menuSeparator(file)
    menuAction(file, "Convert All", "r", funcptr(onConvert))
    menuSeparator(file)
    menuAction(file, "Clear Queue", "k", funcptr(onClear))

    let edit = menu(bar, "Edit")
    menuSelector(edit, "Cut", "x", "cut:")
    menuSelector(edit, "Copy", "c", "copy:")
    menuSelector(edit, "Paste", "v", "paste:")
    menuSelector(edit, "Select All", "a", "selectAll:")
    emit "1"
}

// ── Window ───────────────────────────────────────────────────────────

just run {
    let H = 660
    let leftX = 24
    let leftW = 592
    let rightX = 648
    let rightW = 328

    app("Krypton Transmute")
    setupMenus()

    let win = window("Krypton Transmute", 1000, H)
    g_win = win
    minSize(win, 1000, H)
    doWindowBackground(win, cCanvas())
    doTransparentTitlebar(win)
    okAppearance(win, "NSAppearanceNameDarkAqua")

    // Header (left inset clears the traffic lights)
    let titleLabel = label(win, "KRYPTON TRANSMUTE", area(88, H - 58, 460, 24))
    styleLabel(titleLabel, cBlue(), 18)

    let subtitle = label(win, "image format lab  ·  Krypton + AppKit", area(88, H - 78, 460, 16))
    styleLabel(subtitle, cFaint(), 10)

    // Queue
    g_queueLabel = label(win, "IMAGES   0   ·   0 B", area(leftX, H - 116, 420, 14))
    styleLabel(g_queueLabel, cAmber(), 10)

    g_list = textBox(win, area(leftX, 196, leftW, 330))
    doBackground(g_list, cSurface())
    doTextColor(g_list, cText())
    doFont(g_list, mono(11))
    doNoWrap(g_list)
    doEditable(g_list, 0)

    let activityLabel = label(win, "ACTIVITY", area(leftX, 168, 300, 14))
    styleLabel(activityLabel, cAmber(), 10)

    g_log = textBox(win, area(leftX, 90, leftW, 72))
    doBackground(g_log, cSurface())
    doTextColor(g_log, cMuted())
    doFont(g_log, mono(10))
    doNoWrap(g_log)
    doEditable(g_log, 0)
    doTextBox(g_log, "Ready. Add images, pick a format, convert.\n")

    g_progress = progress(win, area(leftX, 72, leftW, 8))
    doProgress(g_progress, 0)

    g_status = label(win, "Ready.", area(leftX, 40, leftW, 20))
    styleLabel(g_status, cMuted(), 11)

    // ── Export settings ──────────────────────────────────────────────
    let settingsLabel = label(win, "EXPORT SETTINGS", area(rightX, H - 116, rightW, 14))
    styleLabel(settingsLabel, cAmber(), 10)

    let formatLabel = label(win, "Format", area(rightX, H - 144, 140, 14))
    styleLabel(formatLabel, cMuted(), 11)

    g_format = choices(win, area(rightX, H - 170, rightW, 26))
    let fi = 0
    while fi < formatCount() {
        doAddChoice(g_format, formatName(fi))
        fi += 1
    }
    doChoose(g_format, 0)
    doTextColor(g_format, cText())
    doBackground(g_format, cSurface())

    let qualityLabel = label(win, "Quality  (JPEG · HEIC · AVIF)", area(rightX, H - 200, rightW, 14))
    styleLabel(qualityLabel, cMuted(), 11)
    g_quality = field(win, area(rightX, H - 226, 92, 24))
    styleField(g_quality)
    doText(g_quality, "90")
    doTip(g_quality, "1–100. Used by lossy formats only.")

    let qualityHint = label(win, "0 = smallest, 100 = best", area(rightX + 100, H - 226, 210, 24))
    styleLabel(qualityHint, cFaint(), 10)

    let resizeLabel = label(win, "Resize", area(rightX, H - 256, 140, 14))
    styleLabel(resizeLabel, cMuted(), 11)
    g_resize = choices(win, area(rightX, H - 282, rightW, 26))
    doAddChoice(g_resize, "Original")
    doAddChoice(g_resize, "Longest edge")
    doAddChoice(g_resize, "Percent")
    doChoose(g_resize, 0)
    doTextColor(g_resize, cText())
    doBackground(g_resize, cSurface())

    let sizeLabel = label(win, "Size value", area(rightX, H - 312, 140, 14))
    styleLabel(sizeLabel, cMuted(), 11)
    g_size = field(win, area(rightX, H - 338, 120, 24))
    styleField(g_size)
    doText(g_size, "2048")
    doTip(g_size, "Pixels for Longest edge, percentage for Percent.")

    let sizeHint = label(win, "px / % depending on mode", area(rightX + 128, H - 338, 200, 24))
    styleLabel(sizeHint, cFaint(), 10)

    let suffixLabel = label(win, "Filename suffix", area(rightX, H - 368, 180, 14))
    styleLabel(suffixLabel, cMuted(), 11)
    g_suffix = field(win, area(rightX, H - 394, 180, 24))
    styleField(g_suffix)
    doText(g_suffix, "-converted")
    doTip(g_suffix, "Added before the new extension.")

    let destLabel = label(win, "Destination", area(rightX, H - 420, 180, 14))
    styleLabel(destLabel, cMuted(), 11)
    g_dest = choices(win, area(rightX, H - 446, rightW, 26))
    doAddChoice(g_dest, "Alongside source")
    doAddChoice(g_dest, "Folder")
    doChoose(g_dest, 0)
    doTextColor(g_dest, cText())
    doBackground(g_dest, cSurface())

    g_folder = field(win, area(rightX, H - 484, 212, 24))
    styleField(g_folder)
    doPlaceholder(g_folder, "Output folder")

    let chooseBtn = button(win, "Choose…", area(rightX + 220, H - 485, 108, 26))
    doButtonTextColor(chooseBtn, cBlue())

    let addBtn = button(win, "Add image", area(rightX, H - 520, 150, 30))
    doButtonTextColor(addBtn, cText())
    let folderBtn = button(win, "Add folder", area(rightX + 162, H - 520, 166, 30))
    doButtonTextColor(folderBtn, cText())

    g_convert = button(win, "Convert", area(rightX, H - 562, rightW, 38))
    doButtonTextColor(g_convert, cGreen())
    doFont(g_convert, mono(13))

    g_reveal = button(win, "Reveal last output", area(rightX, H - 600, rightW, 24))
    doButtonTextColor(g_reveal, cMuted())
    doDisable(g_reveal)

    // Wiring
    doClick(addBtn, "add", funcptr(onAdd))
    doClick(folderBtn, "addFolder", funcptr(onAddFolder))
    doClick(chooseBtn, "chooseFolder", funcptr(onChooseFolder))
    doClick(g_convert, "convert", funcptr(onConvert))
    doClick(g_reveal, "reveal", funcptr(onReveal))

    refreshList()
    doShow(win)
    doRun()
}
