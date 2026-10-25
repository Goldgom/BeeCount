import 'package:beecount/data/db.dart';
import 'package:beecount/providers/finance_display_providers.dart';
import 'package:flutter_test/flutter_test.dart';

Account account({String currency = 'CNY'}) => Account(
    id: 1,
    ledgerId: 1,
    name: '银行',
    type: 'bank_card',
    currency: currency,
    initialBalance: 100,
    sortOrder: 0,
    syncId: 'account-uuid',
    hidden: false);

void main() {
  test('Finance final balance replaces local without adding initial or income',
      () {
    final local = <int, DisplayAccountStats>{
      1: (balance: 120, expense: 10, income: 30)
    };
    final snapshot = FinanceDisplaySnapshot(connected: true, balances: {
      'account-uuid': FinanceBalance('CNY', 155.25, DateTime.utc(2026, 10, 25))
    });
    final result = overlayFinanceBalances([account()], local, snapshot);
    expect(result[1], (balance: 155.25, expense: 10.0, income: 30.0));
    expect(local[1]!.balance, 120);
    expect(account().initialBalance, 100);
  });
  test('Unmatched currency and unavailable cloud preserve offline local data',
      () {
    final local = <int, DisplayAccountStats>{
      1: (balance: 120, expense: 10, income: 30)
    };
    expect(
        overlayFinanceBalances([account()], local,
            const FinanceDisplaySnapshot(connected: true, stale: true)),
        local);
    expect(
        overlayFinanceBalances(
            [account(currency: 'USD')],
            local,
            FinanceDisplaySnapshot(connected: true, balances: {
              'account-uuid': FinanceBalance('CNY', 999, DateTime.utc(2026))
            })),
        local);
  });
  test('Finance parser rejects malformed/unknown sources and prefers decimal',
      () {
    final json = {
      'currency': 'USD',
      'balance_decimal': '100.12',
      'cash_balance': 1,
      'cash_as_of': '2026-10-25T10:00:00Z',
      'balance_source': 'projection_plus_finance_events'
    };
    expect(FinanceBalance.parse(json)!.balance, 100.12);
    expect(FinanceBalance.parse({...json, 'balance_decimal': 'NaN'}), isNull);
    expect(
        FinanceBalance.parse({...json, 'balance_source': 'unknown'}), isNull);
    expect(FinanceBalance.parse({...json, 'cash_as_of': 'invalid'}), isNull);
  });
}
