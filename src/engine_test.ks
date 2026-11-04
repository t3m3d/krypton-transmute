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

    // App icon bundles
    let icns = makeIcns(fixture, dir, "-icon")
    check(fileExists(icns), "macOS .icns written")
    check(extOf(icns) == "icns", "ICNS extension")
    check(fileBytes(icns) > 1000, "ICNS has content")
    check(imageWidth(icns) == "1024", "ICNS carries the 1024 px master")

    let ico = makeIco(fixture, dir, "-icon")
    check(fileExists(ico), "Windows .ico written")
    check(extOf(ico) == "ico", "ICO extension")
    check(fileBytes(ico) > 1000, "ICO has content")
    check(trim(exec("xxd -p -l 6 " + shq(ico))) == "000001000600", "ICO header declares 6 sizes")

    // Non-square sources are center-cropped, so the icon pipeline still works.
    let wide = dir + "/wide.png"
    shellRun("sips -z 600 800 " + shq(fixture) + " --out " + shq(wide) + " >/dev/null 2>&1")
    check(fileExists(wide), "non-square fixture created")
    check(fileExists(makeIcns(wide, dir, "-wide")), "ICNS from non-square source")
    check(fileExists(makeIco(wide, dir, "-wide")), "ICO from non-square source")

    // Documents
    let textFixture = dir + "/note.txt"
    writeFile(textFixture, "Krypton Transmute\n\nDocuments convert through textutil.\n")
    check(fileExists(textFixture), "text fixture created")
    check(isDocument(textFixture) == 1, "plain text counts as a document")
    check(isDocument(fixture) == 0, "images do not count as documents")

    let d = 0
    while d < docFormatCount() {
        let out = convertDocument(textFixture, d, dir, "-doc-" + docFormatName(d))
        check(fileExists(out), docFormatName(d) + " document written")
        check(extOf(out) == docFormatExtension(d), docFormatName(d) + " document extension")
        check(fileBytes(out) > 20, docFormatName(d) + " document has content")
        d += 1
    }

    let pdfDoc = convertDocument(textFixture, 9, dir, "-print")
    check(trim(exec("head -c 4 " + shq(pdfDoc))) == "%PDF", "PDF output is a real PDF")

    let rtfIn = dir + "/rich.rtf"
    shellRun("textutil -convert rtf -output " + shq(rtfIn) + " " + shq(textFixture) + " >/dev/null 2>&1")
    check(fileExists(rtfIn), "RTF fixture created")
    let backToDocx = convertDocument(rtfIn, 5, dir, "-word")
    check(fileExists(backToDocx), "RTF converts to DOCX")
    check(contains(toLower(trim(exec("textutil -convert txt -stdout " + shq(backToDocx) + " 2>/dev/null"))), "krypton transmute") == 1, "DOCX keeps the text")

    let foundDocs = scanDocuments(dir)
    check(lineCount(foundDocs) >= docFormatCount(), "folder scan finds every document")

    // Audio
    let audioFixture = "/System/Library/Sounds/Ping.aiff"
    check(fileExists(audioFixture), "system audio fixture present")
    check(isAudio(audioFixture) == 1, "aiff counts as audio")
    check(isAudio(fixture) == 0, "images do not count as audio")
    check(audioLength(audioFixture) == "0:01", "audio length is m:ss")
    check(contains(audioInfo(audioFixture), "48000") == 1, "audio format reports sample rate")

    let a = 0
    while a < audioFormatCount() {
        let out = convertAudio(audioFixture, a, "128", dir, "-audio-" + audioFormatName(a))
        check(fileExists(out), audioFormatName(a) + " audio written")
        check(extOf(out) == audioFormatExtension(a), audioFormatName(a) + " audio extension")
        check(fileBytes(out) > 1000, audioFormatName(a) + " audio has content")
        check(contains(exec("afinfo " + shq(out) + " 2>/dev/null"), "estimated duration") == 1, audioFormatName(a) + " is readable audio")
        a += 1
    }

    let lowRate = convertAudio(audioFixture, 0, "64", dir, "-aac64")
    let highRate = convertAudio(audioFixture, 0, "256", dir, "-aac256")
    check(fileBytes(highRate) > fileBytes(lowRate), "higher AAC bitrate writes more data")
    check(lineCount(scanAudio("/System/Library/Sounds")) > 3, "audio folder scan")

    // Toolbox
    check(toolboxReady() == 1, "toolbox back end installed")
    check(toolFormatTotal() == 28, "grouped format list totals 28")
    check(toolCategoryForFormat(0) == 0, "first format is video")
    check(toolCategoryForFormat(27) == 7, "last format is a mesh")
    check(toolLocalIndex(27) == 2, "mesh format index is local")
    check(toolCategoryForExt("csv") == 1, "csv belongs to tables")
    check(toolCategoryForExt("png") == -1, "png is not a toolbox family")
    check(toolAccepts(1, "x.csv") == 1, "tables accept csv")
    check(toolAccepts(1, "x.png") == 0, "tables reject png")
    check(len(trim(exec("command -v avconvert"))) > 0, "avconvert present for video")
    check(videoPreset(0, "1080") == "Preset1920x1080", "video preset follows height")
    check(videoPreset(3, "720") == "PresetAppleM4A", "audio-only video preset")

    let csvFixture = dir + "/table.csv"
    writeFile(csvFixture, "name,role,note\nAda,engineer,\"math, logic\"\nGrace,compiler,ship it\n")
    let tsvOut = toolConvert(1, csvFixture, 1, "", dir, "-tsv")
    check(fileExists(tsvOut), "CSV to TSV written")
    check(extOf(tsvOut) == "tsv", "TSV extension")
    let tableJson = toolConvert(1, csvFixture, 2, "", dir, "-tablejson")
    check(contains(exec("cat " + shq(tableJson)), "\"name\": \"Ada\"") == 1, "CSV to JSON keeps cells")

    let xlsxOut = toolConvert(1, csvFixture, 3, "", dir, "-xlsx")
    check(fileExists(xlsxOut), "CSV to XLSX written")
    check(contains(exec("unzip -l " + shq(xlsxOut)), "xl/workbook.xml") == 1, "XLSX is a real package")
    let csvBack = toolConvert(1, xlsxOut, 0, "", dir, "-csvback")
    check(contains(exec("cat " + shq(csvBack)), "Grace") == 1, "XLSX reads back to CSV")
    check(contains(toolInfo(1, xlsxOut), "2 rows") == 1, "table detail counts rows")

    let dataJson = dir + "/data.json"
    writeFile(dataJson, "{\"title\":\"Demo\",\"count\":3,\"tags\":[\"a\",\"b\"],\"owner\":{\"name\":\"Ada\"}}")
    let yamlOut = toolConvert(2, dataJson, 1, "", dir, "-yaml")
    check(fileExists(yamlOut), "JSON to YAML written")
    check(contains(exec("cat " + shq(yamlOut)), "title: Demo") == 1, "YAML keeps values")
    let tomlOut = toolConvert(2, dataJson, 2, "", dir, "-toml")
    check(contains(exec("cat " + shq(tomlOut)), "[owner]") == 1, "TOML writes nested tables")
    let xmlOut = toolConvert(2, dataJson, 3, "", dir, "-structxml")
    check(contains(exec("cat " + shq(xmlOut)), "<owner>") == 1, "XML nests objects")
    let dataBack = toolConvert(2, yamlOut, 0, "", dir, "-jsonback")
    check(contains(exec("cat " + shq(dataBack)), "\"title\": \"Demo\"") == 1, "YAML round-trips to JSON")

    let mdFixture = dir + "/page.md"
    writeFile(mdFixture, "# Title\n\nSome **bold** text and `code`.\n\n- one\n- two\n")
    let htmlOut = toolConvert(3, mdFixture, 0, "", dir, "-html")
    check(contains(exec("cat " + shq(htmlOut)), "<h1>Title</h1>") == 1, "Markdown heading to HTML")
    check(contains(exec("cat " + shq(htmlOut)), "<strong>bold</strong>") == 1, "Markdown bold to HTML")
    let mdBack = toolConvert(3, htmlOut, 1, "", dir, "-md")
    check(contains(exec("cat " + shq(mdBack)), "# Title") == 1, "HTML reads back to Markdown")
    let plainOut = toolConvert(3, mdFixture, 2, "", dir, "-plain")
    check(contains(exec("cat " + shq(plainOut)), "Some bold text") == 1, "Markdown to text strips markers")

    let epubOut = toolConvert(4, mdFixture, 0, "Demo Book", dir, "-book")
    check(fileExists(epubOut), "EPUB written")
    check(contains(exec("unzip -l " + shq(epubOut)), "mimetype") == 1, "EPUB carries its mimetype")
    check(contains(exec("unzip -p " + shq(epubOut) + " OEBPS/content.opf"), "Demo Book") == 1, "EPUB uses the given title")
    let epubTxt = toolConvert(4, epubOut, 2, "", dir, "-epubtxt")
    check(contains(exec("cat " + shq(epubTxt)), "Title") == 1, "EPUB reads back to text")

    let srtFixture = dir + "/cues.srt"
    writeFile(srtFixture, "1\n00:00:01,000 --> 00:00:03,500\nHello there\n\n2\n00:00:04,000 --> 00:00:06,000\nSecond line\n")
    let vttOut = toolConvert(5, srtFixture, 1, "", dir, "-vtt")
    check(contains(exec("cat " + shq(vttOut)), "WEBVTT") == 1, "SRT to VTT header")
    check(contains(exec("cat " + shq(vttOut)), "00:00:01.000 --> 00:00:03.500") == 1, "VTT keeps timings")
    let assOut = toolConvert(5, srtFixture, 2, "", dir, "-ass")
    check(contains(exec("cat " + shq(assOut)), "Dialogue: 0,00:00:01,00:00:03") == 1, "SRT to ASS events")
    let srtBack = toolConvert(5, vttOut, 0, "", dir, "-srtback")
    check(contains(exec("cat " + shq(srtBack)), "Hello there") == 1, "VTT back to SRT")

    let zipFixture = dir + "/bundle.zip"
    shellRun("cd " + shq(dir) + " && zip -q " + shq(baseName(zipFixture)) +
        " " + shq(baseName(csvFixture)) + " >/dev/null 2>&1")
    check(fileExists(zipFixture), "zip fixture created")
    let tarOut = toolConvert(6, zipFixture, 1, "", dir, "-tar")
    check(contains(exec("tar -tf " + shq(tarOut)), baseName(csvFixture)) == 1, "ZIP to TAR keeps files")
    let tgzOut = toolConvert(6, tarOut, 2, "", dir, "-tgz")
    check(contains(exec("tar -tzf " + shq(tgzOut)), baseName(csvFixture)) == 1, "TAR to TGZ keeps files")

    let objFixture = dir + "/tri.obj"
    writeFile(objFixture, "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n")
    let stlOut = toolConvert(7, objFixture, 1, "", dir, "-stl")
    check(contains(exec("head -1 " + shq(stlOut)), "solid") == 1, "OBJ to ASCII STL")
    let plyOut = toolConvert(7, objFixture, 2, "", dir, "-ply")
    check(contains(exec("head -1 " + shq(plyOut)), "ply") == 1, "OBJ to PLY")
    let objBack = toolConvert(7, plyOut, 0, "", dir, "-objback")
    check(contains(exec("cat " + shq(objBack)), "f 1 2 3") == 1, "PLY back to OBJ")
    check(contains(toolInfo(7, stlOut), "1 tris") == 1, "mesh detail counts triangles")
    check(lineCount(toolScan(6, dir)) >= 1, "toolbox folder scan")

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
