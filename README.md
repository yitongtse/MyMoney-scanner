# MyMoney scanner development

Local tools and the YAML contract for writing institution-specific scanners for MyMoney.
A scanner converts a downloaded transaction file or a statement into YAML; MyMoney handles
import previews, duplicate detection, and reconciliation.

## Start here

- [SPEC.md](SPEC.md): complete version-1 YAML field reference for cash and investment
  transaction imports, cash reconciliation, and investment position reconciliation.
- [examples/](examples/): annotated, synthetic checking and brokerage files, with a
  transaction download and matching statement summary for each account.
- [HOWTO.md](HOWTO.md): develop a scanner, connect it to MyMoney, extract PDF text, and
  sanitize local text.
- [SCANNER-PROMPT.md](SCANNER-PROMPT.md): copy-and-paste coding-assistant prompt for
  building a transaction or statement scanner from a reviewed sanitized sample.
- [DECISIONS.md](DECISIONS.md): scope, provenance, and compatibility decisions.

## Tools

Requires macOS with Swift and the Command Line Tools (`xcode-select --install`).
There are no third-party dependencies or package installation steps.

```sh
swift scripts/pdf-to-text.swift "/path/to/statement.pdf" "/path/to/statement.private.txt"
swift scripts/sanitize-statement.swift "/path/to/sanitize.private.yaml" "/path/to/statement.private.txt" "/path/to/statement-synthetic.txt"
```

Copy [sanitize-statement.example.yaml](scripts/sanitize-statement.example.yaml) to a private
folder and replace its synthetic aliases before using the sanitizer. Keep originals and
private configuration outside this repository. Sanitization is not guaranteed anonymization:
review the entire result locally before sharing it. Randomized financial values do not balance.

## Tests

Run from this repository's root:

```sh
swift scripts/test-pdf-to-text.swift
swift scripts/test-sanitize-statement.swift
```

Tests create synthetic fixtures in temporary directories and remove them afterward.
They compile and exercise the local copies of the tools, not the sibling MyMoney checkout.
These are tool regression tests, not a MyMoney YAML validator; validate scanner output in
MyMoney as described in [HOWTO.md](HOWTO.md).
