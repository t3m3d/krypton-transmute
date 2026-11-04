#!/usr/bin/env python3
"""Krypton Transmute toolbox back end.

macOS ships no pandoc, ffmpeg or 7-Zip, so the parser-heavy families run here
on the Python standard library, while media stays on Apple's own tools
(avconvert, sips, textutil, afconvert). Krypton calls this script as:

    toolkit.py convert <family> <format> <source> <output> [option]
    toolkit.py info <family> <path>

Families: tables, data, markup, ebook, subs, archive, models.
Exit status is 0 on success; failures explain themselves on stderr.
"""

import base64
import csv
import hashlib
import html as htmllib
import io
import json
import os
import re
import shutil
import struct
import sys
import tarfile
import tempfile
import zipfile
import xml.etree.ElementTree as ET
from html.parser import HTMLParser


# ── shared helpers ───────────────────────────────────────────────────

def read_text(path):
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        return f.read()


def write_text(path, text):
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)


def ext_of(path):
    name = os.path.basename(path).lower()
    if name.endswith('.tar.gz'):
        return 'tar.gz'
    return name.rsplit('.', 1)[-1] if '.' in name else ''


def esc(text):
    return (str(text).replace('&', '&amp;').replace('<', '&lt;')
            .replace('>', '&gt;').replace('"', '&quot;'))


# ── tables: csv / tsv / json / xlsx ──────────────────────────────────

def table_cell(value):
    if value is None:
        return ''
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return str(value)
    return str(value)


def read_table(path):
    ext = ext_of(path)
    if ext in ('csv', 'tsv'):
        delimiter = ',' if ext == 'csv' else '\t'
        with open(path, newline='', encoding='utf-8', errors='replace') as f:
            rows = [list(r) for r in csv.reader(f, delimiter=delimiter)]
        rows = [r for r in rows if any(str(c).strip() for c in r)]
        if not rows:
            return [], []
        return rows[0], rows[1:]

    if ext == 'json':
        data = json.loads(read_text(path))
        if isinstance(data, dict) and isinstance(data.get('rows'), list):
            data = data['rows']
        if not isinstance(data, list):
            raise ValueError('table JSON must be an array of objects or arrays')
        if data and isinstance(data[0], dict):
            header = []
            for row in data:
                for key in row.keys():
                    if key not in header:
                        header.append(key)
            return header, [[table_cell(row.get(k, '')) for k in header] for row in data]
        rows = [[table_cell(c) for c in (row if isinstance(row, list) else [row])] for row in data]
        width = max((len(r) for r in rows), default=0)
        return ['column%d' % (i + 1) for i in range(width)], rows

    if ext == 'xlsx':
        return read_xlsx(path)
    raise ValueError('unsupported table source .' + ext)


def column_index(ref):
    letters = ''.join(ch for ch in ref if ch.isalpha())
    value = 0
    for ch in letters:
        value = value * 26 + (ord(ch.upper()) - 64)
    return max(value - 1, 0)


def read_xlsx(path):
    ns = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'
    with zipfile.ZipFile(path) as book:
        shared = []
        try:
            root = ET.fromstring(book.read('xl/sharedStrings.xml'))
            for si in root.findall(ns + 'si'):
                shared.append(''.join(t.text or '' for t in si.iter(ns + 't')))
        except KeyError:
            pass

        sheet_name = None
        for name in book.namelist():
            if re.match(r'xl/worksheets/sheet\d+\.xml$', name):
                sheet_name = name
                break
        if sheet_name is None:
            raise ValueError('workbook has no worksheet')
        root = ET.fromstring(book.read(sheet_name))

    rows = []
    for row in root.iter(ns + 'row'):
        cells = []
        for cell in row.findall(ns + 'c'):
            while len(cells) < column_index(cell.get('r') or ''):
                cells.append('')
            kind = cell.get('t')
            value = cell.find(ns + 'v')
            if kind == 'inlineStr':
                text = ''.join(t.text or '' for t in cell.iter(ns + 't'))
            elif kind == 's':
                text = shared[int(value.text)] if value is not None and value.text else ''
            elif kind == 'b':
                text = 'true' if value is not None and value.text == '1' else 'false'
            else:
                text = value.text if value is not None and value.text is not None else ''
            cells.append(text or '')
        rows.append(cells)
    if not rows:
        return [], []
    width = max(len(r) for r in rows)
    rows = [r + [''] * (width - len(r)) for r in rows]
    return rows[0], rows[1:]


def _col_letter(index):
    label = ''
    index += 1
    while index:
        index, rem = divmod(index - 1, 26)
        label = chr(65 + rem) + label
    return label


def write_xlsx(path, header, rows):
    def cell(ref, value):
        text = str(value)
        if text == '':
            return ''
        if re.fullmatch(r'-?\d+', text) or re.fullmatch(r'-?\d*\.\d+', text):
            return '<c r="%s"><v>%s</v></c>' % (ref, text)
        return ('<c r="%s" t="inlineStr"><is><t xml:space="preserve">%s</t></is></c>'
                % (ref, esc(text)))

    body = []
    for ri, row in enumerate([header] + rows):
        cells = ''.join(cell(_col_letter(ci) + str(ri + 1), v) for ci, v in enumerate(row))
        body.append('<row r="%d">%s</row>' % (ri + 1, cells))

    sheet = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
             '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
             '<sheetData>%s</sheetData></worksheet>') % ''.join(body)
    types = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
             '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
             '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
             '<Default Extension="xml" ContentType="application/xml"/>'
             '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
             '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
             '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
             '</Types>')
    rels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
            '</Relationships>')
    workbook = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
                'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
                '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>')
    workbook_rels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                     '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                     '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
                     '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
                     '</Relationships>')
    styles = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
              '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>'
              '<fills count="1"><fill><patternFill patternType="none"/></fill></fills>'
              '<borders count="1"><border/></borders>'
              '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
              '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>'
              '</styleSheet>')

    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as book:
        book.writestr('[Content_Types].xml', types)
        book.writestr('_rels/.rels', rels)
        book.writestr('xl/workbook.xml', workbook)
        book.writestr('xl/_rels/workbook.xml.rels', workbook_rels)
        book.writestr('xl/styles.xml', styles)
        book.writestr('xl/worksheets/sheet1.xml', sheet)


