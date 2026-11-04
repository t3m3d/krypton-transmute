// src/engine.ks — Krypton Transmute conversion engine.
//
// Pure Krypton. macOS `sips` (ImageIO) is the codec back end, so the format
// table below matches what this Mac can actually write. Paths and settings
// are plain strings; every function returns with `emit`.

module engine

func dq() { emit fromCharCode(34) }
func sq() { emit fromCharCode(39) }
func nl() { emit fromCharCode(10) }

// POSIX-shell single-quote a path so spaces and quotes survive.
func shq(s) {
    let q = sq()
    let d = dq()
    emit q + replace(s, q, q + d + q + d + q) + q
}

// ── Paths ────────────────────────────────────────────────────────────

func baseName(p) {
    let start = 0
    let i = len(p) - 1
    let searching = 1
    while i >= 0 && searching == 1 {
        if p[i] == "/" {
            start = i + 1
            searching = 0
        }
        i = i - 1
    }
    emit substring(p, start, len(p))
}

func dirName(p) {
    let cut = -1
    let i = len(p) - 1
    let searching = 1
    while i >= 0 && searching == 1 {
        if p[i] == "/" {
            cut = i
            searching = 0
        }
        i = i - 1
    }
    if cut < 0 { emit "." }
    if cut == 0 { emit "/" }
    emit substring(p, 0, cut)
}

func stripExt(name) {
    let dot = -1
    let i = len(name) - 1
    let searching = 1
    while i >= 0 && searching == 1 {
        if name[i] == "." {
            dot = i
            searching = 0
        }
        i = i - 1
    }
    if dot <= 0 { emit name }
    emit substring(name, 0, dot)
}

func extOf(name) {
    let dot = -1
    let i = len(name) - 1
    let searching = 1
    while i >= 0 && searching == 1 {
        if name[i] == "." {
            dot = i
            searching = 0
        }
        i = i - 1
    }
    if dot < 0 || dot == len(name) - 1 { emit "" }
    emit toLower(substring(name, dot + 1, len(name)))
}

func joinPath(dir, name) {
    if len(dir) == 0 { emit name }
    if dir[len(dir) - 1] == "/" { emit dir + name }
    emit dir + "/" + name
}

func fileExists(p) {
    if len(p) == 0 { emit 0 }
    if shellRun("test -e " + shq(p)) == "0" { emit 1 }
    emit 0
}

func sameFile(a, b) {
    if a == b { emit 1 }
    if fileExists(a) == 0 { emit 0 }
    if shellRun("test " + shq(a) + " -ef " + shq(b)) == "0" { emit 1 }
    emit 0
}

// ── Format table ─────────────────────────────────────────────────────
// Index order is the order shown in the app's format list.

func formatCount() { emit 7 }

func formatName(i) {
    if i == 0 { emit "PNG" }
    if i == 1 { emit "JPEG" }
    if i == 2 { emit "HEIC" }
    if i == 3 { emit "AVIF" }
    if i == 4 { emit "TIFF" }
    if i == 5 { emit "GIF" }
    emit "BMP"
}

func formatExtension(i) {
    if i == 0 { emit "png" }
    if i == 1 { emit "jpg" }
    if i == 2 { emit "heic" }
    if i == 3 { emit "avif" }
    if i == 4 { emit "tiff" }
    if i == 5 { emit "gif" }
    emit "bmp"
}

func formatSipsName(i) {
    if i == 0 { emit "png" }
    if i == 1 { emit "jpeg" }
    if i == 2 { emit "heic" }
    if i == 3 { emit "avif" }
    if i == 4 { emit "tiff" }
    if i == 5 { emit "gif" }
    emit "bmp"
}

func formatIsLossy(i) {
    if i == 1 || i == 2 || i == 3 { emit 1 }
    emit 0
}

func formatSummary(i) {
    if i == 0 { emit "Lossless · keeps transparency" }
    if i == 1 { emit "Universal · smallest photos" }
    if i == 2 { emit "Apple-native · efficient photos" }
    if i == 3 { emit "Next-gen · tiny files" }
    if i == 4 { emit "Lossless · print and archive" }
    if i == 5 { emit "Indexed · 256 colours" }
    emit "Uncompressed bitmap"
}

// ── Metadata ─────────────────────────────────────────────────────────

func imageWidth(p) {
    emit trim(exec("sips -g pixelWidth " + shq(p) + " 2>/dev/null | awk 'END{print $2}'"))
}

func imageHeight(p) {
    emit trim(exec("sips -g pixelHeight " + shq(p) + " 2>/dev/null | awk 'END{print $2}'"))
}

func imageDimensions(p) {
    let w = imageWidth(p)
    let h = imageHeight(p)
    if len(w) == 0 || len(h) == 0 { emit "not an image" }
    emit w + " x " + h
}

func fileBytes(p) {
    if fileExists(p) == 0 { emit 0 }
    emit toInt(trim(exec("stat -f%z " + shq(p) + " 2>/dev/null")))
}

