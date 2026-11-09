# Decisions

## Initial setup (2026-11-09)

- **Snapshot the existing version-1 contract, do not invent a new format.**
  [SPEC.md](SPEC.md) originates from MyMoney's `scripts/scanners/FORMATS.md` at commit
  `8d6875b`. It covers both cash and investment transaction imports and statement
  reconciliation. The implemented MyMoney parsers remain the compatibility authority.
  Update this reference deliberately when MyMoney's contract changes.
- **Keep the repo standalone.** The PDF extractor, sanitizer, synthetic example
  configuration, and their regression scripts are copies, not symlinks or dependencies
  on a sibling checkout. Preserve the `scripts/` layout so the copied tests exercise
  these local tools without changes.
- **Start with documentation, tools, and synthetic YAML examples.** No app code, ledger
  database, institution-specific scanners, or real statements are copied. The annotated
  checking and brokerage examples come from MyMoney's tested scanner examples.
- **Keep processing local.** No network services, OCR service, or new dependency is
  introduced. The extractor needs macOS PDFKit; the scripts and tests need Swift.
- **Sanitized text is not a balanced financial fixture or a privacy guarantee.**
  Randomization preserves useful layout but not accounting identities or date ordering.
  Explicit aliases and full local review are required before sharing any output.
- **No automatic synchronization.** Copies can evolve independently. Re-run local tool
  tests after changes and validate scanner output with MyMoney's import and reconciliation
  flows. No commit, remote configuration, or push is part of this setup.

## Scanner-generation prompt (2026-11-09)

- **Use an ordinary copy-and-paste prompt, not editor-specific configuration.**
  [SCANNER-PROMPT.md](SCANNER-PROMPT.md) lets users choose transaction imports or
  statement reconciliation, cash or investments, and the production input type.
- **Separate layout evidence from accounting evidence.** The prompt requires extraction
  checks against sanitized text and separate internally consistent synthetic fixtures
  for successful end-to-end validation. Production checks must not be disabled to
  accommodate randomized amounts or dates, and missing semantics require clarification.