def write_table(path, fmt, header, rows):
    if fmt in ('csv', 'tsv'):
        with open(path, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f, delimiter=',' if fmt == 'csv' else '\t',
                                lineterminator='\n')
            writer.writerow(header)
            writer.writerows(rows)
    elif fmt == 'json':
        payload = [dict(zip(header, row)) for row in rows]
        write_text(path, json.dumps(payload, indent=2, ensure_ascii=False) + '\n')
    elif fmt == 'xlsx':
        write_xlsx(path, header, rows)
    else:
        raise ValueError('unsupported table target ' + fmt)


def convert_table(fmt, src, dst):
    header, rows = read_table(src)
    write_table(dst, fmt, header, rows)


# ── structured data: json / yaml / toml / xml ────────────────────────

def load_data(path):
    ext = ext_of(path)
    text = read_text(path)
    if ext == 'json':
        return json.loads(text)
    if ext in ('yaml', 'yml'):
        return yaml_load(text)
    if ext == 'toml':
        return toml_load(text)
    if ext == 'xml':
        return xml_load(text)
    if ext in ('plist',):
        return xml_load(text)
    raise ValueError('unsupported data source .' + ext)


def split_inline(text):
    parts, buf, quote, depth = [], '', '', 0
    for ch in text:
        if quote:
            buf += ch
            if ch == quote:
                quote = ''
        elif ch in ('"', "'"):
            quote = ch
            buf += ch
        elif ch in '[{':
            depth += 1
            buf += ch
        elif ch in ']}':
            depth -= 1
            buf += ch
        elif ch == ',' and depth == 0:
            parts.append(buf)
            buf = ''
        else:
            buf += ch
    if buf.strip():
        parts.append(buf)
    return [p.strip() for p in parts]


def yaml_scalar(text):
    s = text.strip()
    if s in ('', '~', 'null', 'Null', 'NULL'):
        return None
    if s in ('true', 'True', 'TRUE'):
        return True
    if s in ('false', 'False', 'FALSE'):
        return False
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ('"', "'"):
        body = s[1:-1]
        return body.replace("''", "'") if s[0] == "'" else body
    if s.startswith('[') and s.endswith(']'):
        return [yaml_scalar(x) for x in split_inline(s[1:-1])]
    if s.startswith('{') and s.endswith('}'):
        out = {}
        for part in split_inline(s[1:-1]):
            if ':' in part:
                key, value = part.split(':', 1)
                out[key.strip().strip('\'"')] = yaml_scalar(value)
        return out
    try:
        return int(s)
    except ValueError:
        pass
    try:
        return float(s)
    except ValueError:
        pass
    return s


def _yaml_lines(text):
    lines = []
    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith('#'):
            continue
        if raw.strip() in ('---', '...'):
            continue
        lines.append([len(raw) - len(raw.lstrip(' ')), raw.strip()])
    return lines


def yaml_load(text):
    lines = _yaml_lines(text)
    if not lines:
        return {}
    value, _ = yaml_block(lines, 0, lines[0][0])
    return value


def _next_indent(lines, index, fallback):
    return lines[index + 1][0] if index + 1 < len(lines) else fallback + 2


def yaml_block(lines, index, indent):
    if index >= len(lines):
        return None, index

    first = lines[index][1]
    is_list = first == '-' or first.startswith('- ')
    node = [] if is_list else {}

    while index < len(lines) and lines[index][0] == indent:
        text = lines[index][1]

        if is_list:
            if not (text == '-' or text.startswith('- ')):
                break
            item = text[1:].strip()
            if item == '':
                child, index = yaml_block(lines, index + 1, _next_indent(lines, index, indent))
                node.append(child)
                continue
            if ':' in item and not item.startswith(('"', "'")):
                key, value = item.split(':', 1)
                entry = {}
                if value.strip():
                    entry[key.strip()] = yaml_scalar(value)
                    index += 1
                else:
                    child, index = yaml_block(lines, index + 1, _next_indent(lines, index, indent))
                    entry[key.strip()] = child
                # sibling keys of the same list item sit one level deeper
                while index < len(lines) and lines[index][0] > indent and not lines[index][1].startswith('- '):
                    block, index = yaml_block(lines, index, lines[index][0])
                    if isinstance(block, dict):
                        entry.update(block)
                node.append(entry)
                continue
            node.append(yaml_scalar(item))
            index += 1
            continue

        if ':' not in text:
            break
        key, value = text.split(':', 1)
        key = key.strip().strip('\'"')
        if value.strip():
            node[key] = yaml_scalar(value)
            index += 1
        else:
            child, index = yaml_block(lines, index + 1, _next_indent(lines, index, indent))
            node[key] = child

    return node, index


def yaml_key(key):
    text = str(key)
    if re.fullmatch(r'[A-Za-z0-9_.-]+', text):
        return text
    return json.dumps(text)