func humanBytes(n) {
    let bytes = toInt(n)
    if bytes >= 1073741824 { emit oneDecimal(bytes, 1073741824) + " GB" }
    if bytes >= 1048576 { emit oneDecimal(bytes, 1048576) + " MB" }
    if bytes >= 1024 { emit oneDecimal(bytes, 1024) + " KB" }
    emit bytes + " B"
}

func oneDecimal(n, unit) {
    let tenths = n * 10 / unit
    emit toInt(tenths / 10) + "." + (tenths % 10)
}

func padRight(s, width) {
    let out = s
    while len(out) < width { out = out + " " }
    emit out
}

func clip(s, width) {
    if len(s) <= width { emit s }
    emit substring(s, 0, width - 1) + "~"
}

// ── Destinations ─────────────────────────────────────────────────────

/// Returns "" when the destination cannot be resolved.
func outputDirectoryFor(source, destinationMode, chosenFolder) {
    if toInt(destinationMode) == 1 {
        if len(chosenFolder) == 0 { emit "" }
        emit chosenFolder
    }
    emit dirName(source)
}

/// Never overwrite an existing file, and never write over the source itself.
func uniqueOutput(source, dir, suffix, ext) {
    let stem = stripExt(baseName(source))
    let base = joinPath(dir, stem + suffix)
    let out = base + "." + ext
    let n = 2
    let guard = 0
    while (fileExists(out) == 1 || sameFile(out, source) == 1) && guard < 999 {
        out = base + " " + n + "." + ext
        n = n + 1
        guard = guard + 1
    }
    emit out
}

/// ── Icon bundles ─────────────────────────────────────────────────────
// macOS icons need a full .iconset; Windows icons need a multi-image ICO.
// sips cannot write a multi-image ICO, so the container is assembled here.

func hexDigit(n) {
    let digits = "0123456789abcdef"
    let v = toInt(n)
    if v < 0 { v = 0 }
    if v > 15 { v = 15 }
    emit digits[v]
}

func hexByte(n) {
    let v = toInt(n)
    emit hexDigit(v / 16) + hexDigit(v % 16)
}

func hexLE2(n) {
    let v = toInt(n)
    emit hexByte(v % 256) + hexByte(v / 256)
}

func hexLE4(n) {
    let v = toInt(n)
    emit hexByte(v % 256) + hexByte((v / 256) % 256) +
        hexByte((v / 65536) % 256) + hexByte(v / 16777216)
}

// ICO stores 256 as 0.
func icoDim(n) {
    if toInt(n) >= 256 { emit "00" }
    emit hexByte(n)
}

func icoEntry(size, bytes, offset) {
    emit icoDim(size) + icoDim(size) + "0000" + "0100" + "2000" +
        hexLE4(bytes) + hexLE4(offset)
}

/// Center-crops the source to a square master (icons must be square).
func squareMaster(source, path) {
    let w = toInt(imageWidth(source))
    let h = toInt(imageHeight(source))
    if w <= 0 || h <= 0 { emit 0 }
    let side = w
    if h < side { side = h }
    let cmd = "sips -c " + side + " " + side + " " + shq(source) +
        " --out " + shq(path) + " >/dev/null 2>&1"
    if shellRun(cmd) != "0" { emit 0 }
    if fileExists(path) == 0 { emit 0 }
    emit 1
}

func resizeSquare(master, size, path) {
    let cmd = "sips -z " + size + " " + size + " " + shq(master) +
        " --out " + shq(path) + " >/dev/null 2>&1"
    if shellRun(cmd) != "0" { emit 0 }
    if fileExists(path) == 0 { emit 0 }
    emit 1
}

/// macOS app icon: complete .iconset (16–1024) compiled with iconutil.
func makeIcns(source, outputDir, suffix) {
    let dir = outputDir
    if len(dir) == 0 { dir = dirName(source) }

    let temp = trim(exec("mktemp -d /tmp/kt-icns.XXXXXX"))
    if len(temp) == 0 { emit "" }
    let setDir = temp + "/AppIcon.iconset"
    let master = temp + "/master.png"
    shellRun("mkdir -p " + shq(setDir))

    if squareMaster(source, master) == 0 {
        shellRun("rm -rf " + shq(temp))
        emit ""
    }

    let ok = 1
    if resizeSquare(master, 16, setDir + "/icon_16x16.png") == 0 { ok = 0 }
    if resizeSquare(master, 32, setDir + "/icon_16x16@2x.png") == 0 { ok = 0 }
    if resizeSquare(master, 32, setDir + "/icon_32x32.png") == 0 { ok = 0 }
    if resizeSquare(master, 64, setDir + "/icon_32x32@2x.png") == 0 { ok = 0 }
    if resizeSquare(master, 128, setDir + "/icon_128x128.png") == 0 { ok = 0 }
    if resizeSquare(master, 256, setDir + "/icon_128x128@2x.png") == 0 { ok = 0 }
    if resizeSquare(master, 256, setDir + "/icon_256x256.png") == 0 { ok = 0 }
    if resizeSquare(master, 512, setDir + "/icon_256x256@2x.png") == 0 { ok = 0 }
    if resizeSquare(master, 512, setDir + "/icon_512x512.png") == 0 { ok = 0 }
    if resizeSquare(master, 1024, setDir + "/icon_512x512@2x.png") == 0 { ok = 0 }

    if ok == 0 {
        shellRun("rm -rf " + shq(temp))
        emit ""
    }

    let out = uniqueOutput(source, dir, suffix, "icns")
    let rc = shellRun("iconutil -c icns " + shq(setDir) + " -o " + shq(out) + " >/dev/null 2>&1")
    shellRun("rm -rf " + shq(temp))
    if rc != "0" { emit "" }
    if fileExists(out) == 0 { emit "" }
    emit out
}

