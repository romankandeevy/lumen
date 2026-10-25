import Foundation

/// Настоящие документы из текста, без Word и внешних программ (Рома, 25.10: «почему он docx не умеет делать?»).
/// .docx и .xlsx — это zip с XML внутри; здесь свой маленький zip (без сжатия) и два сборщика.
public enum Documents {
    /// Расширения, которые make_file собирает сам
    public static let builtExtensions: Set<String> = ["docx", "xlsx"]

    public static func data(forName name: String, content: String) -> Data? {
        switch (name as NSString).pathExtension.lowercased() {
        case "docx": return Docx.make(markdown: content)
        case "xlsx": return Xlsx.make(table: content)
        default: return nil
        }
    }
}

// MARK: - zip

/// Zip без сжатия (метод «хранить»): Word и Excel такие читают
struct ZipWriter {
    private var out = Data()
    private var central = Data()
    private var count: UInt16 = 0

    mutating func add(_ name: String, _ data: Data) {
        let nameBytes = Data(name.utf8)
        let crc = Self.crc32(data)
        let offset = UInt32(out.count)
        func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        // локальный заголовок
        out += le32(0x04034b50) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
        out += le32(crc) + le32(UInt32(data.count)) + le32(UInt32(data.count)) + le16(UInt16(nameBytes.count)) + le16(0)
        out += nameBytes + data
        // запись в центральном каталоге
        central += le32(0x02014b50) + le16(20) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
        central += le32(crc) + le32(UInt32(data.count)) + le32(UInt32(data.count)) + le16(UInt16(nameBytes.count))
        central += le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + nameBytes
        count += 1
    }

    func finish() -> Data {
        func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        var d = out
        let start = UInt32(d.count)
        d += central
        d += le32(0x06054b50) + le16(0) + le16(0) + le16(count) + le16(count) + le32(UInt32(central.count)) + le32(start) + le16(0)
        return d
    }

    private static let table: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
}

private func xmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
}

// MARK: - docx

