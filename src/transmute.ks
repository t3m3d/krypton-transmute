// src/transmute.ks — Krypton Transmute, a native macOS converter.
//
// Pure Krypton. The window, controls and callbacks come from `k:okui`
// (Objective-K over AppKit); conversion lives in engine.ks and runs through
// macOS `sips`/ImageIO for images and `textutil`/`cupsfilter` for documents,
// so no C, Obj-C or Swift source is involved.
//
// Two panels share the window: IMAGES and DOCUMENTS. Each keeps its own queue
// and settings; the header switch swaps panels by moving the inactive panel's
// views off the window. (Hiding views is deliberately avoided: AppKit throws
// "_trackingAreaHelper not allocated yet" when a control is hidden here.)

import "k:okui"
import "k:objk"
import "k:cocoa"
import "engine.ks"

// ── Palette ──────────────────────────────────────────────────────────
// Editor-style dark theme. Change these values to re-skin the app.
// The two darks are the palette purple (cPurple, hue ≈276°) taken down to
// 12% and 17% lightness, so the whole surface is purple rather than neutral.
// cTab/cTabOn are the panel-switch chips: barely above the surface, so the
// header still reads as one surface, but distinct enough to look clickable.

func cCanvas()  { emit rgb(27, 21, 38) }
func cSurface() { emit rgb(41, 32, 55) }
func cText()    { emit rgb(214, 219, 228) }
func cMuted()   { emit rgb(154, 163, 178) }
func cFaint()   { emit rgb(107, 115, 131) }
func cBlue()    { emit rgb(99, 179, 245) }
func cPurple()  { emit rgb(199, 146, 234) }
func cGreen()   { emit rgb(158, 206, 106) }
func cAmber()   { emit rgb(230, 192, 123) }
func cRed()     { emit rgb(240, 113, 120) }
func cTab()     { emit rgb(46, 37, 61) }
func cTabOn()   { emit rgb(58, 47, 76) }
func cControl() { emit rgb(60, 49, 79) }

// ── State ────────────────────────────────────────────────────────────

let g_win = ""
let g_subtitle = ""
let g_queueLabel = ""
let g_list = ""
let g_log = ""
let g_status = ""
let g_progress = ""

let g_btnImages = ""
let g_btnDocs = ""
let g_btnAudio = ""
let g_btnTools = ""
let g_mode = "images"

// Each panel's views live in an NSMutableArray (view handles are binary and
// cannot survive newline-joined strings); their home frames are safe ASCII and
// stay in a matching newline-separated list.
let g_imgViews = ""
let g_imgRects = ""
let g_docViews = ""
let g_docRects = ""
let g_audioViews = ""
let g_audioRects = ""
let g_toolViews = ""
let g_toolRects = ""

// Image panel settings
let g_format = ""
let g_quality = ""
let g_resize = ""
let g_size = ""
let g_suffix = ""
let g_dest = ""
let g_folder = ""
let g_convert = ""
let g_icons = ""
let g_reveal = ""

// Document panel settings
let g_docFormat = ""
let g_docSuffix = ""
let g_docDest = ""
let g_docFolder = ""
let g_docConvert = ""
let g_docReveal = ""

// Audio panel settings
let g_audioFormat = ""
let g_audioBitrate = ""
let g_audioSuffix = ""
let g_audioDest = ""
let g_audioFolder = ""
let g_audioConvert = ""
let g_audioReveal = ""

// Toolbox panel settings
let g_toolFormat = ""
let g_toolHeight = ""
let g_toolTitle = ""
let g_toolSuffix = ""
let g_toolDest = ""
let g_toolFolder = ""
let g_toolConvert = ""
let g_toolReveal = ""
let g_toolHint = ""

// Image queue
let g_files = ""
let g_count = 0
let g_bytes = 0
let g_lastOut = ""

// Document queue
let g_docs = ""
let g_docCount = 0
let g_docBytes = 0
let g_lastDocOut = ""

// Audio queue
let g_audioFiles = ""
let g_audioCount = 0
let g_audioBytes = 0
let g_lastAudioOut = ""

// Toolbox queue
let g_toolFiles = ""
let g_toolCount = 0
let g_toolBytes = 0
let g_lastToolOut = ""

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

// Controls are painted by their layer instead of AppKit's grey bezel, so the
// whole app uses the palette. Chips are borderless; combos keep their arrow.
func paintChip(btn, tone) {
    msg_1(btn, "setBordered:", 0)
    msg_1(btn, "setWantsLayer:", 1)
    let lay = msg(btn, "layer")
    msg_d1(lay, "setCornerRadius:", 7)
    msg_1(lay, "setBackgroundColor:", msg(tone, "CGColor"))
    emit btn
}

func styleChip(btn) { emit paintChip(btn, cControl()) }

// Borderless layer-backed NSButtons stop drawing their title entirely when
// AppKit disables them. Keep the button enabled and dim the whole chip
// instead; every action already guards its own empty-queue case.
func setActionState(btn, ready) {
    msg_1(btn, "setEnabled:", 1)
    if toInt(ready) == 1 {
        msg_d1(btn, "setAlphaValue:", 1.0)
    } else {
        msg_d1(btn, "setAlphaValue:", 0.72)
    }
    emit "1"
}

func styleTab(btn) {
    doFont(btn, mono(11))
    emit paintChip(btn, cTab())
}

func styleChoice(combo) {
    doTextColor(combo, cText())
    msg_1(combo, "setWantsLayer:", 1)
    let lay = msg(combo, "layer")
    msg_d1(lay, "setCornerRadius:", 6)
    msg_1(lay, "setBackgroundColor:", msg(cControl(), "CGColor"))
    msg_1(combo, "setDrawsBackground:", 0)
    msg_1(combo, "setBordered:", 0)
    msg_1(combo, "setBezeled:", 0)
    emit combo
}

func tabTone(btn, lit) {
    let c = cTab()
    if lit == 1 { c = cTabOn() }
    msg_1(msg(btn, "layer"), "setBackgroundColor:", msg(c, "CGColor"))
    emit "1"
}

// Panel registration: remember each view with the frame it lives at, so the
// panel can be parked off-window and brought back exactly where it was.
func regImg(view, r) {
    cocoaArrayAdd(g_imgViews, view)
    if g_imgRects == "" { g_imgRects = r } else { g_imgRects = g_imgRects + "\n" + r }
    emit view
}

func regDoc(view, r) {
    cocoaArrayAdd(g_docViews, view)
    if g_docRects == "" { g_docRects = r } else { g_docRects = g_docRects + "\n" + r }
    emit view
}

func regAudio(view, r) {
    cocoaArrayAdd(g_audioViews, view)
    if g_audioRects == "" { g_audioRects = r } else { g_audioRects = g_audioRects + "\n" + r }
    emit view
}

func regTool(view, r) {
    cocoaArrayAdd(g_toolViews, view)
    if g_toolRects == "" { g_toolRects = r } else { g_toolRects = g_toolRects + "\n" + r }
    emit view
}

// Autoresizing masks: 1 = left margin flexible (hug right edge), 4 = right
// margin flexible (stay at left), 8 = bottom margin flexible (stay at top),
// 16 = height sizable, 32 = top margin flexible (stay at bottom).
func anchor(view, mask) {
    msg_1(view, "setAutoresizingMask:", toInt(mask))
    emit view
}

