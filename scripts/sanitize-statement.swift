#!/usr/bin/env swift
import Foundation

struct SanitizerError: Error, CustomStringConvertible {
    let description: String
}

struct Segment {
    var text: String
    var protected: Bool = false
    var sourceOffset: Int = 0
}

func rewrite(
    _ segments: [Segment], using regex: NSRegularExpression,
    accepting: (NSRange) -> Bool = { _ in true },
    replacement: (NSTextCheckingResult, NSString) throws -> String
) rethrows -> [Segment] {
    var result: [Segment] = []
    for segment in segments {
        if segment.protected {
            result.append(segment)
            continue
        }
        let source = segment.text as NSString
        var offset = 0
        for match in regex.matches(in: segment.text, range: NSRange(location: 0, length: source.length)) {
            let originalRange = NSRange(location: segment.sourceOffset + match.range.location, length: match.range.length)
            guard accepting(originalRange) else { continue }
            result.append(Segment(text: source.substring(with: NSRange(
                location: offset, length: match.range.location - offset
            )), sourceOffset: segment.sourceOffset + offset))
            result.append(Segment(text: try replacement(match, source), protected: true,
                                  sourceOffset: originalRange.location))
            offset = NSMaxRange(match.range)
        }
        result.append(Segment(text: source.substring(from: offset), sourceOffset: segment.sourceOffset + offset))
    }
    return result
}

func letters(_ index: Int) -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    var number = index + 1
    var result = ""
    while number > 0 {
        number -= 1
        result = String(alphabet[number % 26]) + result
        number /= 26
    }
    return result
}

func normalized(_ value: String) -> String {
    value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        .joined(separator: " ").lowercased()
}

struct Term {
    let pattern: String
    let placeholder: String
}

struct Configuration {
    let terms: [Term]
    let placeholders: Set<String>

    init(text: String) throws {
        let groups = try parseConfig(text)
        let categories = ["bank", "owner", "account", "address", "ssn", "stock", "other"]
        guard Set(groups.keys).isSubset(of: Set(categories)) else {
            throw SanitizerError(description: "Unknown config category. Allowed: \(categories.joined(separator: ", ")).")
        }
        var terms: [Term] = []
        var assigned: [String: String] = [:]
        var placeholders: Set<String> = []
        for category in categories {
            for (index, aliases) in groups[category, default: []].enumerated() {
                guard !aliases.isEmpty else {
                    throw SanitizerError(description: "Empty alias group in \(category).")
                }
                let placeholder = "[\(category.uppercased())_\(letters(index))]"
                placeholders.insert(placeholder)
                for alias in aliases {
                    let key = normalized(alias)
                    guard !key.isEmpty, !alias.contains("\u{000C}"), !alias.contains("\u{0000}") else {
                        throw SanitizerError(description: "Empty or invalid alias in \(category).")
                    }
                    if let existing = assigned[key] {
                        guard existing == placeholder else {
                            throw SanitizerError(description: "An alias is assigned to more than one entity. Merge its groups.")
                        }
                        continue
                    }
                    assigned[key] = placeholder
                    let escaped = key.components(separatedBy: " ")
                        .map(NSRegularExpression.escapedPattern(for:)).joined(separator: #"[ \t\r\n]+"#)
                    terms.append(Term(pattern: #"(?<![\p{L}\p{N}])"# + escaped + #"(?![\p{L}\p{N}])"#,
                                      placeholder: placeholder))
                }
            }
        }
        guard !terms.isEmpty else {
            throw SanitizerError(description: "Config must list at least one sensitive entity.")
        }
        self.terms = terms.sorted { $0.pattern.count > $1.pattern.count }
        self.placeholders = placeholders
    }
}

func parseConfig(_ text: String) throws -> [String: [[String]]] {
    var groups: [String: [[String]]] = [:]
    var category: String?
    for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
        let body = raw.trimmingCharacters(in: .whitespaces)
        if body.isEmpty || body.hasPrefix("#") { continue }
        func invalid() -> SanitizerError {
            SanitizerError(description: "Invalid YAML at line \(index + 1). Use the example's category / aliases / scalar-list format.")
        }
        guard !raw.contains("\t") else { throw invalid() }
        let indent = raw.prefix(while: { $0 == " " }).count
        if indent == 0 {
            guard body.hasSuffix(":"), !body.dropLast().contains(":") else { throw invalid() }
            let key = String(body.dropLast())
            guard groups[key] == nil else { throw invalid() }
            category = key
            groups[key] = []
        } else if indent == 2 && body == "- aliases:" {
            guard let category else { throw invalid() }
            groups[category, default: []].append([])
        } else if indent == 6 && body.hasPrefix("- ") {
            guard let category, let count = groups[category]?.count, count > 0 else { throw invalid() }
            let scalar = String(body.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            let value: String
            if scalar.hasPrefix("\"") {
                // JSON string escapes are a supported subset of YAML double-quoted scalars.
                guard let decoded = try? JSONDecoder().decode(String.self, from: Data(scalar.utf8)) else {
                    throw invalid()
                }
                value = decoded
            } else if scalar.hasPrefix("'") {
                guard scalar.count >= 2, scalar.hasSuffix("'") else { throw invalid() }
                let inner = String(scalar.dropFirst().dropLast())
                let remainder = inner.replacingOccurrences(of: "''", with: "")
                guard !remainder.contains("'") else { throw invalid() }
                value = inner.replacingOccurrences(of: "''", with: "'")
            } else {
                guard !scalar.isEmpty, !scalar.contains(" #"), !scalar.contains(": "),
                      !["[", "{", "&", "*", "!", "|", ">", "#", "%", "@", "`"].contains(where: scalar.hasPrefix)
                else { throw invalid() }
                value = scalar
            }
            groups[category]?[count - 1].append(value)
        } else {
            throw invalid()
        }
    }
    return groups
}

let monthPattern = #"(?i:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)"#
let numericDatePattern = #"(?<![\p{L}\p{N}])(?:\d{4}([/.-])\d{1,2}\1\d{1,2}|\d{1,2}([/.-])\d{1,2}(?:\2(?:\d{4}|\d{2}))?)(?![\p{L}\p{N}])"#
let namedDatePattern = #"(?<![\p{L}\p{N}])(?:"# + monthPattern
    + #"[ \t./-]+\d{1,2}(?:(?:,[ \t]*|[ \t./-]+)\d{4}|[./-]\d{2})?|\d{1,2}[ \t./-]+"#
    + monthPattern + #"(?:[ \t./-]+\d{4}|[./-]\d{2})?)(?![\p{L}\p{N}])"#

struct SyntheticValues {
    var replacements: [String: String] = [:]

