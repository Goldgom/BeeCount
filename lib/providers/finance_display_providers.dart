import 'dart:async';
import '../cloud/sync/sync_providers.dart' as engine;
import '../cloud/sync/sync_engine.dart' show SyncEngineStatus;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db.dart';
import '../utils/account_type_utils.dart';
import 'database_providers.dart';
import 'currency_providers.dart';
import '../services/currency/rate_math.dart';
import 'statistics_providers.dart';
import 'sync_providers.dart';

typedef DisplayAccountStats = ({double balance, double expense, double income});

class FinanceBalance {
  final String currency;
  final double balance;
  final DateTime asOf;
  const FinanceBalance(this.currency, this.balance, this.asOf);

  static FinanceBalance? parse(dynamic value) {
    if (value is! Map ||
        value['balance_source'] != 'projection_plus_finance_events')
      return null;
    final amount = double.tryParse('${value['balance_decimal']}');
    final asOf = DateTime.tryParse('${value['cash_as_of']}');
    final currency = value['currency'];
    if (amount == null ||
        !amount.isFinite ||
        asOf == null ||
        currency is! String) return null;
    return FinanceBalance(currency.toUpperCase(), amount, asOf);
  }
}

class FinanceDisplaySnapshot {
  final bool connected;
  final bool stale;
  final Map<String, FinanceBalance> balances;
  const FinanceDisplaySnapshot(
      {this.connected = false, this.stale = false, this.balances = const {}});
}

final financeLocalPendingProvider = Provider.autoDispose<bool>((ref) {
  final state = ref.watch(engine.syncEngineStatusProvider);
  final pending =
      ref.watch(engine.unpushedChangeCountProvider).valueOrNull ?? 0;
  return pending > 0 ||
      state == SyncEngineStatus.pushing ||
      state == SyncEngineStatus.pulling ||
      state == SyncEngineStatus.syncing;
});