def yaml_render(value):
    if value is None:
        return 'null'
    if value is True:
        return 'true'
    if value is False:
        return 'false'
    if isinstance(value, (int, float)):
        return repr(value) if isinstance(value, float) else str(value)
    if isinstance(value, (list, dict)):
        if not value:
            return '[]' if isinstance(value, list) else '{}'
        return json.dumps(value, ensure_ascii=False)
    text = str(value)
    if text == '' or re.search(r'[:#\[\]{},&*!|>%@`]', text) or text.strip() != text:
        return json.dumps(text, ensure_ascii=False)
    return text


def yaml_dump(value, indent=0):
    pad = '  ' * indent
    if isinstance(value, dict):
        if not value:
            return pad + '{}\n'
        out = ''
        for key, item in value.items():
            if isinstance(item, (dict, list)) and item:
                out += '%s%s:\n%s' % (pad, yaml_key(key), yaml_dump(item, indent + 1))
            else:
                out += '%s%s: %s\n' % (pad, yaml_key(key), yaml_render(item))
        return out
    if isinstance(value, list):
        if not value:
            return pad + '[]\n'
        out = ''
        for item in value:
            if isinstance(item, dict) and item:
                rendered = yaml_dump(item, indent + 1).splitlines()
                out += '%s- %s\n' % (pad, rendered[0].strip())
                for line in rendered[1:]:
                    out += line + '\n'
            elif isinstance(item, list) and item:
                out += '%s-\n%s' % (pad, yaml_dump(item, indent + 1))
            else:
                out += '%s- %s\n' % (pad, yaml_render(item))
        return out
    return pad + yaml_render(value) + '\n'


def strip_comment(line):
    quote = ''
    for i, ch in enumerate(line):
        if quote:
            if ch == quote:
                quote = ''
        elif ch in ('"', "'"):
            quote = ch
        elif ch == '#':
            return line[:i]
    return line


def toml_value(text):
    s = text.strip()
    if s.startswith('"') and s.endswith('"') and len(s) >= 2:
        return s[1:-1].replace('\\n', '\n').replace('\\t', '\t').replace('\\"', '"')
    if s.startswith("'") and s.endswith("'") and len(s) >= 2:
        return s[1:-1]
    if s in ('true', 'false'):
        return s == 'true'
    if s.startswith('[') and s.endswith(']'):
        return [toml_value(x) for x in split_inline(s[1:-1])]
    if s.startswith('{') and s.endswith('}'):
        out = {}
        for part in split_inline(s[1:-1]):
            if '=' in part:
                key, value = part.split('=', 1)
                out[key.strip().strip('\'"')] = toml_value(value)
        return out
    try:
        return int(s.replace('_', ''))
    except ValueError:
        pass
    try:
        return float(s.replace('_', ''))
    except ValueError:
        pass
    return s


def toml_load(text):
    root = {}
    current = root
    for raw in text.splitlines():
        line = strip_comment(raw).strip()
        if not line:
            continue
        if line.startswith('[[') and line.endswith(']]'):
            path = [p.strip().strip('\'"') for p in line[2:-2].split('.')]
            parent = root
            for part in path[:-1]:
                parent = parent.setdefault(part, {})
            table = parent.setdefault(path[-1], [])
            if not isinstance(table, list):
                raise ValueError('TOML array-of-tables conflicts with a table')
            current = {}
            table.append(current)
            continue
        if line.startswith('[') and line.endswith(']'):
            path = [p.strip().strip('\'"') for p in line[1:-1].split('.')]
            current = root
            for part in path:
                current = current.setdefault(part, {})
            continue
        if '=' not in line:
            continue
        key, value = line.split('=', 1)
        keys = [p.strip().strip('\'"') for p in key.split('.')]
        target = current
        for part in keys[:-1]:
            target = target.setdefault(part, {})
        target[keys[-1]] = toml_value(value)

    def build(node):
        if isinstance(node, dict):
            return {k: build(v) for k, v in node.items()}
        if isinstance(node, list) and node and all(isinstance(x, (dict, list)) for x in node):
            return [build(x) for x in node]
        return node

    return build(root)


def toml_key(key):
    text = str(key)
    return text if re.fullmatch(r'[A-Za-z0-9_-]+', text) else json.dumps(text)


def toml_render(value):
    if value is None:
        return '""'
    if value is True:
        return 'true'
    if value is False:
        return 'false'
    if isinstance(value, (int, float)):
        return repr(value) if isinstance(value, float) else str(value)
    if isinstance(value, list):
        return '[%s]' % ', '.join(toml_render(v) for v in value)
    if isinstance(value, dict):
        return '{%s}' % ', '.join('%s = %s' % (toml_key(k), toml_render(v))
                                  for k, v in value.items())
    return json.dumps(str(value), ensure_ascii=False)


def toml_dump(value, prefix=''):
    if not isinstance(value, dict):
        raise ValueError('TOML needs a table at the top level')
    scalars, tables, arrays = [], [], []
    for key, item in value.items():
        if isinstance(item, dict):
            tables.append((key, item))
        elif isinstance(item, list) and item and all(isinstance(x, dict) for x in item):
            arrays.append((key, item))
        else:
            scalars.append((key, item))

    out = ''
    for key, item in scalars:
        out += '%s = %s\n' % (toml_key(key), toml_render(item))
    for key, item in tables:
        path = prefix + toml_key(key)
        out += '\n[%s]\n' % path + toml_dump(item, path + '.')
    for key, item in arrays:
        path = prefix + toml_key(key)
        for entry in item:
            out += '\n[[%s]]\n' % path + toml_dump(entry, path + '.')
    return out