    mutating func value(for original: String, kind: String, generate: () -> String) -> String {
        let key = kind + ":" + original.lowercased()
        if let existing = replacements[key] { return existing }
        var candidate = generate()
        while candidate.lowercased() == original.lowercased() {
            candidate = generate()
        }
        replacements[key] = candidate
        return candidate
    }

    mutating func number(_ original: String) -> String {
        value(for: original, kind: "number") {
            let digits = Array("0123456789")
            return String(original.map { character in
                character.wholeNumberValue != nil ? digits[Int.random(in: 0...9)] : character
            })
        }
    }

    mutating func date(_ original: String, numeric: Bool) throws -> String {
        let regex = try NSRegularExpression(pattern: numeric ? #"\d+"# : monthPattern + #"|\d+"#)
        let source = original as NSString
        let tokens = regex.matches(in: original, range: NSRange(location: 0, length: source.length))
        guard (2...3).contains(tokens.count) else {
            throw SanitizerError(description: "Cannot synthesize a recognized date.")
        }
        return value(for: original, kind: "date") {
            let year = Int.random(in: 1990...2035)
            // Both fields stay <= 12, so ambiguous numeric dates remain valid in either date convention.
            let month = Int.random(in: 1...12)
            let day = Int.random(in: 1...12)
            let yearFirst = numeric && tokens.count == 3 && tokens[0].range.length == 4
            let monthNames = ["January", "February", "March", "April", "May", "June",
                              "July", "August", "September", "October", "November", "December"]
            var result = original
            for (index, token) in tokens.enumerated().reversed() {
                let old = source.substring(with: token.range)
                let replacement: String
                if old.first?.isLetter == true {
                    let name = monthNames[month - 1]
                    let abbreviated = old.count <= 4
                    var text = abbreviated ? String(name.prefix(old.count == 4 && month == 9 ? 4 : 3)) : name
                    if old == old.uppercased() { text = text.uppercased() }
                    else if old == old.lowercased() { text = text.lowercased() }
                    replacement = text
                } else {
                    let isYear = tokens.count == 3 && (yearFirst ? index == 0 : index == 2)
                    let value = isYear ? (old.count == 2 ? year % 100 : year) : (index == 1 ? day : month)
                    replacement = old.count > 1 ? String(format: "%0*d", old.count, value) : String(value)
                }
                result = (result as NSString).replacingCharacters(in: token.range, with: replacement)
            }
            return result
        }
    }
}

func sanitize(_ text: String, config: Configuration) throws -> (text: String, missing: Set<String>) {
    var segments = [Segment(text: text)]
    var found: Set<String> = []
    let terms = try NSRegularExpression(
        pattern: config.terms.map { "(" + $0.pattern + ")" }.joined(separator: "|"),
        options: [.caseInsensitive]
    )
    segments = try rewrite(segments, using: terms) { match, _ in
        guard let index = config.terms.indices.first(where: { match.range(at: $0 + 1).location != NSNotFound }) else {
            throw SanitizerError(description: "Cannot identify matched config entity.")
        }
        let placeholder = config.terms[index].placeholder
        found.insert(placeholder)
        return placeholder
    }
    let pages = try NSRegularExpression(
        pattern: #"^[ \t]*(?:Page[ \t]+\d+(?:[ \t]+of[ \t]+\d+)?|\d+[ \t]+of[ \t]+\d+)[ \t]*\r?$"#,
        options: [.caseInsensitive, .anchorsMatchLines]
    )
    // Alias replacements create segment boundaries, which must not become artificial page-marker line boundaries.
    let pageRanges = Set(pages.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map(\.range))
    segments = rewrite(segments, using: pages, accepting: pageRanges.contains) { match, source in
        source.substring(with: match.range)
    }

    var values = SyntheticValues()
    for (pattern, numeric) in [(numericDatePattern, true), (namedDatePattern, false)] {
        let dates = try NSRegularExpression(pattern: pattern)
        segments = try rewrite(segments, using: dates) { match, source in
            try values.date(source.substring(with: match.range), numeric: numeric)
        }
    }
    let numbers = try NSRegularExpression(pattern: #"\p{Nd}+(?:[,.]\p{Nd}+)*"#)
    segments = rewrite(segments, using: numbers) { match, source in
        values.number(source.substring(with: match.range))
    }
    return (segments.map(\.text).joined(), config.placeholders.subtracting(found))
}

func say(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func fail(_ message: String) -> Never {
    say("Error: \(message)")
    exit(1)
}

func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        .standardizedFileURL.resolvingSymlinksInPath()
}

let usage = """
Usage: swift scripts/sanitize-statement.swift CONFIG.yaml INPUT.txt OUTPUT.txt

Locally replace configured entities with [BANK_A], [OWNER_A], [STOCK_A], etc.
Copy scripts/sanitize-statement.example.yaml to a PRIVATE location and edit its alias groups.
The supported YAML subset uses category keys, "- aliases:" groups, and indented string lists.
Other numbers and common numeric/month-name dates get synthetic replacements, consistent
for each literal within a run and randomized again on the next run.
Standalone lines "Page 2", "Page 2 of 8", "2 of 8" and form feeds are preserved.
An existing output file is replaced. Input and config files are never overwritten.
No network, OCR, AI, or automatic name recognition. Review output before sharing.
"""
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--help"] || arguments == ["-h"] {
    print(usage)
    exit(0)
}
guard arguments.count == 3 else { fail(usage) }

let configURL = fileURL(arguments[0])
let inputURL = fileURL(arguments[1])
let outputURL = fileURL(arguments[2])
guard outputURL != configURL, outputURL != inputURL else {
    fail("Output must not be the input or config file.")
}

do {
    let configText: String
    do { configText = try String(contentsOf: configURL, encoding: .utf8) }
    catch { throw SanitizerError(description: "Cannot read config file.") }
    let config = try Configuration(text: configText)
    let text: String
    do { text = try String(contentsOf: inputURL, encoding: .utf8) }
    catch { throw SanitizerError(description: "Cannot read input as UTF-8 text.") }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw SanitizerError(description: "Input text is empty.")
    }
    let result = try sanitize(text, config: config)
    do { try Data(result.text.utf8).write(to: outputURL, options: .atomic) }
    catch { throw SanitizerError(description: "Cannot write output file.") }
    if !result.missing.isEmpty {
        say("Warning: no match for configured entities: \(result.missing.sorted().joined(separator: ", ")). Check aliases locally.")
    }
    say("Warning: review output before sharing. Unlisted names, addresses, symbols, and alphabetic identifiers may remain. Synthetic values do not preserve accounting arithmetic.")
} catch {
    // Do not include Foundation errors, paths, or config contents in diagnostics.
    if let error = error as? SanitizerError { fail(error.description) }
    fail("Sanitization failed.")
}
