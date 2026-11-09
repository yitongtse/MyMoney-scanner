# MyMoney scanner specification

A scanner is your own program that reads one institution's file and prints YAML for MyMoney.
This page lists every field of the two formats a scanner can write, and whether it is required.
It is a snapshot of MyMoney's version-1 contract; see [DECISIONS.md](DECISIONS.md) for provenance
and [HOWTO.md](HOWTO.md) for development and app integration.

| Scanner | Reads | Prints | MyMoney uses it to |
|---|---|---|---|
| Transactions scanner | a transaction download (CSV…) | a **transactions file** | import transactions |
| Statement scanner | a statement (PDF…) | a **statement summary** | reconcile cash and positions |

Examples: [examples/](examples/) has both formats for a checking account and a brokerage account. Every line there is
marked `# required` or `# optional`.

## Running

MyMoney runs `<scanner> <input file>` and reads the YAML your scanner prints on **stdout**.

- Print messages (progress, warnings) on **stderr**. They are shown only if the scan fails.
- **Exit non-zero** when the file can't be read or doesn't add up; MyMoney shows the last lines of stderr.
- The environment has `MYMONEY_SCANNER=1`, so a script can tell it is being run by MyMoney.
- Test from Terminal: `swift my-bank.swift ~/Downloads/activity.csv`.

## Writing YAML

Both formats use the same small part of YAML:

- `key: value` lines at the top, and lists written as `key:` followed by `  - key: value` items (two-space indent,
  then four spaces for the item's other keys). No nesting deeper than that, no `[...]` or `{...}`, no multi-line values.
- `#` starts a comment.
- Put text in double quotes when it contains `: `, ` #`, starts with a symbol, or could look like a number:
  `payee: "SQ *BLUE BOTTLE #12"`, `accountNumberLast4: "0123"`. Inside double quotes, write `\"` and `\\`.
  Quoting all text is always safe.
- Dates are `YYYY-MM-DD`.
- Amounts are plain numbers: `-1234.56`. No `$`, no thousands commas, no more decimals than the currency has.
- Share counts and prices take up to 6 decimals: `10.123457`.
- Use `transactions:` with no items for an empty transaction list, not `transactions: []`.
- **Field names are case-sensitive, and an unknown field is an error** (`endingcash` is refused, not ignored).
  Leave a field out rather than writing it empty.

---

## Transactions file

### Top level

| Field | Required | Value | What MyMoney does with it |
|---|---|---|---|
| `format` | **required** | `mymoney-transactions` | identifies the file |
| `version` | **required** | `1` | |
| `transactions` | **required** | list (may be empty) | the transactions to import, see below |
| `balance` | optional | amount | cash balance at the end, in MyMoney's sign (a card's amount owed is **negative**). Shown after the import and pre-fills Balance Account for that date |
| `balanceDate` | optional | date | date of `balance`; default `periodEnd`, then the last transaction's date |
| `periodStart`, `periodEnd` | optional | date | shown in the import ("12 transactions from … to …"); default: first and last transaction dates |
| `accountNumberLast4` | optional | 4 digits, quoted | picks the account when importing with **Import Statement…** and no account chosen |
| `positions` | optional | list | investment accounts only, see below |
| `currency` | optional | `USD`, `EUR`… | only sets how many decimals amounts may have; default USD |
| `institution`, `accountName`, `sourceFile` | optional | text | not used; for people reading the file |

### Each transaction (`transactions:` item)

| Field | Required | Value | Meaning |
|---|---|---|---|
| `date` | **required** | date | |
| `amount` | **required** for cash lines; optional with `action` | amount | cash lines: money in **positive**, money out **negative**. With `action`: the total cash (sign ignored) |
| `id` | optional, **recommended** | text | the institution's unique transaction ID. Re-importing an overlapping download skips lines whose `id` was already imported. Without it, MyMoney matches on date, amount and payee |
| `payee` | optional | text | |
| `memo` | optional | text | |
| `checkNumber` | optional | text | |
| `category` | optional | `Groceries`, `Utilities:Electric`, or `[Savings]` | category path (created if missing), or a transfer to the account in brackets. Bank and card accounts only; leave it out to let rules decide |
| `action` | optional | see below | makes the line an investment transaction (investment accounts only) |
| `security`, `symbol`, `cusip` | see below | text | the security (name, ticker, CUSIP). Give the symbol when there is one |
| `securityType` | optional | `stock`, `etf`, `mutualFund`, `bond`, `cd`, `moneyMarket`, `other` | used when MyMoney creates the security |
| `shares` | see below | number | positive for share actions; for a split, the positive split ratio |
| `price` | optional | number | per share |
| `commission` | optional | amount | buys and sells only |