func showGroup(views, rects, visible) {
    let total = toInt(cocoaArrayCount(views))
    let i = 0
    while i < total {
        let view = cocoaArrayGet(views, i)
        let r = getLine(rects, i)
        if len(view) > 0 {
            if toInt(visible) == 1 {
                doFrame(view, r)
            } else {
                doFrame(view, move(r, -5000, -5000))
            }
        }
        i += 1
    }
    emit "1"
}

// Panel-aware control builders.

func imgLabel(win, text, r, color, size) {
    let v = label(win, text, r)
    styleLabel(v, color, size)
    emit regImg(v, r)
}

func docLabel(win, text, r, color, size) {
    let v = label(win, text, r)
    styleLabel(v, color, size)
    emit regDoc(v, r)
}

func imgField(win, r) {
    emit regImg(styleField(field(win, r)), r)
}

func docField(win, r) {
    emit regDoc(styleField(field(win, r)), r)
}

func imgChoices(win, r) {
    emit regImg(styleChoice(choices(win, r)), r)
}

func docChoices(win, r) {
    emit regDoc(styleChoice(choices(win, r)), r)
}

func imgButton(win, text, r) {
    emit regImg(styleChip(button(win, text, r)), r)
}

func docButton(win, text, r) {
    emit regDoc(styleChip(button(win, text, r)), r)
}

func audioLabel(win, text, r, color, size) {
    let v = label(win, text, r)
    styleLabel(v, color, size)
    emit regAudio(v, r)
}

func audioField(win, r) {
    emit regAudio(styleField(field(win, r)), r)
}

func audioChoices(win, r) {
    emit regAudio(styleChoice(choices(win, r)), r)
}

func audioButton(win, text, r) {
    emit regAudio(styleChip(button(win, text, r)), r)
}

func toolLabel(win, text, r, color, size) {
    let v = label(win, text, r)
    styleLabel(v, color, size)
    emit regTool(v, r)
}

func toolField(win, r) {
    emit regTool(styleField(field(win, r)), r)
}

func toolChoices(win, r) {
    emit regTool(styleChoice(choices(win, r)), r)
}

func toolButton(win, text, r) {
    emit regTool(styleChip(button(win, text, r)), r)
}

// ── Queue rendering ──────────────────────────────────────────────────

func imageTableBody() {
    if g_count == 0 {
        emit "Queue is empty.\n\nAdd a single image, or point the app at a folder.\n" +
            "Every image inside is queued and converted together."
    }
    let body = padRight("NAME", 34) + " " + padRight("TYPE", 6) + " " +
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
    emit body
}

func documentTableBody() {
    if g_docCount == 0 {
        emit "No documents queued.\n\nAdd a document, or point the app at a folder.\n" +
            "Reads txt · md · rtf · rtfd · html · doc · docx · odt · wordml · webarchive."
    }
    let body = padRight("NAME", 34) + " " + padRight("KIND", 12) + "SIZE\n" +
        "────────────────────────────────────────────────────────────\n"
    let i = 0
    while i < lineCount(g_docs) {
        let p = getLine(g_docs, i)
        if len(p) > 0 {
            let name = clip(baseName(p), 33)
            let kind = toUpper(extOf(baseName(p)))
            let size = humanBytes(fileBytes(p))
            body = body + padRight(name, 34) + " " + padRight(kind, 12) + size + "\n"
        }
        i += 1
    }
    emit body
}

func renderImageList() {
    doText(g_queueLabel, "IMAGES   " + g_count + "   ·   " + humanBytes(g_bytes))
    doTextBox(g_list, imageTableBody())
    if g_count > 0 {
        setActionState(g_convert, 1)
        setActionState(g_icons, 1)
    } else {
        setActionState(g_convert, 0)
        setActionState(g_icons, 0)
    }
    emit "1"
}

func renderDocList() {
    doText(g_queueLabel, "DOCUMENTS   " + g_docCount + "   ·   " + humanBytes(g_docBytes))
    doTextBox(g_list, documentTableBody())
    if g_docCount > 0 {
        setActionState(g_docConvert, 1)
    } else {
        setActionState(g_docConvert, 0)
    }
    emit "1"
}

func audioTableBody() {
    if g_audioCount == 0 {
        emit "No audio queued.\n\nAdd a track, or point the app at a folder.\n" +
            "Reads aiff · wav · m4a · caf · flac · mp3; writes six formats."
    }
    let body = padRight("NAME", 32) + " " + padRight("TYPE", 6) + " " +
        padRight("LENGTH", 8) + " " + padRight("FORMAT", 20) + "SIZE\n" +
        "────────────────────────────────────────────────────────────\n"
    let i = 0
    while i < lineCount(g_audioFiles) {
        let p = getLine(g_audioFiles, i)
        if len(p) > 0 {
            let name = clip(baseName(p), 31)
            let kind = toUpper(extOf(baseName(p)))
            let length = audioLength(p)
            let info = clip(audioInfo(p), 19)
            let size = humanBytes(fileBytes(p))
            body = body + padRight(name, 32) + " " + padRight(kind, 6) + " " +
                padRight(length, 8) + " " + padRight(info, 20) + size + "\n"
        }
        i += 1
    }
    emit body
}

func renderAudioList() {
    doText(g_queueLabel, "AUDIO   " + g_audioCount + "   ·   " + humanBytes(g_audioBytes))
    doTextBox(g_list, audioTableBody())
    if g_audioCount > 0 {
        setActionState(g_audioConvert, 1)
    } else {
        setActionState(g_audioConvert, 0)
    }
    emit "1"
}

func toolTableBody() {
    if g_toolCount == 0 {
        emit "Nothing queued.\n\nAdd files, then pick what they should become.\n" +
            "Video goes through avconvert; the other seven families use the\n" +
            "bundled standard-library parsers."
    }
    let body = padRight("NAME", 30) + " " + padRight("KIND", 6) + " " +
        padRight("DETAIL", 22) + "SIZE\n" +
        "────────────────────────────────────────────────────────────\n"
    let i = 0
    while i < lineCount(g_toolFiles) {
        let p = getLine(g_toolFiles, i)
        if len(p) > 0 {
            let name = clip(baseName(p), 29)
            let kind = toUpper(extOf(baseName(p)))
            let cat = toInt(toolCategoryForPath(p))
            let detail = "unsupported"
            if cat >= 0 {
                detail = clip(toolInfo(cat, p), 21)
                if len(detail) == 0 { detail = toolCategoryName(cat) }
            }
            let size = humanBytes(fileBytes(p))
            body = body + padRight(name, 30) + " " + padRight(kind, 6) + " " +
                padRight(detail, 22) + size + "\n"
        }
        i += 1
    }
    emit body
}

func renderToolList() {
    doText(g_queueLabel, "TOOLBOX   " + g_toolCount + "   ·   " + humanBytes(g_toolBytes))
    doTextBox(g_list, toolTableBody())
    if g_toolCount > 0 {
        setActionState(g_toolConvert, 1)
    } else {
        setActionState(g_toolConvert, 0)
    }
    emit "1"
}

func refreshView() {
    if g_mode == "docs" {
        renderDocList()
    }
    if g_mode == "audio" {
        renderAudioList()
    }
    if g_mode == "tools" {
        renderToolList()
    }
    if g_mode == "images" {
        renderImageList()
    }
    emit "1"
}