/// Windows app icon: one ICO holding 16, 32, 48, 64, 128 and 256 px PNGs.
func makeIco(source, outputDir, suffix) {
    let dir = outputDir
    if len(dir) == 0 { dir = dirName(source) }

    let temp = trim(exec("mktemp -d /tmp/kt-ico.XXXXXX"))
    if len(temp) == 0 { emit "" }
    let master = temp + "/master.png"
    let p16 = temp + "/s16.png"
    let p32 = temp + "/s32.png"
    let p48 = temp + "/s48.png"
    let p64 = temp + "/s64.png"
    let p128 = temp + "/s128.png"
    let p256 = temp + "/s256.png"

    if squareMaster(source, master) == 0 {
        shellRun("rm -rf " + shq(temp))
        emit ""
    }

    let ok = 1
    if resizeSquare(master, 16, p16) == 0 { ok = 0 }
    if resizeSquare(master, 32, p32) == 0 { ok = 0 }
    if resizeSquare(master, 48, p48) == 0 { ok = 0 }
    if resizeSquare(master, 64, p64) == 0 { ok = 0 }
    if resizeSquare(master, 128, p128) == 0 { ok = 0 }
    if resizeSquare(master, 256, p256) == 0 { ok = 0 }

    if ok == 0 {
        shellRun("rm -rf " + shq(temp))
        emit ""
    }

    let s16 = fileBytes(p16)
    let s32 = fileBytes(p32)
    let s48 = fileBytes(p48)
    let s64 = fileBytes(p64)
    let s128 = fileBytes(p128)
    let s256 = fileBytes(p256)

    let count = 6
    let base = 6 + 16 * count
    let o16 = base
    let o32 = o16 + s16
    let o48 = o32 + s32
    let o64 = o48 + s48
    let o128 = o64 + s64
    let o256 = o128 + s128

    let head = "00000100" + hexLE2(count)
    head = head + icoEntry(16, s16, o16)
    head = head + icoEntry(32, s32, o32)
    head = head + icoEntry(48, s48, o48)
    head = head + icoEntry(64, s64, o64)
    head = head + icoEntry(128, s128, o128)
    head = head + icoEntry(256, s256, o256)

    let out = uniqueOutput(source, dir, suffix, "ico")
    let cmd = "printf '%s' " + shq(head) + " | xxd -r -p > " + shq(out) +
        " && cat " + shq(p16) + " " + shq(p32) + " " + shq(p48) + " " +
        shq(p64) + " " + shq(p128) + " " + shq(p256) + " >> " + shq(out)
    let rc = shellRun(cmd)
    shellRun("rm -rf " + shq(temp))

    if rc != "0" {
        shellRun("rm -f " + shq(out))
        emit ""
    }
    if fileExists(out) == 0 { emit "" }
    emit out
}

// Converts one image. Returns the written path, or "" on failure.
/// resizeMode: 0 = original, 1 = longest edge, 2 = percent of width.
func convertFile(source, formatIndex, quality, resizeMode, resizeValue, outputDir, suffix) {
    if fileExists(source) == 0 { emit "" }

    let dir = outputDir
    if len(dir) == 0 { dir = dirName(source) }

    let ext = formatExtension(formatIndex)
    let out = uniqueOutput(source, dir, suffix, ext)

    let cmd = "sips -s format " + formatSipsName(formatIndex)
    if formatIsLossy(formatIndex) == 1 && toInt(quality) > 0 {
        cmd = cmd + " -s formatOptions " + toInt(quality)
    }

    let mode = toInt(resizeMode)
    if mode == 1 {
        let edge = toInt(resizeValue)
        if edge > 0 { cmd = cmd + " -Z " + edge }
    }
    if mode == 2 {
        let percent = toInt(resizeValue)
        if percent > 0 {
            let width = toInt(imageWidth(source))
            if width > 0 {
                let target = width * percent / 100
                if target < 1 { target = 1 }
                cmd = cmd + " --resampleWidth " + target
            }
        }
    }

    cmd = cmd + " " + shq(source) + " --out " + shq(out)

    if shellRun(cmd + " >/dev/null 2>&1") != "0" { emit "" }
    if fileExists(out) == 0 { emit "" }
    emit out
}

