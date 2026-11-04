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

/// Converts one image. Returns the written path, or "" on failure.
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