// ── Mode switching ───────────────────────────────────────────────────

func setMode(mode) {
    g_mode = mode

    let images = 0
    let docs = 0
    let audio = 0
    let tools = 0
    if mode == "images" { images = 1 }
    if mode == "docs" { docs = 1 }
    if mode == "audio" { audio = 1 }
    if mode == "tools" { tools = 1 }

    showGroup(g_imgViews, g_imgRects, images)
    showGroup(g_docViews, g_docRects, docs)
    showGroup(g_audioViews, g_audioRects, audio)
    showGroup(g_toolViews, g_toolRects, tools)

    if images == 1 {
        doText(g_subtitle, "image format lab  ·  Krypton + AppKit")
        doButtonTextColor(g_btnImages, cBlue())
        doButtonTextColor(g_btnDocs, cMuted())
        doButtonTextColor(g_btnAudio, cMuted())
        doButtonTextColor(g_btnTools, cMuted())
        renderImageList()
        setStatus("Images  ·  " + g_count + " queued")
    }
    if docs == 1 {
        doText(g_subtitle, "document lab  ·  Krypton + textutil")
        doButtonTextColor(g_btnDocs, cBlue())
        doButtonTextColor(g_btnImages, cMuted())
        doButtonTextColor(g_btnAudio, cMuted())
        doButtonTextColor(g_btnTools, cMuted())
        renderDocList()
        setStatus("Documents  ·  " + g_docCount + " queued")
    }
    if audio == 1 {
        doText(g_subtitle, "audio lab  ·  Krypton + CoreAudio")
        doButtonTextColor(g_btnAudio, cBlue())
        doButtonTextColor(g_btnImages, cMuted())
        doButtonTextColor(g_btnDocs, cMuted())
        doButtonTextColor(g_btnTools, cMuted())
        renderAudioList()
        setStatus("Audio  ·  " + g_audioCount + " queued")
    }
    if tools == 1 {
        doText(g_subtitle, "toolbox  ·  avconvert + stdlib parsers")
        doButtonTextColor(g_btnTools, cBlue())
        doButtonTextColor(g_btnImages, cMuted())
        doButtonTextColor(g_btnDocs, cMuted())
        doButtonTextColor(g_btnAudio, cMuted())
        renderToolList()
        setStatus("Toolbox  ·  " + g_toolCount + " queued")
    }

    tabTone(g_btnImages, images)
    tabTone(g_btnDocs, docs)
    tabTone(g_btnAudio, audio)
    tabTone(g_btnTools, tools)
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

func docQueueContains(path) {
    let hay = nl() + g_docs + nl()
    let needle = nl() + path + nl()
    if contains(hay, needle) == 1 { emit 1 }
    emit 0
}

func addDocPath(path) {
    let p = trim(path)
    if len(p) == 0 { emit 0 }
    if docQueueContains(p) == 1 { emit 0 }
    if g_docs == "" { g_docs = p } else { g_docs = g_docs + "\n" + p }
    g_docCount = g_docCount + 1
    g_docBytes = g_docBytes + fileBytes(p)
    emit 1
}

func audioQueueContains(path) {
    let hay = nl() + g_audioFiles + nl()
    let needle = nl() + path + nl()
    if contains(hay, needle) == 1 { emit 1 }
    emit 0
}

func addAudioPath(path) {
    let p = trim(path)
    if len(p) == 0 { emit 0 }
    if audioQueueContains(p) == 1 { emit 0 }
    if g_audioFiles == "" { g_audioFiles = p } else { g_audioFiles = g_audioFiles + "\n" + p }
    g_audioCount = g_audioCount + 1
    g_audioBytes = g_audioBytes + fileBytes(p)
    emit 1
}

func toolQueueContains(path) {
    let hay = nl() + g_toolFiles + nl()
    let needle = nl() + path + nl()
    if contains(hay, needle) == 1 { emit 1 }
    emit 0
}

func addToolPath(path) {
    let p = trim(path)
    if len(p) == 0 { emit 0 }
    if toolIsAny(p) == 0 { emit 0 }
    if toolQueueContains(p) == 1 { emit 0 }
    if g_toolFiles == "" { g_toolFiles = p } else { g_toolFiles = g_toolFiles + "\n" + p }
    g_toolCount = g_toolCount + 1
    g_toolBytes = g_toolBytes + fileBytes(p)
    emit 1
}

func resetQueue() {
    if g_mode == "tools" {
        g_toolFiles = ""
        g_toolCount = 0
        g_toolBytes = 0
        g_lastToolOut = ""
        setActionState(g_toolReveal, 0)
        setStatus("Toolbox queue cleared.")
    }
    if g_mode == "audio" {
        g_audioFiles = ""
        g_audioCount = 0
        g_audioBytes = 0
        g_lastAudioOut = ""
        setActionState(g_audioReveal, 0)
        setStatus("Audio queue cleared.")
    }
    if g_mode == "docs" {
        g_docs = ""
        g_docCount = 0
        g_docBytes = 0
        g_lastDocOut = ""
        setActionState(g_docReveal, 0)
        setStatus("Document queue cleared.")
    }
    if g_mode == "images" {
        g_files = ""
        g_count = 0
        g_bytes = 0
        g_lastOut = ""
        setActionState(g_reveal, 0)
        setStatus("Image queue cleared.")
    }
    doTextBox(g_log, "")
    doProgress(g_progress, 0)
    refreshView()
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
    refreshView()
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

    refreshView()
    logLine("+ folder " + baseName(dir) + " (" + added + " images)")
    setStatus("Added " + added + " images from " + baseName(dir))
    emit "1"
}

func addDocumentFromPanel() {
    let p = chooseFile("Add a document")
    if len(p) == 0 { emit "1" }
    if isDocument(p) == 0 {
        alert("Krypton Transmute", baseName(p) + " is not a document this app can read.")
        emit "1"
    }
    if addDocPath(p) == 1 {
        logLine("+ " + baseName(p))
        setStatus("Added " + baseName(p))
    } else {
        setStatus("Already in the queue.")
    }
    renderDocList()
    emit "1"
}

func addDocFolderFromPanel() {
    let dir = chooseFolder("Add every document in a folder")
    if len(dir) == 0 { emit "1" }

    let found = scanDocuments(dir)
    let added = 0
    let i = 0
    while i < lineCount(found) {
        let p = trim(getLine(found, i))
        if len(p) > 0 {
            if addDocPath(p) == 1 { added = added + 1 }
        }
        i += 1
    }

    renderDocList()
    logLine("+ folder " + baseName(dir) + " (" + added + " documents)")
    setStatus("Added " + added + " documents from " + baseName(dir))
    emit "1"
}

func addAudioFromPanel() {
    let p = chooseFile("Add an audio file")
    if len(p) == 0 { emit "1" }
    if isAudio(p) == 0 {
        alert("Krypton Transmute", baseName(p) + " is not an audio file this app can read.")
        emit "1"
    }
    if addAudioPath(p) == 1 {
        logLine("+ " + baseName(p))
        setStatus("Added " + baseName(p))
    } else {
        setStatus("Already in the queue.")
    }
    renderAudioList()
    emit "1"
}

func addAudioFolderFromPanel() {
    let dir = chooseFolder("Add every track in a folder")
    if len(dir) == 0 { emit "1" }

    let found = scanAudio(dir)
    let added = 0
    let i = 0
    while i < lineCount(found) {
        let p = trim(getLine(found, i))
        if len(p) > 0 {
            if addAudioPath(p) == 1 { added = added + 1 }
        }
        i += 1
    }

    renderAudioList()
    logLine("+ folder " + baseName(dir) + " (" + added + " tracks)")
    setStatus("Added " + added + " tracks from " + baseName(dir))
    emit "1"
}

func chooseAudioFolder() {
    let dir = chooseFolder("Choose the audio output folder")
    if len(dir) == 0 { emit "1" }
    doText(g_audioFolder, dir)
    doChoose(g_audioDest, 1)
    setStatus("Audio output folder set.")
    emit "1"
}

func revealAudioOutput() {
    if len(g_lastAudioOut) == 0 { emit "1" }
    doReveal(g_lastAudioOut)
    emit "1"
}

func addToolFromPanel() {
    let p = chooseFile("Add a file for the toolbox")
    if len(p) == 0 { emit "1" }
    if toolIsAny(p) == 0 {
        alert("Krypton Transmute", baseName(p) + " is not a format the toolbox reads.")
        emit "1"
    }
    if addToolPath(p) == 1 {
        logLine("+ " + baseName(p))
        setStatus("Added " + baseName(p))
    } else {
        setStatus("Already in the queue.")
    }
    renderToolList()
    emit "1"
}

func addToolFolderFromPanel() {
    let dir = chooseFolder("Add every toolbox file in a folder")
    if len(dir) == 0 { emit "1" }

    let found = ""
    let c = 0
    while c < toolCategoryCount() {
        let chunk = toolScan(c, dir)
        if len(trim(chunk)) > 0 {
            if len(found) == 0 { found = chunk } else { found = found + "\n" + chunk }
        }
        c += 1
    }

    let added = 0
    let i = 0
    while i < lineCount(found) {
        let p = trim(getLine(found, i))
        if len(p) > 0 {
            if addToolPath(p) == 1 { added = added + 1 }
        }
        i += 1
    }

    renderToolList()
    logLine("+ folder " + baseName(dir) + " (" + added + " files)")
    setStatus("Added " + added + " files from " + baseName(dir))
    emit "1"
}

func chooseToolFolder() {
    let dir = chooseFolder("Choose the toolbox output folder")
    if len(dir) == 0 { emit "1" }
    doText(g_toolFolder, dir)
    doChoose(g_toolDest, 1)
    setStatus("Toolbox output folder set.")
    emit "1"
}

func revealToolOutput() {
    if len(g_lastToolOut) == 0 { emit "1" }
    doReveal(g_lastToolOut)
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

func chooseDocFolder() {
    let dir = chooseFolder("Choose the document output folder")
    if len(dir) == 0 { emit "1" }
    doText(g_docFolder, dir)
    doChoose(g_docDest, 1)
    setStatus("Document output folder set.")
    emit "1"
}

func revealOutput() {
    if len(g_lastOut) == 0 { emit "1" }
    doReveal(g_lastOut)
    emit "1"
}

func revealDocOutput() {
    if len(g_lastDocOut) == 0 { emit "1" }
    doReveal(g_lastDocOut)
    emit "1"
}

func onAdd(self, cmd, sender) { emit addFromPanel() }
func onAddFolder(self, cmd, sender) {
    if g_mode == "audio" { emit addAudioFolderFromPanel() }
    if g_mode == "docs" { emit addDocFolderFromPanel() }
    emit addFolderFromPanel()
}
func onAddDoc(self, cmd, sender) { emit addDocumentFromPanel() }
func onAddDocFolder(self, cmd, sender) { emit addDocFolderFromPanel() }
func onAddAudio(self, cmd, sender) { emit addAudioFromPanel() }
func onAddAudioFolder(self, cmd, sender) { emit addAudioFolderFromPanel() }
func onChooseAudioFolder(self, cmd, sender) { emit chooseAudioFolder() }
func onRevealAudio(self, cmd, sender) { emit revealAudioOutput() }
func onAddTool(self, cmd, sender) { emit addToolFromPanel() }
func onAddToolFolder(self, cmd, sender) { emit addToolFolderFromPanel() }
func onChooseToolFolder(self, cmd, sender) { emit chooseToolFolder() }
func onRevealTool(self, cmd, sender) { emit revealToolOutput() }
func onChooseFolder(self, cmd, sender) { emit chooseOutputFolder() }
func onChooseDocFolder(self, cmd, sender) { emit chooseDocFolder() }
func onReveal(self, cmd, sender) { emit revealOutput() }
func onRevealDoc(self, cmd, sender) { emit revealDocOutput() }
func onModeImages(self, cmd, sender) { emit setMode("images") }
func onModeDocs(self, cmd, sender) { emit setMode("docs") }
func onModeAudio(self, cmd, sender) { emit setMode("audio") }
func onModeTools(self, cmd, sender) { emit setMode("tools") }

func onClear(self, cmd, sender) {
    emit resetQueue()
}

func onBuildIcons(self, cmd, sender) {
    if g_count == 0 {
        alert("Krypton Transmute", "Add at least one square-ish image first.")
        emit "1"
    }

    setMode("images")

    let destinationMode = toInt(choiceIndex(g_dest))
    let folder = trim(text(g_folder))
    if destinationMode == 1 && len(folder) == 0 {
        alert("Output folder", "Choose an output folder, or switch destination to Alongside.")
        emit "1"
    }

    let suffix = text(g_suffix)
    let total = lineCount(g_files)

    setActionState(g_icons, 0)
    setActionState(g_reveal, 0)
    doProgress(g_progress, 0)
    setStatus("Building app icons…")
    logLine("")
    logLine("App icons → macOS .icns + Windows .ico")

    let i = 0
    let made = 0
    let failed = 0

    while i < total {
        let source = getLine(g_files, i)
        if len(source) > 0 {
            let dir = outputDirectoryFor(source, destinationMode, folder)
            if len(dir) == 0 {
                failed = failed + 1
                logLine("  fail   " + baseName(source))
            } else {
                let icns = makeIcns(source, dir, suffix)
                let ico = makeIco(source, dir, suffix)
                if len(icns) == 0 && len(ico) == 0 {
                    failed = failed + 1
                    logLine("  fail   " + baseName(source))
                } else {
                    made = made + 1
                    if len(icns) > 0 {
                        g_lastOut = icns
                        logLine("  icns   " + baseName(icns) + "   " + humanBytes(fileBytes(icns)))
                    }
                    if len(ico) > 0 {
                        g_lastOut = ico
                        logLine("  ico    " + baseName(ico) + "   " + humanBytes(fileBytes(ico)))
                    }
                }
            }
            doProgress(g_progress, (i + 1) * 100 / total)
        }
        i += 1
    }

    doProgress(g_progress, 100)
    setActionState(g_icons, 1)
    if len(g_lastOut) > 0 { setActionState(g_reveal, 1) }
    setStatus("Icon sets " + made + "  ·  failed " + failed)
    logLine("Done. " + made + " icon sets, " + failed + " failed.")

    if failed > 0 {
        alert("Krypton Transmute", "" + failed + " image(s) could not be turned into icons.")
    }
    emit "1"
}

func onConvert(self, cmd, sender) {
    if g_count == 0 {
        alert("Krypton Transmute", "Add at least one image first.")
        emit "1"
    }

    setMode("images")

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

    setActionState(g_convert, 0)
    setActionState(g_reveal, 0)
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
    setActionState(g_convert, 1)
    if len(g_lastOut) > 0 { setActionState(g_reveal, 1) }
    setStatus("Converted " + converted + "  ·  failed " + failed + "  ·  " + formatName(format))
    logLine("Done. " + converted + " converted, " + failed + " failed.")

    if failed > 0 {
        alert("Krypton Transmute", "" + failed + " image(s) failed. Check the activity log.")
    }
    emit "1"
}

func onConvertDocs(self, cmd, sender) {
    if g_docCount == 0 {
        alert("Krypton Transmute", "Add at least one document first.")
        emit "1"
    }

    setMode("docs")

    let format = toInt(choiceIndex(g_docFormat))
    let destinationMode = toInt(choiceIndex(g_docDest))
    let folder = trim(text(g_docFolder))

    if destinationMode == 1 && len(folder) == 0 {
        alert("Output folder", "Choose an output folder, or switch destination to Alongside.")
        emit "1"
    }

    let suffix = text(g_docSuffix)
    let total = lineCount(g_docs)

    setActionState(g_docConvert, 0)
    setActionState(g_docReveal, 0)
    doProgress(g_progress, 0)
    setStatus("Converting " + g_docCount + " documents to " + docFormatName(format) + "…")
    logLine("")
    logLine("Documents → " + docFormatName(format) +
        (docFormatIsPdf(format) == 1 ? "  (text-only PDF)" : ""))

    let i = 0
    let converted = 0
    let failed = 0

    while i < total {
        let source = getLine(g_docs, i)
        if len(source) > 0 {
            let dir = outputDirectoryFor(source, destinationMode, folder)
            if len(dir) == 0 {
                failed = failed + 1
                logLine("  fail   " + baseName(source))
            } else {
                let out = convertDocument(source, format, dir, suffix)
                if len(out) == 0 {
                    failed = failed + 1
                    logLine("  fail   " + baseName(source))
                } else {
                    converted = converted + 1
                    g_lastDocOut = out
                    logLine("  ok     " + baseName(out) + "   " + humanBytes(fileBytes(out)))
                }
            }
            doProgress(g_progress, (i + 1) * 100 / total)
        }
        i += 1
    }

    doProgress(g_progress, 100)
    setActionState(g_docConvert, 1)
    if len(g_lastDocOut) > 0 { setActionState(g_docReveal, 1) }
    setStatus("Converted " + converted + "  ·  failed " + failed + "  ·  " + docFormatName(format))
    logLine("Done. " + converted + " converted, " + failed + " failed.")

    if failed > 0 {
        alert("Krypton Transmute", "" + failed + " document(s) failed. Check the activity log.")
    }
    emit "1"
}

func onConvertAudio(self, cmd, sender) {
    if g_audioCount == 0 {
        alert("Krypton Transmute", "Add at least one audio file first.")
        emit "1"
    }

    setMode("audio")

    let format = toInt(choiceIndex(g_audioFormat))
    let destinationMode = toInt(choiceIndex(g_audioDest))
    let folder = trim(text(g_audioFolder))

    if destinationMode == 1 && len(folder) == 0 {
        alert("Output folder", "Choose an output folder, or switch destination to Alongside.")
        emit "1"
    }

    let bitrate = toInt(trim(text(g_audioBitrate)))
    if bitrate < 8 { bitrate = 8 }
    if bitrate > 512 { bitrate = 512 }

    let suffix = text(g_audioSuffix)
    let total = lineCount(g_audioFiles)

    setActionState(g_audioConvert, 0)
    setActionState(g_audioReveal, 0)
    doProgress(g_progress, 0)
    setStatus("Converting " + g_audioCount + " tracks to " + audioFormatName(format) + "…")
    logLine("")
    logLine("Audio → " + audioFormatName(format) +
        (audioFormatIsLossy(format) == 1 ? "  " + bitrate + " kbps" : "  lossless"))

    let i = 0
    let converted = 0
    let failed = 0

    while i < total {
        let source = getLine(g_audioFiles, i)
        if len(source) > 0 {
            let dir = outputDirectoryFor(source, destinationMode, folder)
            if len(dir) == 0 {
                failed = failed + 1
                logLine("  fail   " + baseName(source))
            } else {
                let out = convertAudio(source, format, "" + bitrate, dir, suffix)
                if len(out) == 0 {
                    failed = failed + 1
                    logLine("  fail   " + baseName(source))
                } else {
                    converted = converted + 1
                    g_lastAudioOut = out
                    logLine("  ok     " + baseName(out) + "   " + humanBytes(fileBytes(out)))
                }
            }
            doProgress(g_progress, (i + 1) * 100 / total)
        }
        i += 1
    }

    doProgress(g_progress, 100)
    setActionState(g_audioConvert, 1)
    if len(g_lastAudioOut) > 0 { setActionState(g_audioReveal, 1) }
    setStatus("Converted " + converted + "  ·  failed " + failed + "  ·  " + audioFormatName(format))
    logLine("Done. " + converted + " converted, " + failed + " failed.")

    if failed > 0 {
        alert("Krypton Transmute", "" + failed + " track(s) failed. Check the activity log.")
    }
    emit "1"
}

func onConvertTools(self, cmd, sender) {
    if g_toolCount == 0 {
        alert("Krypton Transmute", "Add at least one toolbox file first.")
        emit "1"
    }

    setMode("tools")

    let global = toInt(choiceIndex(g_toolFormat))
    let cat = toInt(toolCategoryForFormat(global))
    let fmt = toInt(toolLocalIndex(global))
    let destinationMode = toInt(choiceIndex(g_toolDest))
    let folder = trim(text(g_toolFolder))

    if destinationMode == 1 && len(folder) == 0 {
        alert("Output folder", "Choose an output folder, or switch destination to Alongside.")
        emit "1"
    }

    if toolboxReady() == 0 && cat != 0 {
        alert("Toolbox back end missing",
            "Run scripts/build-app.sh so the parser helper is installed.")
        emit "1"
    }

    let option = ""
    if cat == 0 { option = trim(text(g_toolHeight)) }
    if cat == 4 { option = trim(text(g_toolTitle)) }

    let suffix = text(g_toolSuffix)
    let total = lineCount(g_toolFiles)

    setActionState(g_toolConvert, 0)
    setActionState(g_toolReveal, 0)
    doProgress(g_progress, 0)
    setStatus("Converting to " + toolFormatGlobalName(global) + "…")
    logLine("")
    logLine("Toolbox → " + toolFormatGlobalName(global))

    let i = 0
    let converted = 0
    let skipped = 0
    let failed = 0

    while i < total {
        let source = getLine(g_toolFiles, i)
        if len(source) > 0 {
            let dir = outputDirectoryFor(source, destinationMode, folder)
            if len(dir) == 0 {
                failed = failed + 1
                logLine("  fail   " + baseName(source))
            } else {
                if toolAccepts(cat, source) == 0 {
                    skipped = skipped + 1
                    logLine("  skip   " + baseName(source) + "   (other family)")
                } else {
                    let out = toolConvert(cat, source, fmt, option, dir, suffix)
                    if len(out) == 0 {
                        failed = failed + 1
                        logLine("  fail   " + baseName(source))
                    } else {
                        converted = converted + 1
                        g_lastToolOut = out
                        logLine("  ok     " + baseName(out) + "   " + humanBytes(fileBytes(out)))
                    }
                }
            }
            doProgress(g_progress, (i + 1) * 100 / total)
        }
        i += 1
    }

    doProgress(g_progress, 100)
    setActionState(g_toolConvert, 1)
    if len(g_lastToolOut) > 0 { setActionState(g_toolReveal, 1) }
    setStatus("Converted " + converted + "  ·  skipped " + skipped + "  ·  failed " + failed)
    logLine("Done. " + converted + " converted, " + skipped + " skipped, " + failed + " failed.")

    if failed > 0 {
        alert("Krypton Transmute", "" + failed + " file(s) failed. Check the activity log.")
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
    menuAction(file, "Add Document…", "t", funcptr(onAddDoc))
    menuAction(file, "Add Audio…", "u", funcptr(onAddAudio))
    menuAction(file, "Add to Toolbox…", "b", funcptr(onAddTool))
    menuAction(file, "Add Folder…", "d", funcptr(onAddFolder))
    menuSeparator(file)
    menuAction(file, "Convert All Images", "r", funcptr(onConvert))
    menuAction(file, "Convert Documents", "y", funcptr(onConvertDocs))
    menuAction(file, "Convert Audio", "l", funcptr(onConvertAudio))
    menuAction(file, "Convert Toolbox", "j", funcptr(onConvertTools))
    menuAction(file, "Build App Icons", "i", funcptr(onBuildIcons))
    menuSeparator(file)
    menuAction(file, "Clear Queue", "k", funcptr(onClear))

    let view = menu(bar, "View")
    menuAction(view, "Image Panel", "1", funcptr(onModeImages))
    menuAction(view, "Document Panel", "2", funcptr(onModeDocs))
    menuAction(view, "Audio Panel", "3", funcptr(onModeAudio))
    menuAction(view, "Toolbox Panel", "4", funcptr(onModeTools))

    let edit = menu(bar, "Edit")
    menuSelector(edit, "Cut", "x", "cut:")
    menuSelector(edit, "Copy", "c", "copy:")
    menuSelector(edit, "Paste", "v", "paste:")
    menuSelector(edit, "Select All", "a", "selectAll:")
    emit "1"
}

// ── Window ───────────────────────────────────────────────────────────

just run {
    let W = 1060
    let H = 760
    let leftX = 24
    let leftW = 652
    let rightW = 328
    let rightX = W - 352

    app("Krypton Transmute")
    setupMenus()
    g_imgViews = cocoaArray()
    g_docViews = cocoaArray()
    g_audioViews = cocoaArray()
    g_toolViews = cocoaArray()

    // The window is not pinned to a size. It opens at the layout's natural
    // content size the first time, then macOS remembers whatever size and
    // position the user gives it (setFrameAutosaveName).
    let win = window("Krypton Transmute", W, H)
    g_win = win
    // First launch has no saved frame, so put the window in the middle of the
    // screen instead of AppKit's bottom-left default. After that macOS restores
    // whatever size and position the window was last left at.
    if len(trim(setting("NSWindow Frame KryptonTransmuteMainWindow"))) == 0 {
        msg(win, "center")
    }
    msg_1(win, "setFrameAutosaveName:", nsString("KryptonTransmuteMainWindow"))
    doWindowBackground(win, cCanvas())
    doTransparentTitlebar(win)
    okAppearance(win, "NSAppearanceNameDarkAqua")

    // Header (left inset clears the traffic lights)
    let titleLabel = label(win, "KRYPTON TRANSMUTE", area(88, H - 58, 460, 24))
    styleLabel(titleLabel, cBlue(), 18)

    g_subtitle = label(win, "image format lab  ·  Krypton + AppKit", area(88, H - 78, 460, 16))
    styleLabel(g_subtitle, cFaint(), 10)

    // Panel switch
    g_btnImages = styleTab(button(win, "Images", area(rightX, H - 62, 76, 26)))
    g_btnDocs = styleTab(button(win, "Docs", area(rightX + 84, H - 62, 76, 26)))
    g_btnAudio = styleTab(button(win, "Audio", area(rightX + 168, H - 62, 76, 26)))
    g_btnTools = styleTab(button(win, "Tools", area(rightX + 252, H - 62, 76, 26)))
    doClick(g_btnImages, "modeImages", funcptr(onModeImages))
    doClick(g_btnDocs, "modeDocs", funcptr(onModeDocs))
    doClick(g_btnAudio, "modeAudio", funcptr(onModeAudio))
    doClick(g_btnTools, "modeTools", funcptr(onModeTools))

    // Shared queue column
    g_queueLabel = label(win, "IMAGES   0   ·   0 B", area(leftX, H - 124, 420, 14))
    styleLabel(g_queueLabel, cAmber(), 10)

    g_list = textBox(win, area(leftX, 214, leftW, 404))
    doBackground(g_list, cSurface())
    doTextColor(g_list, cText())
    doFont(g_list, mono(11))
    doNoWrap(g_list)
    doEditable(g_list, 0)

    let activityLabel = label(win, "ACTIVITY", area(leftX, 188, 300, 14))
    styleLabel(activityLabel, cAmber(), 10)

    g_log = textBox(win, area(leftX, 104, leftW, 76))
    doBackground(g_log, cSurface())
    doTextColor(g_log, cMuted())
    doFont(g_log, mono(10))
    doNoWrap(g_log)
    doEditable(g_log, 0)
    doTextBox(g_log, "Ready. Add a file, pick a format, convert.\n")

    g_progress = progress(win, area(leftX, 84, leftW, 8))
    doProgress(g_progress, 0)

    g_status = label(win, "Ready.", area(leftX, 48, leftW, 20))
    styleLabel(g_status, cMuted(), 11)

    // ── Image panel: export settings ──────────────────────────────────
    let settingsLabel = imgLabel(win, "EXPORT SETTINGS", area(rightX, H - 148, rightW, 14), cAmber(), 10)

    let formatLabel = imgLabel(win, "Format", area(rightX, H - 178, 140, 14), cMuted(), 11)

    g_format = imgChoices(win, area(rightX, H - 206, rightW, 26))
    let fi = 0
    while fi < formatCount() {
        doAddChoice(g_format, formatName(fi))
        fi += 1
    }
    doChoose(g_format, 0)

    let qualityLabel = imgLabel(win, "Quality  (JPEG · HEIC · AVIF)", area(rightX, H - 244, rightW, 14), cMuted(), 11)
    g_quality = imgField(win, area(rightX, H - 272, 92, 24))
    doText(g_quality, "90")
    doTip(g_quality, "1–100. Used by lossy formats only.")

    let qualityHint = imgLabel(win, "0 = smallest, 100 = best", area(rightX + 100, H - 272, 210, 24), cFaint(), 10)

    let resizeLabel = imgLabel(win, "Resize", area(rightX, H - 310, 140, 14), cMuted(), 11)
    g_resize = imgChoices(win, area(rightX, H - 338, rightW, 26))
    doAddChoice(g_resize, "Original")
    doAddChoice(g_resize, "Longest edge")
    doAddChoice(g_resize, "Percent")
    doChoose(g_resize, 0)

    let sizeLabel = imgLabel(win, "Size value", area(rightX, H - 376, 140, 14), cMuted(), 11)
    g_size = imgField(win, area(rightX, H - 404, 120, 24))
    doText(g_size, "2048")
    doTip(g_size, "Pixels for Longest edge, percentage for Percent.")

    let sizeHint = imgLabel(win, "px / % depending on mode", area(rightX + 128, H - 404, 200, 24), cFaint(), 10)

    let suffixLabel = imgLabel(win, "Filename suffix", area(rightX, H - 442, 180, 14), cMuted(), 11)
    g_suffix = imgField(win, area(rightX, H - 470, 180, 24))
    doText(g_suffix, "-converted")
    doTip(g_suffix, "Added before the new extension.")

    let destLabel = imgLabel(win, "Destination", area(rightX, H - 508, 180, 14), cMuted(), 11)
    g_dest = imgChoices(win, area(rightX, H - 536, rightW, 26))
    doAddChoice(g_dest, "Alongside source")
    doAddChoice(g_dest, "Folder")
    doChoose(g_dest, 0)

    g_folder = imgField(win, area(rightX, H - 576, 212, 24))
    doPlaceholder(g_folder, "Output folder")

    let chooseBtn = imgButton(win, "Choose…", area(rightX + 220, H - 577, 108, 26))
    doButtonTextColor(chooseBtn, cBlue())

    let addBtn = imgButton(win, "Add image", area(rightX, H - 616, 150, 30))
    doButtonTextColor(addBtn, cText())
    let folderBtn = imgButton(win, "Add folder", area(rightX + 162, H - 616, 166, 30))
    doButtonTextColor(folderBtn, cText())

    g_convert = imgButton(win, "Convert", area(rightX, H - 660, rightW, 38))
    doButtonTextColor(g_convert, cGreen())
    doFont(g_convert, mono(13))

    g_icons = imgButton(win, "Build icons", area(rightX, H - 700, 160, 24))
    doButtonTextColor(g_icons, cPurple())
    doTip(g_icons, "Writes a macOS .icns and a Windows .ico (16-256 px) from a square crop.")
    setActionState(g_icons, 0)

    g_reveal = imgButton(win, "Reveal output", area(rightX + 168, H - 700, 160, 24))
    doButtonTextColor(g_reveal, cMuted())
    setActionState(g_reveal, 0)

    // ── Document panel: conversion settings ───────────────────────────
    let docSettingsLabel = docLabel(win, "DOCUMENT SETTINGS", area(rightX, H - 148, rightW, 14), cAmber(), 10)

    let docFormatLabel = docLabel(win, "Convert to", area(rightX, H - 178, 140, 14), cMuted(), 11)

    g_docFormat = docChoices(win, area(rightX, H - 206, rightW, 26))
    let di = 0
    while di < docFormatCount() {
        doAddChoice(g_docFormat, docFormatName(di))
        di += 1
    }
    doChoose(g_docFormat, 5)

    let docInputHint = docLabel(win, "in: txt · md · rtf · doc · docx · odt · html", area(rightX, H - 238, rightW, 14), cFaint(), 10)

    let docSuffixLabel = docLabel(win, "Filename suffix", area(rightX, H - 274, 180, 14), cMuted(), 11)
    g_docSuffix = docField(win, area(rightX, H - 302, 180, 24))
    doText(g_docSuffix, "-converted")
    doTip(g_docSuffix, "Added before the new extension.")

    let docDestLabel = docLabel(win, "Destination", area(rightX, H - 340, 180, 14), cMuted(), 11)
    g_docDest = docChoices(win, area(rightX, H - 368, rightW, 26))
    doAddChoice(g_docDest, "Alongside source")
    doAddChoice(g_docDest, "Folder")
    doChoose(g_docDest, 0)

    g_docFolder = docField(win, area(rightX, H - 408, 212, 24))
    doPlaceholder(g_docFolder, "Output folder")

    let docChooseBtn = docButton(win, "Choose…", area(rightX + 220, H - 409, 108, 26))
    doButtonTextColor(docChooseBtn, cBlue())

    let addDocBtn = docButton(win, "Add document", area(rightX, H - 450, 150, 30))
    doButtonTextColor(addDocBtn, cText())
    let addDocFolderBtn = docButton(win, "Add folder", area(rightX + 162, H - 450, 166, 30))
    doButtonTextColor(addDocFolderBtn, cText())

    g_docConvert = docButton(win, "Convert documents", area(rightX, H - 494, rightW, 38))
    doButtonTextColor(g_docConvert, cGreen())
    doFont(g_docConvert, mono(13))

    let docNote = docLabel(win, "PDF output carries the text, not the layout.", area(rightX, H - 522, rightW, 14), cFaint(), 10)

    g_docReveal = docButton(win, "Reveal output", area(rightX, H - 556, 160, 24))
    doButtonTextColor(g_docReveal, cMuted())
    setActionState(g_docReveal, 0)

    // ── Audio panel: conversion settings ──────────────────────────────
    let audioSettingsLabel = audioLabel(win, "AUDIO SETTINGS", area(rightX, H - 148, rightW, 14), cAmber(), 10)

    let audioFormatLabel = audioLabel(win, "Format", area(rightX, H - 178, 140, 14), cMuted(), 11)

    g_audioFormat = audioChoices(win, area(rightX, H - 206, rightW, 26))
    let au = 0
    while au < audioFormatCount() {
        doAddChoice(g_audioFormat, audioFormatName(au))
        au += 1
    }
    doChoose(g_audioFormat, 0)

    let bitrateLabel = audioLabel(win, "Bitrate  (AAC)", area(rightX, H - 244, 200, 14), cMuted(), 11)
    g_audioBitrate = audioField(win, area(rightX, H - 272, 92, 24))
    doText(g_audioBitrate, "192")
    doTip(g_audioBitrate, "kbps, 8-512. Used by AAC only.")
    let bitrateHint = audioLabel(win, "kbps · 8–512", area(rightX + 100, H - 272, 210, 24), cFaint(), 10)

    let audioSuffixLabel = audioLabel(win, "Filename suffix", area(rightX, H - 310, 180, 14), cMuted(), 11)
    g_audioSuffix = audioField(win, area(rightX, H - 338, 180, 24))
    doText(g_audioSuffix, "-converted")
    doTip(g_audioSuffix, "Added before the new extension.")

    let audioDestLabel = audioLabel(win, "Destination", area(rightX, H - 376, 180, 14), cMuted(), 11)
    g_audioDest = audioChoices(win, area(rightX, H - 404, rightW, 26))
    doAddChoice(g_audioDest, "Alongside source")
    doAddChoice(g_audioDest, "Folder")
    doChoose(g_audioDest, 0)

    g_audioFolder = audioField(win, area(rightX, H - 442, 212, 24))
    doPlaceholder(g_audioFolder, "Output folder")

    let audioChooseBtn = audioButton(win, "Choose…", area(rightX + 220, H - 443, 108, 26))
    doButtonTextColor(audioChooseBtn, cBlue())

    let addAudioBtn = audioButton(win, "Add audio", area(rightX, H - 482, 150, 30))
    doButtonTextColor(addAudioBtn, cText())
    let addAudioFolderBtn = audioButton(win, "Add folder", area(rightX + 162, H - 482, 166, 30))
    doButtonTextColor(addAudioFolderBtn, cText())

    g_audioConvert = audioButton(win, "Convert audio", area(rightX, H - 526, rightW, 38))
    doButtonTextColor(g_audioConvert, cGreen())
    doFont(g_audioConvert, mono(13))

    let audioNote = audioLabel(win, "FLAC and ALAC are lossless; AAC is not.", area(rightX, H - 552, rightW, 14), cFaint(), 10)

    g_audioReveal = audioButton(win, "Reveal output", area(rightX, H - 586, 160, 24))
    doButtonTextColor(g_audioReveal, cMuted())
    setActionState(g_audioReveal, 0)

    // ── Toolbox panel ────────────────────────────────────────────────
    let toolSettingsLabel = toolLabel(win, "TOOLBOX", area(rightX, H - 148, rightW, 14), cAmber(), 10)

    let toolFormatLabel = toolLabel(win, "Convert to", area(rightX, H - 176, 180, 14), cMuted(), 11)
    g_toolFormat = toolChoices(win, area(rightX, H - 204, rightW, 26))
    let tf = 0
    while tf < toolFormatTotal() {
        doAddChoice(g_toolFormat, toolFormatGlobalName(tf))
        tf += 1
    }
    doChoose(g_toolFormat, 4)

    let toolHeightLabel = toolLabel(win, "Video max height", area(rightX, H - 240, 180, 14), cMuted(), 11)
    g_toolHeight = toolField(win, area(rightX, H - 266, 92, 24))
    doText(g_toolHeight, "720")
    doTip(g_toolHeight, "480, 720 or 1080. Video only.")
    let toolHeightHint = toolLabel(win, "480 · 720 · 1080", area(rightX + 100, H - 266, 210, 24), cFaint(), 10)

    let toolTitleLabel = toolLabel(win, "EPUB title", area(rightX, H - 298, 180, 14), cMuted(), 11)
    g_toolTitle = toolField(win, area(rightX, H - 324, rightW, 24))
    doPlaceholder(g_toolTitle, "Blank = source file name")

    let toolSuffixLabel = toolLabel(win, "Filename suffix", area(rightX, H - 356, 180, 14), cMuted(), 11)
    g_toolSuffix = toolField(win, area(rightX, H - 382, 170, 24))
    doText(g_toolSuffix, "-converted")

    let toolDestLabel = toolLabel(win, "Destination", area(rightX, H - 416, 180, 14), cMuted(), 11)
    g_toolDest = toolChoices(win, area(rightX, H - 442, rightW, 26))
    doAddChoice(g_toolDest, "Alongside source")
    doAddChoice(g_toolDest, "Folder")
    doChoose(g_toolDest, 0)

    g_toolFolder = toolField(win, area(rightX, H - 476, 212, 24))
    doPlaceholder(g_toolFolder, "Output folder")

    let toolChooseBtn = toolButton(win, "Choose…", area(rightX + 220, H - 477, 108, 26))
    doButtonTextColor(toolChooseBtn, cBlue())

    let addToolBtn = toolButton(win, "Add files", area(rightX, H - 514, 150, 30))
    doButtonTextColor(addToolBtn, cText())
    let addToolFolderBtn = toolButton(win, "Add folder", area(rightX + 162, H - 514, 166, 30))
    doButtonTextColor(addToolFolderBtn, cText())

    g_toolConvert = toolButton(win, "Convert", area(rightX, H - 558, rightW, 38))
    doButtonTextColor(g_toolConvert, cGreen())
    doFont(g_toolConvert, mono(13))

    g_toolHint = toolLabel(win, "video · tables · data · markup · ebooks · subs · archives · 3D · text · fonts", area(rightX, H - 584, rightW, 14), cFaint(), 9)
    doTip(g_toolHint, "Missing here: FFmpeg (MKV/WebM/GIF), p7zip (7Z), MP3/OGG encoders, fontTools (WOFF2).")

    g_toolReveal = toolButton(win, "Reveal output", area(rightX, H - 612, 160, 24))
    doButtonTextColor(g_toolReveal, cMuted())
    setActionState(g_toolReveal, 0)

    // Wiring
    doClick(addBtn, "add", funcptr(onAdd))
    doClick(folderBtn, "addFolder", funcptr(onAddFolder))
    doClick(chooseBtn, "chooseFolder", funcptr(onChooseFolder))
    doClick(g_convert, "convert", funcptr(onConvert))
    doClick(g_icons, "icons", funcptr(onBuildIcons))
    doClick(g_reveal, "reveal", funcptr(onReveal))

    doClick(addDocBtn, "addDoc", funcptr(onAddDoc))
    doClick(addDocFolderBtn, "addDocFolder", funcptr(onAddDocFolder))
    doClick(docChooseBtn, "chooseDocFolder", funcptr(onChooseDocFolder))
    doClick(g_docConvert, "convertDocs", funcptr(onConvertDocs))
    doClick(g_docReveal, "revealDoc", funcptr(onRevealDoc))

    doClick(addAudioBtn, "addAudio", funcptr(onAddAudio))
    doClick(addAudioFolderBtn, "addAudioFolder", funcptr(onAddAudioFolder))
    doClick(audioChooseBtn, "chooseAudioFolder", funcptr(onChooseAudioFolder))
    doClick(g_audioConvert, "convertAudio", funcptr(onConvertAudio))
    doClick(g_audioReveal, "revealAudio", funcptr(onRevealAudio))

    doClick(addToolBtn, "addTool", funcptr(onAddTool))
    doClick(addToolFolderBtn, "addToolFolder", funcptr(onAddToolFolder))
    doClick(toolChooseBtn, "chooseToolFolder", funcptr(onChooseToolFolder))
    doClick(g_toolConvert, "convertToolbox", funcptr(onConvertTools))
    doClick(g_toolReveal, "revealTool", funcptr(onRevealTool))

    // Keep the layout glued to the window edges when it is resized: header and
    // settings stay at the top, the settings column hugs the right edge, the
    // queue list absorbs extra height, and the activity block stays at the
    // bottom. Nothing here pins a size; it only decides where growth goes.
    anchor(titleLabel, 12)
    anchor(g_subtitle, 12)
    anchor(g_btnImages, 9)
    anchor(g_btnDocs, 9)
    anchor(g_btnAudio, 9)
    anchor(g_btnTools, 9)
    anchor(g_queueLabel, 12)
    anchor(g_list, 20)
    anchor(activityLabel, 36)
    anchor(g_log, 36)
    anchor(g_progress, 36)
    anchor(g_status, 36)

    let ai = 0
    while ai < toInt(cocoaArrayCount(g_imgViews)) {
        anchor(cocoaArrayGet(g_imgViews, ai), 9)
        ai += 1
    }
    let ad = 0
    while ad < toInt(cocoaArrayCount(g_docViews)) {
        anchor(cocoaArrayGet(g_docViews, ad), 9)
        ad += 1
    }
    let aa = 0
    while aa < toInt(cocoaArrayCount(g_audioViews)) {
        anchor(cocoaArrayGet(g_audioViews, aa), 9)
        aa += 1
    }
    let at = 0
    while at < toInt(cocoaArrayCount(g_toolViews)) {
        anchor(cocoaArrayGet(g_toolViews, at), 9)
        at += 1
    }

    setMode("images")
    doShow(win)
    doRun()
}