/// Every readable image under a folder (two levels deep), newline separated.
func scanFolder(dir) {
    let cmd = "find " + shq(dir) + " -maxdepth 2 -type f 2>/dev/null" +
        " | grep -iE '[.](png|jpg|jpeg|heic|avif|tif|tiff|bmp|gif|webp)$'" +
        " | sort"
    emit exec(cmd)
}

/// ── Documents ────────────────────────────────────────────────────────
// Documents convert through macOS `textutil`, which reads and writes the
// formats below. PDF has no textutil writer, so it is produced from the
// document's plain text through `cupsfilter`; the PDF is text-only.

func docFormatCount() { emit 10 }

func docFormatName(i) {
    if i == 0 { emit "TXT" }
    if i == 1 { emit "RTF" }
    if i == 2 { emit "RTFD" }
    if i == 3 { emit "HTML" }
    if i == 4 { emit "DOC" }
    if i == 5 { emit "DOCX" }
    if i == 6 { emit "ODT" }
    if i == 7 { emit "WordML" }
    if i == 8 { emit "WebArchive" }
    emit "PDF"
}

func docFormatExtension(i) {
    if i == 0 { emit "txt" }
    if i == 1 { emit "rtf" }
    if i == 2 { emit "rtfd" }
    if i == 3 { emit "html" }
    if i == 4 { emit "doc" }
    if i == 5 { emit "docx" }
    if i == 6 { emit "odt" }
    if i == 7 { emit "wordml" }
    if i == 8 { emit "webarchive" }
    emit "pdf"
}

/// `textutil -convert` name; empty for PDF, which has its own path.
func docFormatArg(i) {
    if i == 0 { emit "txt" }
    if i == 1 { emit "rtf" }
    if i == 2 { emit "rtfd" }
    if i == 3 { emit "html" }
    if i == 4 { emit "doc" }
    if i == 5 { emit "docx" }
    if i == 6 { emit "odt" }
    if i == 7 { emit "wordml" }
    if i == 8 { emit "webarchive" }
    emit ""
}

func docFormatIsPdf(i) {
    if toInt(i) == 9 { emit 1 }
    emit 0
}

func docFormatSummary(i) {
    if i == 0 { emit "Plain text · no formatting" }
    if i == 1 { emit "Rich text · Word compatible" }
    if i == 2 { emit "Rich text with attachments" }
    if i == 3 { emit "Web page · opens anywhere" }
    if i == 4 { emit "Word 97–2004" }
    if i == 5 { emit "Word 2007 and later" }
    if i == 6 { emit "LibreOffice · OpenDocument" }
    if i == 7 { emit "Word 2003 XML" }
    if i == 8 { emit "Safari archive with assets" }
    emit "Text-only PDF · print ready"
}

func isDocument(p) {
    let e = extOf(baseName(p))
    if e == "txt" || e == "md" || e == "markdown" { emit 1 }
    if e == "rtf" || e == "rtfd" || e == "html" || e == "htm" { emit 1 }
    if e == "doc" || e == "docx" || e == "odt" || e == "wordml" { emit 1 }
    if e == "webarchive" { emit 1 }
    emit 0
}

/// Every readable document under a folder (two levels deep), newline separated.
/// RTFD is a package (a directory), so it needs its own find.
func scanDocuments(dir) {
    let exts = "txt|md|markdown|rtf|html|htm|doc|docx|odt|wordml|webarchive"
    let cmd = "{ find " + shq(dir) + " -maxdepth 2 -type f 2>/dev/null" +
        " | grep -iE '[.](" + exts + ")$'; " +
        "find " + shq(dir) + " -maxdepth 2 -type d -name '*.rtfd' 2>/dev/null; } | sort"
    emit exec(cmd)
}

/// Converts one document. Returns the written path, or "" on failure.
func convertDocument(source, formatIndex, outputDir, suffix) {
    if fileExists(source) == 0 { emit "" }

    let dir = outputDir
    if len(dir) == 0 { dir = dirName(source) }

    let out = uniqueOutput(source, dir, suffix, docFormatExtension(formatIndex))

    if docFormatIsPdf(formatIndex) == 1 {
        let temp = trim(exec("mktemp -d /tmp/kt-pdf.XXXXXX"))
        if len(temp) == 0 { emit "" }
        let txt = temp + "/doc.txt"
        let read = shellRun("textutil -convert txt -output " + shq(txt) +
            " " + shq(source) + " >/dev/null 2>&1")
        if read != "0" || fileExists(txt) == 0 {
            shellRun("rm -rf " + shq(temp))
            emit ""
        }
        let rc = shellRun("cupsfilter -m application/pdf " + shq(txt) +
            " > " + shq(out) + " 2>/dev/null")
        shellRun("rm -rf " + shq(temp))
        if rc != "0" || fileExists(out) == 0 || fileBytes(out) < 100 {
            shellRun("rm -rf " + shq(out))
            emit ""
        }
        emit out
    }

    let cmd = "textutil -convert " + docFormatArg(formatIndex) +
        " -output " + shq(out) + " " + shq(source) + " >/dev/null 2>&1"
    if shellRun(cmd) != "0" {
        shellRun("rm -rf " + shq(out))
        emit ""
    }
    if fileExists(out) == 0 { emit "" }
    if fileBytes(out) == 0 {
        shellRun("rm -rf " + shq(out))
        emit ""
    }
    emit out
}