/// Текст с лёгкой разметкой → документ Word: `#`/`##`/`###` — заголовки, `-`/`*` — списки, `1.` — нумерация,
/// `**жирный**`, `*курсив*`, `` `код` ``, `---` — разрыв страницы, пустая строка — новый абзац
enum Docx {
    static func make(markdown: String) -> Data {
        var body = ""
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for raw in lines {
            let line = raw.trimmingCharacters(in: .init(charactersIn: " \t"))
            if line.isEmpty { continue }
            if line == "---" || line == "***" { body += "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>"; continue }
            if let h = heading(line) {
                body += "<w:p><w:pPr><w:pStyle w:val=\"Heading\(h.level)\"/></w:pPr>\(runs(h.text))</w:p>"
            } else if let item = bullet(line) {
                body += "<w:p><w:pPr><w:pStyle w:val=\"ListParagraph\"/><w:ind w:left=\"567\" w:hanging=\"283\"/></w:pPr>"
                    + "<w:r><w:t xml:space=\"preserve\">•\t</w:t></w:r>\(runs(item))</w:p>"
            } else if let n = numbered(line) {
                body += "<w:p><w:pPr><w:pStyle w:val=\"ListParagraph\"/><w:ind w:left=\"567\" w:hanging=\"340\"/></w:pPr>"
                    + "<w:r><w:t xml:space=\"preserve\">\(n.number).\t</w:t></w:r>\(runs(n.text))</w:p>"
            } else {
                body += "<w:p>\(runs(line))</w:p>"
            }
        }
        if body.isEmpty { body = "<w:p/>" }
        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(body)<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>
        """
        var zip = ZipWriter()
        zip.add("[Content_Types].xml", Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>
            """.utf8))
        zip.add("_rels/.rels", Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
            """.utf8))
        zip.add("word/_rels/document.xml.rels", Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
            """.utf8))
        zip.add("word/styles.xml", Data(styles.utf8))
        zip.add("word/document.xml", Data(document.utf8))
        return zip.finish()
    }

    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/><w:sz w:val="24"/><w:szCs w:val="24"/><w:lang w:val="ru-RU"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="360" w:after="160"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="40"/><w:szCs w:val="40"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="280" w:after="120"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="100"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="60"/></w:pPr></w:style></w:styles>
    """

    static func heading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...3).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)).trimmingCharacters(in: .whitespaces))
    }

    static func bullet(_ line: String) -> String? {
        for m in ["- ", "* ", "• "] where line.hasPrefix(m) { return String(line.dropFirst(2)) }
        return nil
    }

    static func numbered(_ line: String) -> (number: Int, text: String)? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3, let n = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return (n, String(rest.dropFirst(2)))
    }

    /// Строка → куски текста с жирным, курсивом и кодом
    static func runs(_ text: String) -> String {
        var out = ""
        var bold = false, italic = false, code = false
        var buffer = ""
        func flush() {
            guard !buffer.isEmpty else { return }
            var props = ""
            if bold { props += "<w:b/>" }
            if italic { props += "<w:i/>" }
            if code { props += "<w:rFonts w:ascii=\"Menlo\" w:hAnsi=\"Menlo\" w:cs=\"Menlo\"/><w:sz w:val=\"21\"/>" }
            out += "<w:r>\(props.isEmpty ? "" : "<w:rPr>\(props)</w:rPr>")<w:t xml:space=\"preserve\">\(xmlEscape(buffer))</w:t></w:r>"
            buffer = ""
        }
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            if chars[i] == "`" { flush(); code.toggle(); i += 1; continue }
            if !code, chars[i] == "*", i + 1 < chars.count, chars[i + 1] == "*" { flush(); bold.toggle(); i += 2; continue }
            if !code, chars[i] == "*" { flush(); italic.toggle(); i += 1; continue }
            buffer.append(chars[i])
            i += 1
        }
        flush()
        return out
    }
}

// MARK: - xlsx

/// CSV или TSV (первая строка — заголовки) → таблица Excel; числа остаются числами
enum Xlsx {
    static func make(table text: String) -> Data {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").filter { !$0.isEmpty }
        let delimiter: Character = (lines.first ?? "").contains("\t") ? "\t" : (((lines.first ?? "").contains(";") && !(lines.first ?? "").contains(",")) ? ";" : ",")
        var rows = ""
        for (r, line) in lines.enumerated() {
            var cells = ""
            for (c, value) in split(line, delimiter).enumerated() {
                let ref = column(c) + String(r + 1)
                let v = value.trimmingCharacters(in: .whitespaces)
                if let n = Double(v.replacingOccurrences(of: ",", with: ".")), !v.isEmpty, !v.hasPrefix("0") || v == "0" || v.hasPrefix("0.") || v.hasPrefix("0,") {
                    cells += "<c r=\"\(ref)\"><v>\(n)</v></c>"
                } else {
                    cells += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xmlEscape(value))</t></is></c>"
                }
            }
            rows += "<row r=\"\(r + 1)\">\(cells)</row>"
        }
        var zip = ZipWriter()
        zip.add("[Content_Types].xml", Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>
            """.utf8))
        zip.add("_rels/.rels", Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
            """.utf8))
        zip.add("xl/workbook.xml", Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Лист1" sheetId="1" r:id="rId1"/></sheets></workbook>
            """.utf8))
        zip.add("xl/_rels/workbook.xml.rels", Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>
            """.utf8))
        zip.add("xl/worksheets/sheet1.xml", Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(rows)</sheetData></worksheet>
            """.utf8))
        return zip.finish()
    }

    /// A, B … Z, AA …
    static func column(_ i: Int) -> String {
        var n = i, s = ""
        repeat { s = String(UnicodeScalar(UInt8(65 + n % 26))) + s; n = n / 26 - 1 } while n >= 0
        return s
    }

    /// Разбор строки CSV с кавычками
    static func split(_ line: String, _ d: Character) -> [String] {
        var out: [String] = [], cur = "", quoted = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if quoted {
                if ch == "\"" { if i + 1 < chars.count, chars[i + 1] == "\"" { cur.append("\""); i += 1 } else { quoted = false } } else { cur.append(ch) }
            } else if ch == "\"" { quoted = true } else if ch == d { out.append(cur); cur = "" } else { cur.append(ch) }
            i += 1
        }
        out.append(cur)
        return out
    }
}
