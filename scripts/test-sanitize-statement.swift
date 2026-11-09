#!/usr/bin/env swift
import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw TestFailure(description: message) }
}

func run(_ executable: URL, _ arguments: [String]) throws -> (status: Int32, out: String, err: String) {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    // Synthetic output is small enough to fit in both pipes.
    process.waitUntilExit()
    return (
        process.terminationStatus,
        String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
        String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    )
}

func test() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("sanitize-statement-\(UUID())")
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
    defer {
        do { try FileManager.default.removeItem(at: temporary) }
        catch { FileHandle.standardError.write(Data("Cleanup failed: \(error)\n".utf8)) }
    }
    let executable = temporary.appendingPathComponent("sanitizer")
    let compilation = try run(URL(fileURLWithPath: "/usr/bin/xcrun"), [
        "swiftc", "-swift-version", "6", root.appendingPathComponent("scripts/sanitize-statement.swift").path,
        "-o", executable.path
    ])
    try check(compilation.status == 0, "Compilation failed: \(compilation.err)")
    let config = temporary.appendingPathComponent("config.private.yaml")
    let example = try String(contentsOf: root.appendingPathComponent("scripts/sanitize-statement.example.yaml"),
                             encoding: .utf8)
    try example.write(to: config, atomically: true, encoding: .utf8)
    let input = temporary.appendingPathComponent("statement.private.txt")
    let output = temporary.appendingPathComponent("synthetic.txt")
    let fixture = """
    FABRIKAM BANK / Fabrikam
    Alex Q. Example / Alex Example
    AB-12345678 / ****5678
    123 Example
    Street
    Sample City, ZZ 12345
    000-12-3456 / XXX-XX-3456
    Contoso Industries CTSO / Northwind Example Fund NWEX
    alex@example.invalid
    Holdings: $12,345.67 ($12,345.67) -98.76 +.45 1234 12.3456 9.25%
    Dates: 12/31/2026 31/12/2026 2026-12-31 31.12.26
    Names: January 31, 2026 / 31 Jan 2026
    Short: 12/31 31/12 Jan 31 31-Jan-2026
    Again: 12/31/2026 12,345.67
    Page 2 of 8
    Page 2
    2 of 8
    \u{000C}
    1234
    Unicode: \u{0661}\u{0662}\u{0663}
    CTSOLOGY stays.
    Alex Example Page 1234
    """
    try fixture.write(to: input, atomically: true, encoding: .utf8)
    let result = try run(executable, [config.path, input.path, output.path])
    try check(result.status == 0 && result.out.isEmpty, "Sanitization failed: \(result.err)")
    let text = try String(contentsOf: output, encoding: .utf8)
    try check(text.hasPrefix("[BANK_A] / [BANK_A]\n[OWNER_A] / [OWNER_A]\n[ACCOUNT_A] / [ACCOUNT_A]"),
              "Aliases did not share stable pseudonyms.")
    try check(text.contains("[ADDRESS_A]\n[ADDRESS_B]"), "Multiline or overlapping alias not removed.")
    try check(text.contains("[SSN_A] / [SSN_A]"), "SSNs not replaced.")
    try check(text.contains("[STOCK_A] [STOCK_A] / [STOCK_B] [STOCK_B]"), "Stock identities not preserved.")
    try check(text.contains("[OTHER_A]"), "Other private term not removed.")
    try check(text.contains("Page 2 of 8\nPage 2\n2 of 8\n\u{000C}\n"), "Page structure changed.")
    try check(text.contains("CTSOLOGY stays."), "Word boundary behavior changed.")
    for original in ["FABRIKAM", "Alex", "AB-12345678", "****5678", "Example", "Sample City",
                     "000-12-3456", "XXX-XX-3456", "Contoso", "Northwind", "alex@example.invalid",
                     "\u{0661}\u{0662}\u{0663}"] {
        try check(!text.contains(original), "Synthetic fixture term/value remains: \(original)")
        try check(!result.err.contains(original), "Diagnostics exposed synthetic private input.")
    }
    try check(result.err.contains("review output"), "Review warning missing.")

    let lines = text.components(separatedBy: "\n")
    guard let holdings = lines.first(where: { $0.hasPrefix("Holdings:") }),
          let dates = lines.first(where: { $0.hasPrefix("Dates:") }),
          let again = lines.first(where: { $0.hasPrefix("Again:") }) else {
        throw TestFailure(description: "Expected fixture lines missing.")
    }
    let numberRegex = try NSRegularExpression(pattern: #"\d+(?:[,.]\d+)*"#)
    let matches = numberRegex.matches(in: holdings, range: NSRange(location: 0, length: (holdings as NSString).length))
        .map { (holdings as NSString).substring(with: $0.range) }
    try check(matches.count == 7 && matches[0] == matches[1] && again.hasSuffix(matches[0]),
              "Repeated values were not consistent.")
    let originalNumbers = ["12,345.67", "12,345.67", "98.76", "45", "1234", "12.3456", "9.25"]
    for (actual, original) in zip(matches, originalNumbers) {
        try check(actual != original, "A financial value retained its original number.")
    }
    try check(lines.contains(matches[4]), "Bare numeric value was not replaced consistently.")
    try check(lines.contains("[OWNER_A] Page \(matches[4])"), "Alias boundary was treated as a page-marker line.")
    try check(holdings.contains("$") && holdings.contains("($") && holdings.contains(") -")
              && holdings.contains("+.") && holdings.hasSuffix("%"), "Financial formatting changed.")
    let dateTokens = dates.dropFirst("Dates: ".count).split(separator: " ").map(String.init)
    try check(dateTokens.count == 4 && again.contains(dateTokens[0]), "Repeated dates were not consistent.")
    for (index, date) in dateTokens.enumerated() {
        let parts = date.split(whereSeparator: { "/.-".contains($0) }).compactMap { Int($0) }
        try check(parts.count == 3, "Date output was not numeric.")
        let yearFirst = index == 2
        let dayMonth = yearFirst ? Array(parts.dropFirst()) : Array(parts.prefix(2))
        try check(dayMonth.allSatisfy { (1...12).contains($0) }, "Date invalid in one numeric convention.")
        try check(date != ["12/31/2026", "31/12/2026", "2026-12-31", "31.12.26"][index],
                  "Original date was retained.")
    }
    let names = lines.first(where: { $0.hasPrefix("Names:") }) ?? ""
    let namedRegex = try NSRegularExpression(pattern: #"[A-Za-z]+ (\d{1,2}), (\d{4}) / (\d{1,2}) [A-Za-z]+ (\d{4})"#)
    guard let named = namedRegex.firstMatch(in: names, range: NSRange(location: 0, length: (names as NSString).length)) else {
        throw TestFailure(description: "Month-name date formatting changed.")
    }
    for group in [1, 3] {
        let day = Int((names as NSString).substring(with: named.range(at: group))) ?? 0
        try check((1...12).contains(day), "Invalid month-name date day.")
    }
    guard let short = lines.first(where: { $0.hasPrefix("Short:") }) else {
        throw TestFailure(description: "Short date fixture missing.")
    }
    let shortRegex = try NSRegularExpression(pattern: #"Short: (\d{1,2})/(\d{1,2}) (\d{1,2})/(\d{1,2}) [A-Za-z]+ (\d{1,2}) (\d{1,2})-[A-Za-z]+-(\d{4})"#)
    guard let shortDates = shortRegex.firstMatch(in: short, range: NSRange(location: 0, length: (short as NSString).length)) else {
        throw TestFailure(description: "Yearless or hyphenated month-name date shape changed.")
    }
    for group in 1...6 {
        let field = Int((short as NSString).substring(with: shortDates.range(at: group))) ?? 0
        try check((1...12).contains(field), "Invalid yearless or hyphenated date field.")
    }

    let second = try run(executable, [config.path, input.path, output.path])
    let secondText = try String(contentsOf: output, encoding: .utf8)
    try check(second.status == 0 && secondText != text, "Fresh run did not randomize values.")
    try check(secondText.hasPrefix("[BANK_A] / [BANK_A]"), "Pseudonym labels were unstable.")

    let yaml = """
    # quoting and literal punctuation
    other:
      - aliases:
          - 'O''Example'
          - "Sensitive # label"
      - aliases:
          - C++ Fund (Class A)
          - "Caf\\u00e9 Fund"
    """
    try yaml.write(to: config, atomically: true, encoding: .utf8)
    try "O'Example Sensitive # label C++ Fund (Class A) Caf\u{00E9} Fund"
        .write(to: input, atomically: true, encoding: .utf8)
    let quoting = try run(executable, [config.path, input.path, output.path])
    let quotedOutput = try String(contentsOf: output, encoding: .utf8)
    try check(quoting.status == 0 && quotedOutput == "[OTHER_A] [OTHER_A] [OTHER_B] [OTHER_B]",
              "YAML quoting or regex escaping failed.")

    let invalidConfigs = [
        "", "unknown:\n  - aliases:\n      - secret",
        "bank:\n  - aliases:", "bank:\n  - aliases:\n      - \"\"",
        "bank:\n  - aliases:\n      - duplicate\nowner:\n  - aliases:\n      - DUPLICATE",
        "bank:\n  - aliases:\n      - secret\nbank:",
        "bank:\n  - aliases: [secret]", "bank:\n\t- aliases:",
        "bank:\n  - aliases:\n      - &secret alias",
        "bank:\n  - aliases:\n      - 'bad'quote'",
        "bank:\n  - aliases:\n      - \"unclosed",
        "bank:\n  - aliases:\n      - secret # comment"
    ]
    for invalid in invalidConfigs {
        try invalid.write(to: config, atomically: true, encoding: .utf8)
        let failed = try run(executable, [config.path, input.path, output.path])
        try check(failed.status != 0 && failed.out.isEmpty && failed.err.contains("Error:"),
                  "Invalid YAML accepted.")
        let preserved = try String(contentsOf: output, encoding: .utf8)
        try check(preserved == quotedOutput, "Failure overwrote existing output.")
        try check(!failed.err.contains("secret") && !failed.err.contains(config.path),
                  "Error exposed config content or path.")
    }

    try example.write(to: config, atomically: true, encoding: .utf8)
    for forbidden in [input, config] {
        let failure = try run(executable, [config.path, input.path, forbidden.path])
        try check(failure.status != 0, "Input/config overwrite accepted.")
    }
    let symlink = temporary.appendingPathComponent("alias.txt")
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: input)
    let aliasFailure = try run(executable, [config.path, input.path, symlink.path])
    try check(aliasFailure.status != 0, "Symlink overwrite accepted.")
    for arguments in [
        [config.path, temporary.appendingPathComponent("missing").path, output.path],
        [config.path, input.path, temporary.appendingPathComponent("missing/out.txt").path]
    ] {
        let failed = try run(executable, arguments)
        try check(failed.status != 0 && failed.err.contains("Error:"), "I/O failure was hidden.")
    }
    try "".write(to: input, atomically: true, encoding: .utf8)
    let empty = try run(executable, [config.path, input.path, output.path])
    try check(empty.status != 0 && empty.err.contains("empty"), "Empty input accepted.")
    try Data([0xFF]).write(to: input)
    let encoding = try run(executable, [config.path, input.path, output.path])
    try check(encoding.status != 0 && encoding.err.contains("UTF-8"), "Invalid UTF-8 accepted.")
    let help = try run(executable, ["--help"])
    try check(help.status == 0 && help.out.contains("CONFIG.yaml"), "Help failed.")
    let usage = try run(executable, [])
    try check(usage.status != 0 && usage.err.contains("Usage:"), "Missing arguments accepted.")
    print("Statement sanitizer tests passed.")
}

do {
    try test()
} catch {
    FileHandle.standardError.write(Data("Test failed: \(error)\n".utf8))
    exit(1)
}
