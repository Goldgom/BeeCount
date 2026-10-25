import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/finance_display_providers.dart';
import '../../styles/tokens.dart';

class FinanceBalanceStatus extends ConsumerWidget {
  const FinanceBalanceStatus({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(financeDisplaySnapshotProvider);
    final snapshot = state.asData?.value;
    if (!state.isLoading && snapshot?.connected != true)
      return const SizedBox.shrink();
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final pending = ref.watch(financeLocalPendingProvider);
    String label;
    if (pending) {
      label = zh
          ? '同步中或有待上传变更 · 显示本地数据'
          : 'Syncing or pending changes · showing local data';
    } else if (state.isLoading) {
      label = zh
          ? '正在更新云端余额 · 暂显示本地旧数据'
          : 'Updating cloud balances · showing local data';
    } else if (snapshot!.stale) {
      label = zh
          ? '云端不可用 · 本地数据可能已过期'
          : 'Cloud unavailable · local data may be outdated';
    } else {
      final times = snapshot.balances.values.map((e) => e.asOf).toList()
        ..sort();
      final time = times.isEmpty ? null : times.first.toLocal();
      final stamp = time == null
          ? ''
          : ' · ${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      label = zh
          ? '云端余额$stamp · 未匹配账户使用本地值'
          : 'Cloud balances$stamp · unmatched accounts use local values';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [
        Icon(
            snapshot?.stale == true
                ? Icons.cloud_off_outlined
                : Icons.cloud_outlined,
            size: 16,
            color: BeeTokens.textSecondary(context)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: BeeTokens.textSecondary(context)))),
        IconButton(
            tooltip: zh ? '刷新云端余额' : 'Refresh cloud balances',
            onPressed: state.isLoading
                ? null
                : () => ref.invalidate(financeDisplaySnapshotProvider),
            icon: const Icon(Icons.refresh, size: 20)),
      ]),
    );
  }
}
