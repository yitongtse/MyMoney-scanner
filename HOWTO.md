# Scanner workflows

## Develop a scanner

To have a coding assistant implement your scanner, use [SCANNER-PROMPT.md](SCANNER-PROMPT.md).
Fill in its settings and attach only locally reviewed sanitized input. It covers both
transaction imports and statement reconciliation, including investment accounts.

1. Read [SPEC.md](SPEC.md). Choose `mymoney-transactions` for importing activity or
   `mymoney-statement-summary` for reconciling statement balances and holdings.
   The [checking examples](examples/checking-2026-03.transactions.yaml) and
   [brokerage examples](examples/brokerage-2026-01.transactions.yaml) show both cash and
   investment activity. Their matching summaries are in [examples/](examples/).
2. Write an institution-specific program that takes one input-file path, prints only
   version-1 YAML to stdout, and writes diagnostics to stderr. Exit nonzero on unreadable,
   unsupported, or inconsistent input. Do not silently skip unknown transaction types.
3. Keep monetary calculations exact (integer minor units or decimal arithmetic). Check
   balances and holdings against the source where available before emitting output.
   Preserve institution transaction IDs for repeat-import detection.
4. Test with synthetic fixtures. For example, after creating your scanner:

   ```sh
   swift my-bank-transactions.swift "/path/to/activity.csv" > "/path/to/activity.private.yaml"
   swift my-bank-statement.swift "/path/to/statement.pdf" > "/path/to/summary.private.yaml"
   ```

5. In MyMoney, open the relevant account and import the transactions YAML with
   **Import Statement...** (or **Import Investment Statement...**). Inspect the preview,
   import, and re-import the same activity to check duplicate detection. Use
   **Use Statement Summary YAML File...** in reconciliation to test a summary.
   Confirm cash balances and, for investments, share counts and prices.

Transactions and summaries are different formats: a summary does not import activity.
In transaction files, money entering an account is positive and money leaving is negative;
a credit card's balance owed is negative. In summaries, cash balances use the statement's
printed sign, so a card's amount owed is normally positive. Investment actions determine
cash direction, regardless of the sign of their `amount`.

For position-only retirement statements, omit unavailable cash figures rather than
inventing zeros. A summary without `endingCash` needs at least one position; MyMoney uses
its own cash balances. Include `periodStart` when providing starting positions or prices.
Transaction positions use `security` and `shares`; summary positions use `name`,
`startShares`, and `endShares`. Do not interchange those field names.

## Connect a scanner to MyMoney

1. Open **Settings > Scanners** and click **Install Helper...** once. Install it into the
   Application Scripts folder MyMoney offers. If the folder does not exist, use
   **Copy Terminal Command** and run the supplied command.
2. Choose a **Transactions scanner** and/or **Statement scanner** for the relevant account.
   The helper runs `.swift`, `.py`, `.js`, `.rb`, and `.sh` files with their interpreters;
   other programs must be executable. Install any interpreter your scanner needs locally.
   Scanners can remain in this repository; the helper belongs in MyMoney's scripts folder.
3. Use **Scan Transactions...** inside the account's import dialog for downloads.
   Use **Scan Statement...** in **Balance Account...** or **Reconcile Positions...**
   for statements. Review the results before committing or completing reconciliation.

MyMoney sets `MYMONEY_SCANNER=1`, passes the input path as one argument, and reads stdout
as YAML. Diagnostics are shown only on failure, so exit nonzero when review is required
instead of relying on a successful run's stderr warning.

## Extract PDF text locally

```sh
swift scripts/pdf-to-text.swift "/path/to/statement.pdf"
swift scripts/pdf-to-text.swift "/path/to/statement.pdf" "/path/to/statement.private.txt"
```

Without an output path, UTF-8 text goes to stdout. An existing output file is replaced.
Pages are separated by form feeds (U+000C). PDFKit's reading order may not preserve tables.
Individual text-free pages produce warnings and keep their positions. Entirely text-free,
password-locked, and copy-restricted PDFs fail. This tool performs no OCR and does not
produce MyMoney YAML; a statement scanner must interpret the extracted text.

## Sanitize extracted text locally

Keep all source files and private aliases outside the repository:

```sh
mkdir -p ~/Documents/StatementTools
cp scripts/sanitize-statement.example.yaml ~/Documents/StatementTools/sanitize.private.yaml
```

Edit that private copy. Categories are `bank`, `owner`, `account`, `address`, `ssn`, `stock`,
and `other`. Each `aliases` group represents one entity and receives one typed placeholder.
For example:

```yaml
stock:
  - aliases:
      - "Contoso Industries"
      - "CTSO"
```

Both aliases become `[STOCK_A]`. List all abbreviated and masked forms, address lines,
security names and symbols, and other private identifiers (emails, employers, payees,
web addresses) yourself. Unlisted names are not automatically detected.

Use the example's exact indentation and full-line comments. Plain, single-quoted, and
JSON-escaped double-quoted strings are supported; inline lists/comments, multiline
scalars, and anchors are not. This configuration format is separate from the scanner
output formats in [SPEC.md](SPEC.md).

```sh
swift scripts/pdf-to-text.swift ~/Downloads/statement.pdf ~/Documents/StatementTools/statement.private.txt
swift scripts/sanitize-statement.swift ~/Documents/StatementTools/sanitize.private.yaml ~/Documents/StatementTools/statement.private.txt ~/Documents/StatementTools/statement-synthetic.txt
```

An existing output file is replaced. Input and configuration cannot be overwritten.
Aliases match case-insensitively across whitespace, with letter/digit boundaries and
longer overlaps preferred. No original-to-placeholder map is saved or printed.
Diagnostics do not print aliases, source text, or paths.

Remaining digits and common dates are randomized, preserving formatting and repeated
identical literals within a run. Standalone `Page 2`, `Page 2 of 8`, `2 of 8`, and form
feeds are preserved; bare page numbers and inline page labels are randomized.
Configured aliases take precedence even on page-marker lines.

**Review the entire output locally before sharing it.** This is not guaranteed
anonymization. Unlisted personal details, alphabetic identifiers, and numbers written
as words may remain. Unsupported date formats may become invalid. Add missing aliases
and rerun. Randomized amounts, holdings, and dates do not preserve arithmetic or
chronology; use deliberately balanced synthetic fixtures for scanner correctness tests.
Share only reviewed synthetic output, never originals or private configuration.
