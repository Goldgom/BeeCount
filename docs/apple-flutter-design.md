# Flutter grouped design and finance display

## Visual system

Material remains the rendering/interaction foundation on Android. No Cupertino route, input, or permission behavior replaces Android functionality. Grouped neutral page surfaces, flat rounded cards, system-blue default accent, system font fallbacks, clearer title/body hierarchy and light/dark surfaces are shared by the real home, account list, valuation/investment account detail and settings row components. Existing user-selected accent/skin preferences remain intact. Bottom navigation preserves tabs, unread indicators, avatars and recording long-press actions; selection has explicit accessibility semantics. Shared rows support multiline large text and minimum touch targets.

Investment is an existing account type, not a newly invented portfolio/trading feature.

## Read-only finance balances

`readFinanceBalances` uses the existing authenticated/retry client at `GET /finance/balances`. The server returns a direct map keyed by account sync ID. Only valid finite `balance_decimal`, matching currency, valid `cash_as_of` and `projection_plus_finance_events` source are accepted. This is the final balance, **not an effect to add to local balance**.

Display-only providers overlay account cards/details, per-currency net worth, asset composition and their currency-converted summaries. Income/expense statistics and original repository providers remain local. No initial balance, transaction, or database row is written. Missing/unmatched accounts use local values. Hidden accounts still contribute to net worth as before. Missing exchange rates are not replaced with 1.

Finance reads are bounded to 8 seconds, refresh after local statistics/sync generation changes and every 60 seconds while observed, and can be manually refreshed. No cloud snapshot persists across credentials/config changes. Failure/offline falls back to local data with an outdated-data warning; active sync or unpushed changes prefer local data and show the pending/sync status. The status shows the oldest included cloud cash timestamp, not an invented local sync timestamp. Historic trend/category transaction graphs remain local ledger history (finance audit is not fabricated as transactions).

## Verification

- `flutter analyze --no-pub`: no errors; repository-wide existing warnings/info remain (not a clean lint baseline).
- `flutter test --no-pub test/widgets/apple_design_system_test.dart test/providers/finance_display_test.dart test/widgets/transfer_form_account_hidden_test.dart test/repositories/account_hidden_test.dart`: 15 passed.
- `flutter build apk --debug --flavor dev --no-pub`: successful Dev Debug APK.

Tests cover Android theme platform retention, light/dark surface hierarchy and contrast, 2x text shared-row layout/taps, final balance replacement without mutation/addition, currency mismatch and offline fallback, malformed finance payload rejection, and existing hidden-account business behavior.

Build initially failed because native SQLite assets could not be downloaded from GitHub. The notification worker recovered the package's checksum-verified native-asset cache using the already configured local proxy; no native source changes were made by this visual worker. Pub mirror resolution also failed; a command-scoped `PUB_HOSTED_URL=https://pub.dev flutter pub get` restored dependencies. Device rendering/screenshots, real server authenticated finance responses and physical Android notification permission flows still require runtime/device acceptance; compile/tests alone do not prove them.