/// ── Audio ────────────────────────────────────────────────────────────
// Audio converts through macOS `afconvert` (CoreAudio), and `afinfo` reads
// duration and stream format. AAC, Apple Lossless, PCM in WAV/AIFF/CAF and
// FLAC are all writable here. macOS has no MP3 encoder, so MP3 is input only.

func audioFormatCount() { emit 6 }

func audioFormatName(i) {
    if i == 0 { emit "M4A (AAC)" }
    if i == 1 { emit "ALAC" }
    if i == 2 { emit "WAV" }
    if i == 3 { emit "AIFF" }
    if i == 4 { emit "CAF" }
    emit "FLAC"
}

func audioFormatExtension(i) {
    if i == 0 { emit "m4a" }
    if i == 1 { emit "m4a" }
    if i == 2 { emit "wav" }
    if i == 3 { emit "aiff" }
    if i == 4 { emit "caf" }
    emit "flac"
}

func audioFormatFileType(i) {
    if i == 0 { emit "m4af" }
    if i == 1 { emit "m4af" }
    if i == 2 { emit "WAVE" }
    if i == 3 { emit "AIFF" }
    if i == 4 { emit "caff" }
    emit "flac"
}

func audioFormatData(i) {
    if i == 0 { emit "aac" }
    if i == 1 { emit "alac" }
    if i == 2 { emit "LEI16" }
    if i == 3 { emit "BEI16" }
    if i == 4 { emit "LEI16" }
    emit "flac"
}

func audioFormatIsLossy(i) {
    if toInt(i) == 0 { emit 1 }
    emit 0
}

func audioFormatSummary(i) {
    if i == 0 { emit "AAC · small, plays everywhere" }
    if i == 1 { emit "Apple Lossless · bit-exact" }
    if i == 2 { emit "PCM · uncompressed, universal" }
    if i == 3 { emit "PCM · Apple's classic format" }
    if i == 4 { emit "Core Audio · uncompressed container" }
    emit "Free lossless · 50% smaller" }

func isAudio(p) {
    let e = extOf(baseName(p))
    if e == "aif" || e == "aiff" || e == "aifc" { emit 1 }
    if e == "wav" || e == "wave" { emit 1 }
    if e == "m4a" || e == "m4b" || e == "aac" { emit 1 }
    if e == "caf" || e == "flac" || e == "mp3" { emit 1 }
    if e == "au" || e == "snd" { emit 1 }
    emit 0
}

/// Every readable audio file under a folder (two levels deep).
func scanAudio(dir) {
    let cmd = "find " + shq(dir) + " -maxdepth 2 -type f 2>/dev/null" +
        " | grep -iE '[.](aif|aiff|aifc|wav|wave|m4a|m4b|aac|caf|flac|mp3|au|snd)$'" +
        " | sort"
    emit exec(cmd)
}

func audioBitrateHz(kbps) {
    let v = toInt(kbps)
    if v < 8 { v = 8 }
    if v > 512 { v = 512 }
    emit v * 1000
}

/// Converts one audio file. Returns the written path, or "" on failure.
func convertAudio(source, formatIndex, bitrate, outputDir, suffix) {
    if fileExists(source) == 0 { emit "" }

    let dir = outputDir
    if len(dir) == 0 { dir = dirName(source) }

    let out = uniqueOutput(source, dir, suffix, audioFormatExtension(formatIndex))
    let cmd = "afconvert -f " + audioFormatFileType(formatIndex) +
        " -d " + audioFormatData(formatIndex)
    if audioFormatIsLossy(formatIndex) == 1 && toInt(bitrate) > 0 {
        cmd = cmd + " -b " + audioBitrateHz(bitrate)
    }
    cmd = cmd + " " + shq(source) + " " + shq(out) + " >/dev/null 2>&1"

    if shellRun(cmd) != "0" {
        shellRun("rm -f " + shq(out))
        emit ""
    }
    if fileExists(out) == 0 { emit "" }
    if fileBytes(out) == 0 {
        shellRun("rm -f " + shq(out))
        emit ""
    }
    emit out
}

/// Duration as m:ss, straight from afinfo.
func audioLength(p) {
    if fileExists(p) == 0 { emit "--:--" }
    let q = dq()
    let prog = "/estimated duration/ {printf " + q + "%d:%02d" + q + ", $3/60, $3%60}"
    let v = trim(exec("afinfo " + shq(p) + " 2>/dev/null | awk " + shq(prog)))
    if len(v) == 0 { emit "--:--" }
    emit v
}

