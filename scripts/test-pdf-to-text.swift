#!/usr/bin/env swift
import CoreGraphics
import CoreText
import Foundation
import PDFKit

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
    // Fixture output is small enough to fit in the pipes without blocking.
    process.waitUntilExit()
    return (
        process.terminationStatus,
        String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
        String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    )
}

func makePDF(_ url: URL, pages: [String]) throws {
    var bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(url as CFURL, mediaBox: &bounds, nil) else {
        throw TestFailure(description: "Cannot create PDF fixture.")
    }
    for text in pages {
        context.beginPDFPage(nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String):
                CTFontCreateWithName("Helvetica" as CFString, 12, nil)]
        ))
        context.textPosition = CGPoint(x: 72, y: 720)
        CTLineDraw(line, context)
        context.endPDFPage()
    }
    context.closePDF()
}

func test() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-to-text-\(UUID())")
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
    defer {
        do { try FileManager.default.removeItem(at: temporary) }
        catch { FileHandle.standardError.write(Data("Cleanup failed: \(error)\n".utf8)) }
    }
    let executable = temporary.appendingPathComponent("pdf-to-text")
    let compilation = try run(URL(fileURLWithPath: "/usr/bin/xcrun"), [
        "swiftc", "-swift-version", "6", root.appendingPathComponent("scripts/pdf-to-text.swift").path,
        "-o", executable.path
    ])
    try check(compilation.status == 0, "Compilation failed: \(compilation.err)")

    let pdf = temporary.appendingPathComponent("sample with spaces.pdf")
    try makePDF(pdf, pages: ["Synthetic statement", "Caf\u{00E9} total 123.45"])
    let result = try run(executable, [pdf.path])
    try check(result.status == 0 && result.err.isEmpty, "Text extraction failed: \(result.err)")
    try check(result.out == "Synthetic statement\n\u{000C}\nCaf\u{00E9} total 123.45\n",
              "Unexpected UTF-8 text or page separators: \(result.out.debugDescription)")

    let output = temporary.appendingPathComponent("output.txt")
    try Data("Old output".utf8).write(to: output)
    let saved = try run(executable, [pdf.path, output.path])
    try check(saved.status == 0 && saved.out.isEmpty, "File output failed: \(saved.err)")
    let savedText = try String(contentsOf: output, encoding: .utf8)
    try check(savedText == result.out, "File and stdout text differ.")

    let sameFile = try run(executable, [pdf.path, pdf.path])
    try check(sameFile.status != 0 && sameFile.err.contains("must not be the input"),
              "Input overwrite was not rejected.")
    let alias = temporary.appendingPathComponent("alias.pdf")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: pdf)
    let sameAlias = try run(executable, [pdf.path, alias.path])
    try check(sameAlias.status != 0, "Symlink input overwrite was not rejected.")

    let mixed = temporary.appendingPathComponent("mixed.pdf")
    try makePDF(mixed, pages: ["First page", "", "Third page"])
    let partial = try run(executable, [mixed.path])
    try check(partial.status == 0 && partial.err.contains("page(s) 2"),
              "Empty page warning missing.")
    try check(partial.out == "First page\n\u{000C}\n\n\u{000C}\nThird page\n",
              "Empty page position was not preserved.")

    let blank = temporary.appendingPathComponent("blank.pdf")
    try makePDF(blank, pages: [""])
    let noText = try run(executable, [blank.path, output.path])
    try check(noText.status != 0 && noText.err.contains("No extractable text"), "Blank PDF accepted.")
    let preserved = try String(contentsOf: output, encoding: .utf8)
    try check(preserved == savedText, "Failed extraction changed the output file.")

    guard let document = PDFDocument(url: pdf) else {
        throw TestFailure(description: "Cannot read encryption fixture.")
    }
    let locked = temporary.appendingPathComponent("locked.pdf")
    try check(document.write(to: locked, withOptions: [
        .userPasswordOption: "synthetic-password", .ownerPasswordOption: "synthetic-owner"
    ]), "Cannot create locked PDF.")
    let protected = try run(executable, [locked.path])
    try check(protected.status != 0 && protected.err.contains("password-protected"),
              "Locked PDF accepted.")

    let invalid = temporary.appendingPathComponent("invalid.pdf")
    try Data("Not a PDF".utf8).write(to: invalid)
    for path in [invalid.path, temporary.appendingPathComponent("missing.pdf").path] {
        let failure = try run(executable, [path])
        try check(failure.status != 0 && failure.out.isEmpty && failure.err.contains("Error:"),
                  "Invalid input did not fail explicitly.")
    }
    let unwritable = try run(executable, [pdf.path, temporary.appendingPathComponent("missing/output.txt").path])
    try check(unwritable.status != 0 && unwritable.err.contains("Error:"), "Write failure was hidden.")
    let help = try run(executable, ["--help"])
    try check(help.status == 0 && help.out.contains("Usage:"), "Help failed.")
    let usage = try run(executable, [])
    try check(usage.status != 0 && usage.err.contains("Usage:"), "Missing arguments accepted.")
    print("PDF text extraction tests passed.")
}

do {
    try test()
} catch {
    FileHandle.standardError.write(Data("Test failed: \(error)\n".utf8))
    exit(1)
}
