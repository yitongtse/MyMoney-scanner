# Scanner development

Read [SPEC.md](SPEC.md) first. Record compatibility and design judgement calls in
[DECISIONS.md](DECISIONS.md); put user workflows in [HOWTO.md](HOWTO.md).

- Keep all processing local. Never commit real statements, transaction downloads,
  account details, extracted private text, or sanitizer configurations.
- Use synthetic fixtures only. Sanitization is not guaranteed anonymization and its
  randomized values do not balance.
- Scanners take one input path, print only MyMoney YAML on stdout, write diagnostics
  to stderr, and exit nonzero on failure. Preserve exact money and share precision.
- Preserve the version-1 contract and distinguish transaction fields/signs from
  statement-summary fields/signs. MyMoney's parsers determine compatibility.
- Run `swift scripts/test-pdf-to-text.swift` and
  `swift scripts/test-sanitize-statement.swift` after related tool changes.
  Validate scanner output in MyMoney; the standalone tests cover only the tools.
- This repository does not build the MyMoney app and requires no Swift package.