/// "2 ch · 48000 Hz" for the queue table.
func audioInfo(p) {
    if fileExists(p) == 0 { emit "audio" }
    let q = dq()
    let prog = "/Data format/ {print $3" + q + " ch · " + q + "$5" + q + " Hz" + q + "}"
    let v = trim(exec("afinfo " + shq(p) + " 2>/dev/null | awk " + shq(prog)))
    if len(v) == 0 { emit "audio" }
    emit v
}

/// ── Toolbox ──────────────────────────────────────────────────────────
// Everything macOS cannot convert on its own. Video uses Apple's `avconvert`;
// tables, structured data, markup, e-books, subtitles, archives and meshes
// use src/toolkit.py, which is Python standard library only. The build copies
// that helper to Application Support, which is where this looks first.

func supportDirectory() {
    emit trim(exec("echo $HOME")) + "/Library/Application Support/Krypton Transmute"
}

func toolkitPath() {
    let support = supportDirectory() + "/toolkit.py"
    if fileExists(support) == 1 { emit support }
    if fileExists("src/toolkit.py") == 1 { emit "src/toolkit.py" }
    emit support
}

func pythonPath() {
    emit trim(exec("command -v python3"))
}

func toolboxReady() {
    if len(pythonPath()) == 0 { emit 0 }
    if fileExists(toolkitPath()) == 0 { emit 0 }
    emit 1
}

func toolRun(args) {
    let py = pythonPath()
    if len(py) == 0 { emit "127" }
    emit shellRun(shq(py) + " " + shq(toolkitPath()) + " " + args + " 2>/dev/null")
}

func toolOutput(args) {
    let py = pythonPath()
    if len(py) == 0 { emit "" }
    emit exec(shq(py) + " " + shq(toolkitPath()) + " " + args + " 2>/dev/null")
}

func toolCategoryCount() { emit 10 }

func toolCategoryName(i) {
    let c = toInt(i)
    if c == 0 { emit "Video" }
    if c == 1 { emit "Tables" }
    if c == 2 { emit "Structured data" }
    if c == 3 { emit "Markup" }
    if c == 4 { emit "E-books" }
    if c == 5 { emit "Subtitles" }
    if c == 6 { emit "Archives" }
    if c == 7 { emit "3D models" }
    if c == 8 { emit "Text encoding" }
    emit "Fonts"
}

func toolCategoryKey(i) {
    let c = toInt(i)
    if c == 0 { emit "video" }
    if c == 1 { emit "tables" }
    if c == 2 { emit "data" }
    if c == 3 { emit "markup" }
    if c == 4 { emit "ebook" }
    if c == 5 { emit "subs" }
    if c == 6 { emit "archive" }
    if c == 7 { emit "models" }
    if c == 8 { emit "encoding" }
    emit "fonts"
}

func toolFormatCount(cat) {
    let c = toInt(cat)
    if c == 0 || c == 1 || c == 2 { emit 4 }
    if c == 3 || c == 5 || c == 6 { emit 3 }
    if c == 4 || c == 7 { emit 5 }
    if c == 8 { emit 4 }
    emit 1
}

func toolFormatName(cat, i) {
    let c = toInt(cat)
    let k = toInt(i)
    if c == 0 {
        if k == 0 { emit "MP4 (H.264)" }
        if k == 1 { emit "MOV (ProRes)" }
        if k == 2 { emit "M4V (Apple)" }
        emit "M4A (audio only)"
    }
    if c == 1 {
        if k == 0 { emit "CSV" }
        if k == 1 { emit "TSV" }
        if k == 2 { emit "JSON" }
        emit "XLSX"
    }
    if c == 2 {
        if k == 0 { emit "JSON" }
        if k == 1 { emit "YAML" }
        if k == 2 { emit "TOML" }
        emit "XML"
    }
    if c == 3 {
        if k == 0 { emit "HTML" }
        if k == 1 { emit "Markdown" }
        emit "TXT"
    }
    if c == 4 {
        if k == 0 { emit "EPUB" }
        if k == 1 { emit "HTML" }
        if k == 2 { emit "TXT" }
        if k == 3 { emit "Markdown" }
        emit "DOCX"
    }
    if c == 5 {
        if k == 0 { emit "SRT" }
        if k == 1 { emit "VTT" }
        emit "ASS"
    }
    if c == 6 {
        if k == 0 { emit "ZIP" }
        if k == 1 { emit "TAR" }
        emit "TGZ"
    }
    if c == 7 {
        if k == 0 { emit "OBJ" }
        if k == 1 { emit "STL" }
        if k == 2 { emit "PLY" }
        if k == 3 { emit "GLB" }
        emit "glTF"
    }
    if c == 8 {
        if k == 0 { emit "UTF-8" }
        if k == 1 { emit "UTF-16" }
        if k == 2 { emit "Latin-1" }
        emit "Windows-1252"
    }
    emit "WOFF"
}