def xml_node(element):
    children = list(element)
    if not children:
        return (element.text or '').strip()
    out = {}
    for key, value in element.attrib.items():
        out['@' + key] = value
    for child in children:
        value = xml_node(child)
        if child.tag in out:
            if not isinstance(out[child.tag], list):
                out[child.tag] = [out[child.tag]]
            out[child.tag].append(value)
        else:
            out[child.tag] = value
    text = (element.text or '').strip()
    if text:
        out['#text'] = text
    return out


def xml_load(text):
    root = ET.fromstring(text)
    return {root.tag: xml_node(root)}


def xml_dump(value):
    def build(tag, node):
        element = ET.Element(str(tag))
        if isinstance(node, dict):
            for key, item in node.items():
                if key.startswith('@'):
                    element.set(str(key[1:]), str(item))
                elif key == '#text':
                    element.text = str(item)
                else:
                    element.append(build(key, item))
        elif isinstance(node, list):
            for item in node:
                element.append(build('item', item))
        else:
            if isinstance(node, bool):
                element.text = 'true' if node else 'false'
            else:
                element.text = '' if node is None else str(node)
        return element

    tag = 'root'
    payload = value
    if isinstance(value, dict) and len(value) == 1:
        only = list(value.keys())[0]
        if isinstance(value[only], (dict, list)):
            tag, payload = only, value[only]
    root = build(tag, payload)
    ET.indent(root, space='  ')
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(root, encoding='unicode') + '\n'


def convert_data(fmt, src, dst):
    value = load_data(src)
    if fmt == 'json':
        write_text(dst, json.dumps(value, indent=2, ensure_ascii=False) + '\n')
    elif fmt in ('yaml', 'yml'):
        write_text(dst, yaml_dump(value))
    elif fmt == 'toml':
        write_text(dst, toml_dump(value))
    elif fmt == 'xml':
        write_text(dst, xml_dump(value))
    else:
        raise ValueError('unsupported data target ' + fmt)


# ── markup: markdown / html / text ──────────────────────────────────

def md_inline(text):
    s = esc(text)
    s = re.sub(r'!\[([^\]]*)\]\(([^)]+)\)', r'<img alt="\1" src="\2">', s)
    s = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2">\1</a>', s)
    s = re.sub(r'`([^`]+)`', r'<code>\1</code>', s)
    s = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', s)
    s = re.sub(r'__([^_]+)__', r'<strong>\1</strong>', s)
    s = re.sub(r'\*([^*]+)\*', r'<em>\1</em>', s)
    s = re.sub(r'_([^_]+)_', r'<em>\1</em>', s)
    return s