/// No persistence and no cached cloud values across credentials/config changes.
/// Network failure returns local values, explicitly labelled as old/local data.
final financeDisplaySnapshotProvider =
    FutureProvider.autoDispose<FinanceDisplaySnapshot>((ref) async {
  ref.watch(syncStatusRefreshProvider);
  ref.watch(statsRefreshProvider);
  ref.watch(syncGenerationProvider);
  final pending = ref.watch(financeLocalPendingProvider);
  final cloud = await ref.watch(beecountCloudProviderInstance.future);
  if (cloud == null) return const FinanceDisplaySnapshot();
  if (pending)
    return const FinanceDisplaySnapshot(connected: true, stale: true);
  final timer = Timer(const Duration(seconds: 60), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  try {
    final json =
        await cloud.readFinanceBalances().timeout(const Duration(seconds: 8));
    final balances = <String, FinanceBalance>{};
    for (final entry in json.entries) {
      final parsed = FinanceBalance.parse(entry.value);
      if (parsed != null) balances[entry.key] = parsed;
    }
    return FinanceDisplaySnapshot(connected: true, balances: balances);
  } catch (_) {
    return const FinanceDisplaySnapshot(connected: true, stale: true);
  }
});

Map<int, DisplayAccountStats> overlayFinanceBalances(List<Account> accounts,
    Map<int, DisplayAccountStats> local, FinanceDisplaySnapshot snapshot) {
  final result = Map<int, DisplayAccountStats>.from(local);
  for (final account in accounts) {
    final remote = snapshot.balances[account.syncId];
    final original = local[account.id];
    if (remote == null ||
        original == null ||
        remote.currency != account.currency.toUpperCase()) continue;
    result[account.id] = (
      balance: remote.balance,
      expense: original.expense,
      income: original.income
    );
  }
  return result;
}

final displayAllAccountStatsProvider =
    Provider.autoDispose<AsyncValue<Map<int, DisplayAccountStats>>>((ref) {
  final local = ref.watch(allAccountStatsProvider);
  final accounts = ref.watch(allAccountsStreamProvider).valueOrNull;
  final snapshot = ref.watch(financeDisplaySnapshotProvider).asData?.value;
  if (accounts == null || snapshot == null) return local;
  return local
      .whenData((values) => overlayFinanceBalances(accounts, values, snapshot));
});

final displayAccountStatsProvider = Provider.autoDispose
    .family<AsyncValue<DisplayAccountStats>, int>((ref, id) {
  final local = ref.watch(accountStatsProvider(id));
  final all = ref.watch(displayAllAccountStatsProvider).valueOrNull;
  if (all != null && all.containsKey(id)) return AsyncData(all[id]!);
  return local;
});

final displayNetWorthByCurrencyProvider = Provider.autoDispose<
    AsyncValue<
        Map<
            String,
            ({
              double totalAssets,
              double totalLiabilities,
              double netWorth
            })>>>((ref) {
  final accounts = ref.watch(allAccountsStreamProvider).valueOrNull;
  final stats = ref.watch(displayAllAccountStatsProvider);
  if (accounts == null) return ref.watch(netWorthBreakdownByCurrencyProvider);
  return stats.whenData((values) {
    final result = <String,
        ({double totalAssets, double totalLiabilities, double netWorth})>{};
    for (final account in accounts) {
      final balance = values[account.id]?.balance ?? 0;
      final currency = account.currency.toUpperCase();
      final old = result[currency] ??
          (totalAssets: 0.0, totalLiabilities: 0.0, netWorth: 0.0);
      result[currency] = (
        totalAssets:
            old.totalAssets + (isAssetType(account.type) ? balance : 0),
        totalLiabilities:
            old.totalLiabilities + (isAssetType(account.type) ? 0 : balance),
        netWorth: old.netWorth + balance
      );
    }
    return result;
  });
});

final displayAssetCompositionProvider = Provider.autoDispose<
    AsyncValue<List<({String type, double totalBalance})>>>((ref) {
  final accounts = ref.watch(allAccountsStreamProvider).valueOrNull;
  if (accounts == null) return ref.watch(assetCompositionProvider);
  return ref.watch(displayAllAccountStatsProvider).whenData((values) {
    final groups = <String, double>{};
    for (final a in accounts) {
      groups.update(a.type, (v) => v + (values[a.id]?.balance ?? 0),
          ifAbsent: () => values[a.id]?.balance ?? 0);
    }
    return groups.entries
        .map((e) => (type: e.key, totalBalance: e.value))
        .toList();
  });
});

final displayConvertedNetWorthProvider =
    Provider.autoDispose<AsyncValue<ConvertedNetWorth>>((ref) {
  final breakdown = ref.watch(displayNetWorthByCurrencyProvider);
  final rates = ref.watch(effectiveRatesProvider);
  final base = ref.watch(baseCurrencyProvider).toUpperCase();
  return breakdown.whenData((values) => computeConvertedNetWorth(
      breakdown: values, rates: rates.valueOrNull ?? {}, base: base));
});

final displayConvertedAssetCompositionProvider = Provider.autoDispose<
    AsyncValue<List<({String type, double totalBalance})>>>((ref) {
  final accounts = ref.watch(allAccountsStreamProvider).valueOrNull;
  final rates = ref.watch(effectiveRatesProvider).valueOrNull ?? {};
  final base = ref.watch(baseCurrencyProvider).toUpperCase();
  if (accounts == null) return const AsyncLoading();
  return ref.watch(displayAllAccountStatsProvider).whenData((values) {
    final groups = <String, double>{};
    for (final a in accounts) {
      final amount = computeNativeAmount(
          amount: values[a.id]?.balance ?? 0,
          accountCurrency: a.currency,
          ledgerBase: base,
          rates: rates);
      if (amount == null) continue;
      groups.update(a.type, (v) => v + amount, ifAbsent: () => amount);
    }
    return groups.entries
        .map((e) => (type: e.key, totalBalance: e.value))
        .toList();
  });
});