A line without `action` is a cash movement (in an investment account: deposits, withdrawals, fees…). A line with
`security`, `symbol`, `cusip`, `shares`, `price` or `commission` must have an `action`.

### What each investment `action` needs

"Security" means at least one of `security`, `symbol` or `cusip`.

| `action` | Security | `shares` | `amount` | Cash |
|---|---|---|---|---|
| `buy` | **required** | **required** | optional if `price` given | out |
| `sell` | **required** | **required** | optional if `price` given | in |
| `sharesIn`, `reinvestDividend`, `reinvestInterest`, `reinvestCapitalGain` | **required** | **required** | `amount` or `price` recommended (sets the cost) | none |
| `sharesOut` | **required** | **required** | optional | none |
| `split` | **required** | **required**: the ratio (`2` for 2-for-1) | ignored | none |
| `returnOfCapital` | **required** | – | **required** | in |
| `dividend`, `interest`, `capitalGainLong`, `capitalGainShort`, `miscIncome` | optional | – | **required** | in |
| `miscExpense` | optional | – | **required** | out |

MyMoney refuses the file, naming the transaction, when a line misses something this table requires.
Action names and `securityType` values are matched case-insensitively. For buys and sells,
an omitted `amount` requires a positive `price`; total cash is calculated from shares, price,
and commission (added for a buy, subtracted for a sell).

### Each position (`positions:` item, investment accounts only)

Holdings at the end of the file, used to save prices and check share counts.

| Field | Required | Value |
|---|---|---|
| `security`, `symbol`, `cusip` | **one required** | text |
| `shares` | **required** | number |
| `price` | optional | number; saved as the security's price |
| `date` | optional | date; default `balanceDate`, then `periodEnd` |
| `securityType` | optional | as above |

### Smallest valid file

```yaml
format: mymoney-transactions
version: 1
transactions:
  - date: 2026-03-03
    amount: -84.12
```

---

## Statement summary

### Top level

| Field | Required | Value | What MyMoney does with it |
|---|---|---|---|
| `format` | **required** | `mymoney-statement-summary` | identifies the file |
| `version` | **required** | `1` | |
| `periodEnd` | **required** | date | the statement date |
| `endingCash` | **required unless `positions` has items** | amount | ending balance, **as printed** (a card shows the amount owed as a positive number; MyMoney flips it) |
| `startingCash` | optional, **recommended** | amount | starting balance as printed; MyMoney warns if it isn't the last reconciled balance |
| `periodStart` | optional, **recommended** | date | first day of the period; starting figures are as of the day before. Needed for the position check's starting shares and start prices |
| `positions` | **required unless `endingCash` is given** | list | see below |
| `accountNumberLast4` | optional | 4 digits, quoted | MyMoney warns if it differs from the account's |
| `info` | optional | list | lines shown on the Balance Account sheet for reference, see below |
| `totalStartValue`, `totalEndValue` | optional | amount | not used yet; for checking your scanner |
| `institution`, `sourceFile` | optional | text | shown as the statement's title |
| `accountName` | optional | text | not used; for people reading the file |

Without `endingCash` (a 401(k) statement with no cash line), MyMoney uses its own balances.
Omit unavailable cash figures rather than inventing zero balances. A summary is for
reconciliation only: it does not import transactions. Unlike a transactions file, a summary
has no `currency` field; do not add one.

### Each position (`positions:` item)

| Field | Required | Value | Meaning |
|---|---|---|---|
| `name`, `symbol`, `cusip` | **one required** | text | matched to a security by CUSIP, then symbol, then name (a security you pick once is remembered) |
| `endShares` | optional, **recommended** | number | shares at `periodEnd`; checked against MyMoney |
| `startShares` | optional | number | shares on the day before `periodStart`; tells whether a difference is older than this statement |
| `endPrice`, `endValue` | optional | number, amount | saved as the price on `periodEnd` (value ÷ shares when both are given, since printed prices are rounded) |
| `startPrice`, `startValue` | optional | number, amount | saved as the price on the day before `periodStart` |
| `costBasis` | optional | amount | compared with MyMoney's cost basis (a warning only) |

### Each info line (`info:` item)

| Field | Required | Value |
|---|---|---|
| `label` | **required** | text, e.g. `Deposits` |
| `amount` | **required** | amount |

### Smallest valid file

```yaml
format: mymoney-statement-summary
version: 1
periodEnd: 2026-03-31
endingCash: 6670.75
```

---

## Checklist for a new scanner

1. Check the statement adds up before printing (start + activity = end; positions sum to the total) and exit
   non-zero if it doesn't.
2. Give every transaction the institution's `id` when the download has one.
3. Use MyMoney's signs in a transactions file (money out negative); use the statement's printed figures in a summary.
4. Run it from Terminal and open the output with **Import Statement…** or **Use Statement Summary YAML File…**
   before setting it as the account's scanner.