func toolFormatExt(cat, i) {
    let c = toInt(cat)
    let k = toInt(i)
    if c == 0 {
        if k == 0 { emit "mp4" }
        if k == 1 { emit "mov" }
        if k == 2 { emit "m4v" }
        emit "m4a"
    }
    if c == 1 {
        if k == 0 { emit "csv" }
        if k == 1 { emit "tsv" }
        if k == 2 { emit "json" }
        emit "xlsx"
    }
    if c == 2 {
        if k == 0 { emit "json" }
        if k == 1 { emit "yaml" }
        if k == 2 { emit "toml" }
        emit "xml"
    }
    if c == 3 {
        if k == 0 { emit "html" }
        if k == 1 { emit "md" }
        emit "txt"
    }
    if c == 4 {
        if k == 0 { emit "epub" }
        if k == 1 { emit "html" }
        if k == 2 { emit "txt" }
        if k == 3 { emit "md" }
        emit "docx"
    }
    if c == 5 {
        if k == 0 { emit "srt" }
        if k == 1 { emit "vtt" }
        emit "ass"
    }
    if c == 6 {
        if k == 0 { emit "zip" }
        if k == 1 { emit "tar" }
        emit "tgz"
    }
    if c == 7 {
        if k == 0 { emit "obj" }
        if k == 1 { emit "stl" }
        if k == 2 { emit "ply" }
        if k == 3 { emit "glb" }
        emit "gltf"
    }
    if c == 8 { emit "txt" }
    emit "woff"
}

func toolFormatKey(cat, i) {
    let k = toInt(i)
    if toInt(cat) == 8 {
        if k == 0 { emit "utf8" }
        if k == 1 { emit "utf16" }
        if k == 2 { emit "latin1" }
        emit "cp1252"
    }
    emit toolFormatExt(cat, i)
}

/// The panel shows one grouped list, so these map a global format index to
/// its family and to that family's own index.
func toolFormatTotal() { emit 36 }

func toolCategoryForFormat(g) {
    let k = toInt(g)
    if k < 4 { emit 0 }
    if k < 8 { emit 1 }
    if k < 12 { emit 2 }
    if k < 15 { emit 3 }
    if k < 20 { emit 4 }
    if k < 23 { emit 5 }
    if k < 26 { emit 6 }
    if k < 31 { emit 7 }
    if k < 35 { emit 8 }
    emit 9
}

func toolLocalIndex(g) {
    let k = toInt(g)
    let cat = toInt(toolCategoryForFormat(k))
    let offset = 0
    if cat == 1 { offset = 4 }
    if cat == 2 { offset = 8 }
    if cat == 3 { offset = 12 }
    if cat == 4 { offset = 15 }
    if cat == 5 { offset = 20 }
    if cat == 6 { offset = 23 }
    if cat == 7 { offset = 26 }
    if cat == 8 { offset = 31 }
    if cat == 9 { offset = 35 }
    emit k - offset
}

func toolFormatGlobalName(g) {
    let cat = toInt(toolCategoryForFormat(g))
    emit toolCategoryName(cat) + " · " + toolFormatName(cat, toolLocalIndex(g))
}

/// Which family a path belongs to, or -1 when the toolbox cannot read it.
func toolCategoryForExt(e) {
    let ext = toLower(e)
    if ext == "mov" || ext == "mp4" || ext == "m4v" || ext == "m4a" { emit 0 }
    if ext == "csv" || ext == "tsv" || ext == "xlsx" { emit 1 }
    if ext == "json" || ext == "yaml" || ext == "yml" || ext == "toml" || ext == "xml" || ext == "plist" { emit 2 }
    if ext == "html" || ext == "htm" || ext == "md" || ext == "markdown" || ext == "txt" { emit 3 }
    if ext == "epub" { emit 4 }
    if ext == "srt" || ext == "vtt" || ext == "ass" || ext == "ssa" { emit 5 }
    if ext == "zip" || ext == "tar" || ext == "tgz" || ext == "gz" { emit 6 }
    if ext == "obj" || ext == "stl" || ext == "ply" || ext == "glb" || ext == "gltf" { emit 7 }
    if ext == "ttf" || ext == "otf" { emit 9 }
    emit -1
}

/// A CSV is a table, and also readable as structured data; the family list
/// above decides which one wins (tables, for csv/tsv/xlsx).
func toolCategoryForPath(p) {
    emit toolCategoryForExt(extOf(baseName(p)))
}

func toolIsAny(p) {
    if toInt(toolCategoryForPath(p)) < 0 { emit 0 }
    emit 1
}

func toolOptionLabel(cat) {
    if toInt(cat) == 0 { emit "Max height  (480 · 720 · 1080)" }
    if toInt(cat) == 4 { emit "Book title  (blank = file name)" }
    emit "No option for this family"
}

func toolOptionDefault(cat) {
    if toInt(cat) == 0 { emit "720" }
    emit ""
}

