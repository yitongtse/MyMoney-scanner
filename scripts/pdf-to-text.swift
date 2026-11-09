#!/usr/bin/env swift
import Foundation
import PDFKit

func say(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func fail(_ message: String) -> Never {
    say("Error: \(message)")
    exit(1)
}

let usage = """
Usage: swift scripts/pdf-to-text.swift INPUT.pdf [OUTPUT.txt]

Extract text locally from a text-based PDF on macOS.
Without OUTPUT.txt, write UTF-8 text to stdout. An existing output file is replaced.
Pages are separated by a form-feed character (U+000C).
Scanned PDFs require OCR, which this tool does not perform.
"""

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--help"] || arguments == ["-h"] {
    print(usage)
    exit(0)
}
guard (1...2).contains(arguments.count) else { fail(usage) }

func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        .standardizedFileURL.resolvingSymlinksInPath()
}

let input = fileURL(arguments[0])
let output = arguments.count == 2 ? fileURL(arguments[1]) : nil
if output == input { fail("The output must not be the input PDF.") }

do {
    let data = try Data(contentsOf: input)
    guard let document = PDFDocument(data: data) else {
        fail("Cannot open \(input.path) as a PDF.")
    }
    guard !document.isLocked else {
        fail("The PDF is password-protected. Unlock it before extracting text.")
    }
    guard document.allowsCopying else {
        fail("The PDF does not allow copying text.")
    }
    guard document.pageCount > 0 else { fail("The PDF has no pages.") }

    var pages: [String] = []
    var emptyPages: [Int] = []
    for index in 0..<document.pageCount {
        guard let page = document.page(at: index) else {
            fail("Cannot read page \(index + 1).")
        }
        let text = page.string ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emptyPages.append(index + 1)
        }
        pages.append(text)
    }
    guard emptyPages.count < document.pageCount else {
        fail("No extractable text found. The PDF may be scanned and require OCR.")
    }
    if !emptyPages.isEmpty {
        say("Warning: no extractable text on page(s) \(emptyPages.map(String.init).joined(separator: ", ")). Blank or scanned pages are kept as empty pages; no OCR is performed.")
    }

    var text = pages.joined(separator: "\n\u{000C}\n")
    if !text.hasSuffix("\n") { text += "\n" }
    let result = Data(text.utf8)
    if let output {
        try result.write(to: output, options: .atomic)
    } else {
        try FileHandle.standardOutput.write(contentsOf: result)
    }
} catch {
    fail(error.localizedDescription)
}
