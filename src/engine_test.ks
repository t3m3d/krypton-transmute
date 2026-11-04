// src/engine_test.ks — engine checks for Krypton Transmute.
//
// Run from the project root:
//   kcc -r src/engine_test.ks        (or ./scripts/test.sh)
//
// Creates a temporary workspace, builds a real PNG fixture with sips, then
// exercises conversion, resize, naming and folder scanning.

import "engine.ks"

let g_pass = 0
let g_fail = 0

func check(ok, label) {
    if toInt(ok) == 1 {
        g_pass = g_pass + 1
        kp("  PASS   " + label)
        emit "1"
    }
    g_fail = g_fail + 1
    kp("  FAIL   " + label)
    emit "0"
}

// What container did sips actually write? (png, jpeg, heic, avif, tiff, gif, bmp)
func detectedFormat(p) {
    emit toLower(trim(exec("sips -g format " + shq(p) + " 2>/dev/null | awk 'END{print $2}'")))
}

just run {
    kp("Krypton Transmute — engine checks")
    kp("")

    let dir = trim(exec("mktemp -d /tmp/krypton-transmute.XXXXXX"))
    check(len(dir) > 0, "temporary workspace")

    let fixture = dir + "/base.png"
    shellRun("sips -s format png " + shq("assets/AppIcon.icns") + " --out " + shq(fixture) + " >/dev/null 2>&1")
    check(fileExists(fixture), "PNG fixture created from app icon")
    check(imageWidth(fixture) == "1024", "fixture width is 1024")
    check(imageHeight(fixture) == "1024", "fixture height is 1024")

    // Format conversion
    let jpeg = convertFile(fixture, 1, "60", 0, "", dir, "-jpeg")
    check(fileExists(jpeg), "JPEG output written")
    check(extOf(jpeg) == "jpg", "JPEG uses .jpg extension")
    check(fileBytes(jpeg) > 0, "JPEG has content")

    let heic = convertFile(fixture, 2, "70", 0, "", dir, "-heic")
    check(fileExists(heic), "HEIC output written")

    let avif = convertFile(fixture, 3, "60", 0, "", dir, "-avif")
    check(fileExists(avif), "AVIF output written")

    // Every offered format
    let f = 0
    while f < formatCount() {
        let out = convertFile(fixture, f, "80", 0, "", dir, "-all-" + formatName(f))
        check(fileExists(out), formatName(f) + " output written")
        check(extOf(out) == formatExtension(f), formatName(f) + " extension")
        check(fileBytes(out) > 0, formatName(f) + " has content")
        check(imageWidth(out) == "1024", formatName(f) + " readable at full size")
        check(detectedFormat(out) == formatSipsName(f), formatName(f) + " container")
        f += 1
    }

    // Resize
    let edge = convertFile(fixture, 0, "90", 1, "128", dir, "-edge")
    check(imageWidth(edge) == "128", "longest-edge resize width")
    check(imageHeight(edge) == "128", "longest-edge resize height")

    let half = convertFile(fixture, 0, "90", 2, "50", dir, "-pct")
    check(imageWidth(half) == "512", "percent resize width")
    check(imageHeight(half) == "512", "percent resize height")

    // Naming
    let first = convertFile(fixture, 0, "90", 0, "", dir, "-same")
    let second = convertFile(fixture, 0, "90", 0, "", dir, "-same")
    check(first != second, "existing files are not overwritten")
    check(fileExists(first) && fileExists(second), "both colliding outputs exist")

    // Folder scan
    let found = scanFolder(dir)
    check(lineCount(found) >= 7, "folder scan finds every image")

    // Helpers
    check(humanBytes(1536) == "1.5 KB", "human-readable sizes")
    check(baseName("/tmp/example/photo.jpeg") == "photo.jpeg", "base name")
    check(stripExt("photo.jpeg") == "photo", "extension stripped")
    check(dirName("/tmp/example/photo.jpeg") == "/tmp/example", "directory name")

    shellRun("rm -rf " + shq(dir))

    kp("")
    let total = g_pass + g_fail
    if g_fail > 0 {
        kp("" + g_fail + " of " + total + " checks failed")
    } else {
        kp("All " + total + " checks passed")
    }
}