def md_to_html(md):
    lines = md.splitlines()
    out, i = [], 0
    in_code, code = False, []
    list_open = None

    def close_list():
        nonlocal list_open
        if list_open:
            out.append('</%s>' % list_open)
            list_open = None

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if stripped.startswith('```'):
            if in_code:
                out.append('<pre><code>' + esc('\n'.join(code)) + '</code></pre>')
                in_code, code = False, []
            else:
                in_code = True
            i += 1
            continue
        if in_code:
            code.append(line)
            i += 1
            continue
        if not stripped:
            close_list()
            i += 1
            continue

        heading = re.match(r'^(#{1,6})\s+(.*)$', stripped)
        if heading:
            close_list()
            level = len(heading.group(1))
            out.append('<h%d>%s</h%d>' % (level, md_inline(heading.group(2)), level))
            i += 1
            continue

        if re.match(r'^([-*_])\1{2,}$', stripped):
            close_list()
            out.append('<hr>')
            i += 1
            continue

        if stripped.startswith('>'):
            close_list()
            quote = []
            while i < len(lines) and lines[i].strip().startswith('>'):
                quote.append(lines[i].strip()[1:].strip())
                i += 1
            out.append('<blockquote>' + md_to_html('\n'.join(quote)) + '</blockquote>')
            continue

        bullet = re.match(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$', line)
        if bullet:
            tag = 'ol' if bullet.group(2)[0].isdigit() else 'ul'
            if list_open != tag:
                close_list()
                out.append('<%s>' % tag)
                list_open = tag
            out.append('<li>' + md_inline(bullet.group(3)) + '</li>')
            i += 1
            continue

        paragraph = [stripped]
        i += 1
        while i < len(lines):
            nxt = lines[i].strip()
            if not nxt or re.match(r'^(#{1,6}\s|[-*+]\s|\d+[.)]\s|>|```)', nxt):
                break
            paragraph.append(nxt)
            i += 1
        close_list()
        out.append('<p>' + md_inline(' '.join(paragraph)) + '</p>')

    if in_code:
        out.append('<pre><code>' + esc('\n'.join(code)) + '</code></pre>')
    close_list()
    return '\n'.join(out) + '\n'


def md_to_text(md):
    out, in_code = [], False
    for line in md.splitlines():
        if line.strip().startswith('```'):
            in_code = not in_code
            continue
        if in_code:
            out.append(line)
            continue
        s = line
        s = re.sub(r'^#{1,6}\s*', '', s)
        s = re.sub(r'^>\s?', '', s)
        s = re.sub(r'^(\s*)[-*+]\s+', r'\1', s)
        s = re.sub(r'!\[([^\]]*)\]\([^)]+\)', r'\1', s)
        s = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', s)
        s = s.replace('**', '').replace('__', '').replace('`', '')
        s = re.sub(r'(?<!\w)[*_](\S.*?\S)[*_](?!\w)', r'\1', s)
        out.append(s)
    return '\n'.join(out).strip() + '\n'


class MarkdownParser(HTMLParser):
    block_tags = ('p', 'div', 'br', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li',
                  'tr', 'pre', 'blockquote', 'hr', 'section', 'article')

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts, self.skip = [], 0

    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style', 'head'):
            self.skip += 1
        elif tag in self.block_tags:
            self.parts.append('\n')

    def handle_endtag(self, tag):
        if tag in ('script', 'style', 'head'):
            self.skip = max(0, self.skip - 1)
        elif tag in self.block_tags:
            self.parts.append('\n')

    def handle_data(self, data):
        if not self.skip:
            self.parts.append(data)


def html_to_text(markup):
    parser = MarkdownParser()
    parser.feed(markup)
    text = ''.join(parser.parts)
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r' *\n *', '\n', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip() + '\n'


class HtmlToMarkdown(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out, self.skip, self.href, self.pre = [], 0, '', 0
        self.lists = []

    def handle_starttag(self, tag, attrs):
        attr = dict(attrs)
        if tag in ('script', 'style', 'head'):
            self.skip += 1
            return
        if tag in ('h1', 'h2', 'h3', 'h4', 'h5', 'h6'):
            self.out.append('\n\n' + '#' * int(tag[1]) + ' ')
        elif tag == 'p':
            self.out.append('\n\n')
        elif tag == 'br':
            self.out.append('  \n')
        elif tag == 'hr':
            self.out.append('\n\n---\n\n')
        elif tag == 'li':
            self.out.append('\n' + '  ' * len(self.lists) + '- ')
        elif tag in ('ul', 'ol'):
            self.out.append('\n')
            self.lists.append(tag)
        elif tag == 'blockquote':
            self.out.append('\n\n> ')
        elif tag == 'pre':
            self.out.append('\n\n```\n')
            self.pre += 1
        elif tag == 'code' and not self.pre:
            self.out.append('`')
        elif tag in ('strong', 'b'):
            self.out.append('**')
        elif tag in ('em', 'i'):
            self.out.append('*')
        elif tag == 'a':
            self.href = attr.get('href', '')
            self.out.append('[')
        elif tag == 'img':
            self.out.append('![%s](%s)' % (attr.get('alt', ''), attr.get('src', '')))

    def handle_endtag(self, tag):
        if tag in ('script', 'style', 'head'):
            self.skip = max(0, self.skip - 1)
            return
        if tag in ('h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p'):
            self.out.append('\n')
        elif tag in ('ul', 'ol'):
            self.out.append('\n')
            if self.lists:
                self.lists.pop()
        elif tag == 'pre':
            self.out.append('\n```\n\n')
            self.pre = max(0, self.pre - 1)
        elif tag == 'code' and not self.pre:
            self.out.append('`')
        elif tag in ('strong', 'b'):
            self.out.append('**')
        elif tag in ('em', 'i'):
            self.out.append('*')
        elif tag == 'a':
            self.out.append('](%s)' % self.href)
            self.href = ''

    def handle_data(self, data):
        if self.skip:
            return
        self.out.append(data if self.pre else re.sub(r'\s+', ' ', data))


def html_to_md(markup):
    parser = HtmlToMarkdown()
    parser.feed(markup)
    text = ''.join(parser.out)
    text = re.sub(r'[ \t]+\n', '\n', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip() + '\n'


def text_to_html(text):
    blocks = re.split(r'\n\s*\n', text.strip())
    if not blocks:
        return '<p></p>\n'
    return '\n'.join('<p>' + esc(b).replace('\n', '<br>') + '</p>' for b in blocks) + '\n'


def convert_markup(fmt, src, dst):
    ext = ext_of(src)
    text = read_text(src)
    is_html = ext in ('html', 'htm', 'xhtml')
    is_md = ext in ('md', 'markdown')

    if fmt == 'html':
        if is_html:
            write_text(dst, text)
        elif is_md:
            write_text(dst, md_to_html(text))
        else:
            write_text(dst, text_to_html(text))
    elif fmt in ('md', 'markdown'):
        write_text(dst, html_to_md(text) if is_html else (text if is_md else text))
    elif fmt == 'txt':
        if is_html:
            write_text(dst, html_to_text(text))
        elif is_md:
            write_text(dst, md_to_text(text))
        else:
            write_text(dst, text)
    else:
        raise ValueError('unsupported markup target ' + fmt)


# ── e-books: epub / html / text / markdown ──────────────────────────

def epub_body(path):
    with zipfile.ZipFile(path) as book:
        names = book.namelist()
        container = None
        if 'META-INF/container.xml' in names:
            container = ET.fromstring(book.read('META-INF/container.xml'))
        opf_path = None
        if container is not None:
            for element in container.iter():
                if element.tag.endswith('rootfile'):
                    opf_path = element.get('full-path')
                    break

        docs = []
        if opf_path and opf_path in names:
            opf = ET.fromstring(book.read(opf_path))
            base = os.path.dirname(opf_path)
            manifest, order = {}, []
            for element in opf.iter():
                if element.tag.endswith('item'):
                    manifest[element.get('id')] = element.get('href')
                elif element.tag.endswith('itemref'):
                    order.append(element.get('idref'))
            for idref in order:
                href = manifest.get(idref)
                if not href:
                    continue
                full = os.path.normpath(os.path.join(base, href)).replace('\\', '/')
                if full in names:
                    docs.append(book.read(full).decode('utf-8', 'replace'))
        if not docs:
            for name in names:
                if name.lower().endswith(('.xhtml', '.html', '.htm')):
                    docs.append(book.read(name).decode('utf-8', 'replace'))
        if not docs:
            raise ValueError('epub has no readable documents')
        return '\n<hr>\n'.join(body_of(doc) for doc in docs)


def body_of(markup):
    match = re.search(r'<body[^>]*>(.*?)</body>', markup, re.S | re.I)
    return match.group(1) if match else markup


def make_epub(body_html, title):
    digest = hashlib.md5(title.encode('utf-8')).hexdigest()[:16]
    chapter = ('<?xml version="1.0" encoding="UTF-8"?>\n'
               '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>%s</title>'
               '<meta charset="utf-8"/></head><body>%s</body></html>'
               % (esc(title), body_html))
    container = ('<?xml version="1.0" encoding="UTF-8"?>'
                 '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
                 '<rootfiles><rootfile full-path="OEBPS/content.opf" '
                 'media-type="application/oebps-package+xml"/></rootfiles></container>')
    opf = ('<?xml version="1.0" encoding="UTF-8"?>'
           '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">'
           '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
           '<dc:identifier id="bookid">urn:uuid:krypton-%s</dc:identifier>'
           '<dc:title>%s</dc:title><dc:language>en</dc:language>'
           '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>'
           '</metadata><manifest>'
           '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
           '<item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>'
           '</manifest><spine><itemref idref="c1"/></spine></package>'
           % (digest, esc(title)))
    nav = ('<?xml version="1.0" encoding="UTF-8"?>'
           '<html xmlns="http://www.w3.org/1999/xhtml" '
           'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head>'
           '<body><nav epub:type="toc"><h1>%s</h1><ol><li><a href="chapter1.xhtml">Text</a></li>'
           '</ol></nav></body></html>' % esc(title))
    return chapter, container, opf, nav


def convert_ebook(fmt, src, dst, option):
    ext = ext_of(src)
    title = option.strip() or os.path.splitext(os.path.basename(src))[0]

    if ext == 'epub':
        body = epub_body(src)
        html_doc = ('<?xml version="1.0" encoding="UTF-8"?>\n<html><head><title>%s</title>'
                    '<meta charset="utf-8"/></head><body>%s</body></html>'
                    % (esc(title), body))
        if fmt == 'html':
            write_text(dst, html_doc)
        elif fmt == 'txt':
            write_text(dst, html_to_text(body))
        elif fmt in ('md', 'markdown'):
            write_text(dst, html_to_md(body))
        else:
            raise ValueError('unsupported e-book target ' + fmt)
        return

    text = read_text(src)
    if ext in ('html', 'htm', 'xhtml'):
        body = body_of(text)
        md = html_to_md(body)
    elif ext in ('md', 'markdown'):
        body = md_to_html(text)
        md = text
    else:
        body = text_to_html(text)
        md = text

    if fmt == 'epub':
        chapter, container, opf, nav = make_epub(body, title)
        with zipfile.ZipFile(dst, 'w') as book:
            book.writestr('mimetype', 'application/epub+zip', compress_type=zipfile.ZIP_STORED)
            book.writestr('META-INF/container.xml', container)
            book.writestr('OEBPS/content.opf', opf)
            book.writestr('OEBPS/nav.xhtml', nav)
            book.writestr('OEBPS/chapter1.xhtml', chapter)
    elif fmt == 'html':
        write_text(dst, '<!DOCTYPE html>\n<html><head><meta charset="utf-8"><title>%s</title>'
                        '</head><body>\n%s\n</body></html>\n' % (esc(title), body))
    elif fmt == 'txt':
        write_text(dst, html_to_text(body))
    elif fmt in ('md', 'markdown'):
        write_text(dst, md)
    else:
        raise ValueError('unsupported e-book target ' + fmt)


# ── subtitles: srt / vtt / ass ──────────────────────────────────────

def parse_timestamp(text):
    match = re.match(r'\s*(\d+):(\d{1,2}):(\d{1,2})(?:[.,](\d{1,3}))?', text)
    if not match:
        raise ValueError('bad timestamp: ' + text.strip())
    hours, minutes, seconds, frac = match.groups()
    millis = int((frac or '0').ljust(3, '0')[:3])
    return int(hours) * 3600 + int(minutes) * 60 + int(seconds) + millis / 1000.0


def load_subs(path):
    ext = ext_of(path)
    text = read_text(path).replace('\r\n', '\n').replace('\r', '\n')
    if ext == 'ass' or ext == 'ssa':
        return parse_ass(text)
    if ext == 'vtt':
        return parse_vtt(text)
    return parse_srt(text)


def parse_srt(text):
    cues = []
    for block in re.split(r'\n\s*\n', text.strip()):
        lines = [ln for ln in block.split('\n')]
        if not lines:
            continue
        time_index = 0
        while time_index < len(lines) and '-->' not in lines[time_index]:
            time_index += 1
        if time_index >= len(lines):
            continue
        start_text, end_text = lines[time_index].split('-->', 1)
        cues.append((parse_timestamp(start_text), parse_timestamp(end_text),
                     '\n'.join(lines[time_index + 1:]).strip()))
    return cues


def parse_vtt(text):
    lines = text.split('\n')
    cues = []
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if '-->' in line:
            start_text, rest = line.split('-->', 1)
            end_text = rest.strip().split(' ')[0]
            body, i = [], i + 1
            while i < len(lines) and lines[i].strip():
                body.append(lines[i].strip())
                i += 1
            cues.append((parse_timestamp(start_text), parse_timestamp(end_text),
                         '\n'.join(body)))
        i += 1
    return cues


def parse_ass(text):
    cues = []
    for line in text.split('\n'):
        if not line.startswith('Dialogue:'):
            continue
        parts = line[len('Dialogue:'):].split(',', 9)
        if len(parts) < 10:
            continue
        start = parse_timestamp(parts[1].strip())
        end = parse_timestamp(parts[2].strip())
        body = parts[9].replace('\\N', '\n').replace('\\n', '\n')
        body = re.sub(r'\{[^}]*\}', '', body).strip()
        cues.append((start, end, body))
    return cues


def clock(seconds, sep):
    total = int(round(seconds * 1000))
    hours, rem = divmod(total, 3600000)
    minutes, rem = divmod(rem, 60000)
    secs, millis = divmod(rem, 1000)
    return '%02d:%02d:%02d%s%03d' % (hours, minutes, secs, sep, millis)


def write_srt(cues):
    out = []
    for index, (start, end, body) in enumerate(cues, 1):
        out.append('%d\n%s --> %s\n%s\n' % (index, clock(start, ','), clock(end, ','), body))
    return '\n'.join(out)


def write_vtt(cues):
    out = ['WEBVTT', '']
    for start, end, body in cues:
        out.append('%s --> %s\n%s\n' % (clock(start, '.'), clock(end, '.'), body))
    return '\n'.join(out)


def write_ass(cues):
    header = ('[Script Info]\nScriptType: v4.00+\nWrapStyle: 0\nScaledBorderAndShadow: yes\n\n'
              '[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, '
              'OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, '
              'Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, '
              'MarginV, Encoding\n'
              'Style: Default,Helvetica,20,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,'
              '0,0,0,0,100,100,0,0,1,2,0,2,20,20,20,1\n\n'
              '[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, '
              'Effect, Text\n')
    lines = []
    for start, end, body in cues:
        lines.append('Dialogue: 0,%s,%s,Default,,0,0,0,,%s'
                     % (clock(start, '.')[:-4], clock(end, '.')[:-4],
                        body.replace('\n', '\\N')))
    return header + '\n'.join(lines) + '\n'


def convert_subs(fmt, src, dst):
    cues = load_subs(src)
    if fmt == 'srt':
        write_text(dst, write_srt(cues))
    elif fmt == 'vtt':
        write_text(dst, write_vtt(cues))
    elif fmt == 'ass':
        write_text(dst, write_ass(cues))
    else:
        raise ValueError('unsupported subtitle target ' + fmt)


# ── archives: zip / tar / tgz ───────────────────────────────────────

def safe_join(root, name):
    target = os.path.realpath(os.path.join(root, name))
    base = os.path.realpath(root)
    if target != base and not target.startswith(base + os.sep):
        return None
    return target


def extract_archive(path, root):
    ext = ext_of(path)
    if ext == 'zip':
        with zipfile.ZipFile(path) as archive:
            for member in archive.infolist():
                if safe_join(root, member.filename) is None:
                    continue
                archive.extract(member, root)
        return
    mode = 'r:gz' if ext in ('tgz', 'gz', 'tar.gz') else 'r'
    with tarfile.open(path, mode) as archive:
        for member in archive.getmembers():
            if member.name.startswith('/') or '..' in member.name.split('/'):
                continue
            archive.extract(member, root)


def pack_archive(root, dst, fmt):
    if fmt == 'zip':
        with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as archive:
            for base, dirs, files in os.walk(root):
                for name in sorted(files):
                    full = os.path.join(base, name)
                    archive.write(full, os.path.relpath(full, root))
        return
    mode = 'w:gz' if fmt == 'tgz' else 'w'
    with tarfile.open(dst, mode) as archive:
        for name in sorted(os.listdir(root)):
            archive.add(os.path.join(root, name), arcname=name)


def convert_archive(fmt, src, dst):
    temp = tempfile.mkdtemp(prefix='kt-archive-')
    try:
        extract_archive(src, temp)
        pack_archive(temp, dst, fmt)
    finally:
        shutil.rmtree(temp, ignore_errors=True)


# ── 3D meshes: obj / stl / ply ─────────────────────────────────────

def obj_load(text):
    verts, tris = [], []
    for line in text.splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == 'v' and len(parts) >= 4:
            verts.append((float(parts[1]), float(parts[2]), float(parts[3])))
        elif parts[0] == 'f':
            indices = []
            for token in parts[1:]:
                raw = int(token.split('/')[0])
                indices.append(raw - 1 if raw > 0 else len(verts) + raw)
            for k in range(1, len(indices) - 1):
                tris.append((indices[0], indices[k], indices[k + 1]))
    return verts, tris


def stl_ascii_load(text):
    verts, tris = [], []
    for match in re.finditer(r'facet[^\n]*\n\s*outer loop(.*?)endloop', text, re.S):
        points = re.findall(r'vertex\s+([-\d.eE+]+)\s+([-\d.eE+]+)\s+([-\d.eE+]+)',
                            match.group(1))
        if len(points) != 3:
            continue
        base = len(verts)
        for point in points:
            verts.append(tuple(float(v) for v in point))
        tris.append((base, base + 1, base + 2))
    return verts, tris


def stl_load(path):
    with open(path, 'rb') as handle:
        data = handle.read()
    head = data[:200].lower()
    if head.startswith(b'solid') and b'facet' in head:
        return stl_ascii_load(data.decode('utf-8', 'replace'))
    count = struct.unpack('<I', data[80:84])[0]
    verts, tris, offset = [], [], 84
    for _ in range(count):
        values = struct.unpack('<12fH', data[offset:offset + 50])
        offset += 50
        base = len(verts)
        verts.extend([(values[3], values[4], values[5]),
                      (values[6], values[7], values[8]),
                      (values[9], values[10], values[11])])
        tris.append((base, base + 1, base + 2))
    return verts, tris


def ply_load(text):
    lines = text.splitlines()
    if lines and lines[0].strip() != 'ply':
        raise ValueError('not a PLY file')
    vertex_count = face_count = 0
    index = 0
    while index < len(lines):
        line = lines[index].strip()
        if line.startswith('format') and 'ascii' not in line:
            raise ValueError('only ASCII PLY is supported')
        if line.startswith('element vertex'):
            vertex_count = int(line.split()[-1])
        if line.startswith('element face'):
            face_count = int(line.split()[-1])
        if line == 'end_header':
            break
        index += 1
    index += 1
    verts = []
    for _ in range(vertex_count):
        parts = lines[index].split()
        verts.append((float(parts[0]), float(parts[1]), float(parts[2])))
        index += 1
    tris = []
    for _ in range(face_count):
        parts = lines[index].split()
        count = int(parts[0])
        indices = [int(x) for x in parts[1:1 + count]]
        for k in range(1, count - 1):
            tris.append((indices[0], indices[k], indices[k + 1]))
        index += 1
    return verts, tris


def load_mesh(path):
    ext = ext_of(path)
    if ext == 'obj':
        return obj_load(read_text(path))
    if ext == 'stl':
        return stl_load(path)
    if ext == 'ply':
        return ply_load(read_text(path))
    raise ValueError('unsupported mesh source .' + ext)


def write_obj(path, verts, tris):
    lines = ['# Krypton Transmute', 'o mesh']
    lines += ['v %.6f %.6f %.6f' % v for v in verts]
    lines += ['f %d %d %d' % (a + 1, b + 1, c + 1) for a, b, c in tris]
    write_text(path, '\n'.join(lines) + '\n')


def write_stl(path, verts, tris):
    lines = ['solid krypton']
    for a, b, c in tris:
        lines.append('  facet normal 0 0 0')
        lines.append('    outer loop')
        for index in (a, b, c):
            x, y, z = verts[index]
            lines.append('      vertex %.6f %.6f %.6f' % (x, y, z))
        lines.append('    endloop')
        lines.append('  endfacet')
    lines.append('endsolid krypton')
    write_text(path, '\n'.join(lines) + '\n')


def write_ply(path, verts, tris):
    lines = ['ply', 'format ascii 1.0', 'element vertex %d' % len(verts),
             'property float x', 'property float y', 'property float z',
             'element face %d' % len(tris), 'property list uchar int vertex_indices',
             'end_header']
    lines += ['%.6f %.6f %.6f' % v for v in verts]
    lines += ['3 %d %d %d' % tri for tri in tris]
    write_text(path, '\n'.join(lines) + '\n')


def convert_model(fmt, src, dst):
    verts, tris = load_mesh(src)
    if not tris:
        raise ValueError('mesh has no faces')
    if fmt == 'obj':
        write_obj(dst, verts, tris)
    elif fmt == 'stl':
        write_stl(dst, verts, tris)
    elif fmt == 'ply':
        write_ply(dst, verts, tris)
    else:
        raise ValueError('unsupported mesh target ' + fmt)


# ── info for the queue table ────────────────────────────────────────

def describe(family, path):
    try:
        if family == 'tables':
            header, rows = read_table(path)
            return '%d rows · %d cols' % (len(rows), len(header))
        if family == 'data':
            value = load_data(path)
            if isinstance(value, dict):
                return '%d keys' % len(value)
            if isinstance(value, list):
                return '%d items' % len(value)
            return type(value).__name__
        if family == 'markup':
            return '%d words' % len(read_text(path).split())
        if family == 'ebook':
            return 'epub' if ext_of(path) == 'epub' else '%d words' % len(read_text(path).split())
        if family == 'subs':
            return '%d cues' % len(load_subs(path))
        if family == 'archive':
            ext = ext_of(path)
            if ext == 'zip':
                with zipfile.ZipFile(path) as archive:
                    return '%d files' % len(archive.infolist())
            mode = 'r:gz' if ext in ('tgz', 'gz', 'tar.gz') else 'r'
            with tarfile.open(path, mode) as archive:
                return '%d files' % len(archive.getmembers())
        if family == 'models':
            verts, tris = load_mesh(path)
            return '%d tris' % len(tris)
    except Exception:
        return ''
    return ''


# ── command line ────────────────────────────────────────────────────

def main(argv):
    if len(argv) < 2:
        sys.stderr.write(__doc__)
        return 2
    command = argv[1]

    try:
        if command == 'info' and len(argv) >= 4:
            print(describe(argv[2], argv[3]))
            return 0

        if command == 'convert' and len(argv) >= 6:
            family, fmt, src, dst = argv[2], argv[3].lower(), argv[4], argv[5]
            option = argv[6] if len(argv) > 6 else ''
            if not os.path.exists(src):
                raise ValueError('missing source: ' + src)
            if family == 'tables':
                convert_table(fmt, src, dst)
            elif family == 'data':
                convert_data(fmt, src, dst)
            elif family == 'markup':
                convert_markup(fmt, src, dst)
            elif family == 'ebook':
                convert_ebook(fmt, src, dst, option)
            elif family == 'subs':
                convert_subs(fmt, src, dst)
            elif family == 'archive':
                convert_archive(fmt, src, dst)
            elif family == 'models':
                convert_model(fmt, src, dst)
            else:
                raise ValueError('unknown family ' + family)
            if not os.path.exists(dst):
                raise ValueError('converter produced no output')
            return 0

        sys.stderr.write('usage: toolkit.py convert <family> <fmt> <src> <dst> [option]\n'
                         '       toolkit.py info <family> <path>\n')
        return 2
    except Exception as exc:  # reported to the app's activity log
        sys.stderr.write('%s: %s\n' % (type(exc).__name__, exc))
        try:
            if 'dst' in locals() and os.path.exists(dst):
                os.remove(dst)
        except Exception:
            pass
        return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