func toolHint(cat) {
    let c = toInt(cat)
    if c == 0 { emit "avconvert · H.264 · ProRes · audio extract" }
    if c == 1 { emit "csv ↔ tsv ↔ json ↔ xlsx" }
    if c == 2 { emit "json ↔ yaml ↔ toml ↔ xml" }
    if c == 3 { emit "markdown ↔ html ↔ txt" }
    if c == 4 { emit "epub ↔ html · txt · markdown · docx" }
    if c == 5 { emit "srt ↔ vtt ↔ ass" }
    if c == 6 { emit "zip ↔ tar ↔ tgz · 7z needs p7zip" }
    if c == 7 { emit "obj ↔ stl ↔ ply ↔ glb/gltf · triangles only" }
    if c == 8 { emit "utf-8 ↔ utf-16 ↔ latin-1 ↔ windows-1252" }
    emit "ttf/otf → woff · woff2 needs fontTools"
}

/// Pipe-separated extensions a family can read.
func toolExtList(cat) {
    let c = toInt(cat)
    if c == 0 { emit "mov|mp4|m4v|m4a" }
    if c == 1 { emit "csv|tsv|json|xlsx" }
    if c == 2 { emit "json|yaml|yml|toml|xml|plist" }
    if c == 3 { emit "html|htm|md|markdown|txt" }
    if c == 4 { emit "epub|html|htm|md|markdown|txt" }
    if c == 5 { emit "srt|vtt|ass|ssa" }
    if c == 6 { emit "zip|tar|tgz|gz" }
    if c == 7 { emit "obj|stl|ply|glb|gltf" }
    if c == 8 { emit "txt|md|markdown|csv|tsv|json|yaml|yml|toml|xml|html|htm|srt|vtt|ass" }
    emit "ttf|otf"
}

func toolAccepts(cat, p) {
    let ext = extOf(baseName(p))
    if len(ext) == 0 { emit 0 }
    if contains("|" + toolExtList(cat) + "|", "|" + ext + "|") == 1 { emit 1 }
    emit 0
}

/// Every file of a family under a folder (two levels deep).
func toolScan(cat, dir) {
    let cmd = "find " + shq(dir) + " -maxdepth 2 -type f 2>/dev/null" +
        " | grep -iE '[.](" + toolExtList(cat) + ")$' | sort"
    emit exec(cmd)
}

func toolInfo(cat, p) {
    if fileExists(p) == 0 { emit "" }
    if toolAccepts(cat, p) == 0 { emit "" }
    if toolboxReady() == 0 { emit "" }
    emit trim(toolOutput("info " + shq(toolCategoryKey(cat)) + " " + shq(p)))
}

func videoPreset(fmt, option) {
    let height = toInt(option)
    if height <= 0 { height = 720 }
    let k = toInt(fmt)
    if k == 0 {
        if height >= 1080 { emit "Preset1920x1080" }
        if height >= 720 { emit "Preset1280x720" }
        emit "Preset640x480"
    }
    if k == 1 { emit "PresetAppleProRes422LPCM" }
    if k == 2 {
        if height >= 1080 { emit "PresetAppleM4V1080pHD" }
        if height >= 720 { emit "PresetAppleM4V720pHD" }
        emit "PresetAppleM4V480pSD"
    }
    emit "PresetAppleM4A"
}

/// Converts one movie (or extracts its audio). Returns the path or "".
func convertVideo(source, formatIndex, option, outputDir, suffix) {
    if fileExists(source) == 0 { emit "" }

    let dir = outputDir
    if len(dir) == 0 { dir = dirName(source) }

    let out = uniqueOutput(source, dir, suffix, toolFormatExt(0, formatIndex))
    let cmd = "avconvert --source " + shq(source) + " --output " + shq(out) +
        " --preset " + videoPreset(formatIndex, option) + " --replace"

    if shellRun(cmd + " >/dev/null 2>&1") != "0" {
        shellRun("rm -f " + shq(out))
        emit ""
    }
    if fileExists(out) == 0 { emit "" }
    if fileBytes(out) == 0 {
        shellRun("rm -f " + shq(out))
        emit ""
    }
    emit out
}

/// Converts one toolbox file. Returns the written path, or "" on failure.
func toolConvert(cat, source, formatIndex, option, outputDir, suffix) {
    if fileExists(source) == 0 { emit "" }
    if toolAccepts(cat, source) == 0 { emit "" }

    let dir = outputDir
    if len(dir) == 0 { dir = dirName(source) }

    if toInt(cat) == 0 { emit convertVideo(source, formatIndex, option, dir, suffix) }
    if toolboxReady() == 0 { emit "" }

    let outExt = toolFormatExt(cat, formatIndex)
    if toInt(cat) == 8 { outExt = extOf(source) }
    let out = uniqueOutput(source, dir, suffix, outExt)
    let args = "convert " + shq(toolCategoryKey(cat)) + " " +
        shq(toolFormatKey(cat, formatIndex)) + " " + shq(source) + " " +
        shq(out) + " " + shq(option)

    if toolRun(args) != "0" {
        shellRun("rm -f " + shq(out))
        emit ""
    }
    if fileExists(out) == 0 { emit "" }
    if fileBytes(out) == 0 {
        shellRun("rm -f " + shq(out))
        emit ""
    }
    emit out
}
