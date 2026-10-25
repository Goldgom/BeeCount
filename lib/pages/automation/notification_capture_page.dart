import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers.dart';
import '../../services/automation/notification_capture_service.dart';
import '../data/import_page.dart';

class NotificationCapturePage extends ConsumerStatefulWidget {
  const NotificationCapturePage({super.key});
  @override
  ConsumerState<NotificationCapturePage> createState() =>
      _NotificationCapturePageState();
}

class _NotificationCapturePageState
    extends ConsumerState<NotificationCapturePage> with WidgetsBindingObserver {
  final _service = NotificationCaptureService();
  Map<String, dynamic> _status = {};
  List<CapturedNotification> _events = [];
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final status = await _service.status();
      final events = await _service.events();
      if (mounted) {
        setState(() {
          _status = status;
          _events = events.where((e) => e.state == 'pending').toList()
            ..sort((a, b) => b.postedAt.compareTo(a.postedAt));
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '读取失败：$e');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _time(dynamic value) => value is int && value > 0
      ? DateTime.fromMillisecondsSinceEpoch(value)
          .toLocal()
          .toString()
          .split('.')
          .first
      : '暂无';
  Future<void> _sources() async {
    final controller = TextEditingController(
        text: (_status['packages'] as List? ?? []).join('\n'));
    final answer = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('允许的来源包名'),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    '仅采集下列应用的交易相关通知。银行不同版本包名可能不同，请核实后每行填写一个；不要加入聊天或其他无关应用。'),
                TextField(
                    controller: controller,
                    maxLines: 10,
                    decoration: const InputDecoration(labelText: 'Android 包名')),
              ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, controller.text),
                    child: const Text('保存'))
              ],
            ));
    // Dialog animation may still reference its controller; let it be collected with the route.
    if (answer != null) {
      await _run(() => _service.configure(
          packages: answer
              .split(RegExp(r'[\s,]+'))
              .where((p) => p.isNotEmpty)
              .toSet()
              .toList()));
    }
  }

  Future<void> _confirm(
      CapturedNotification event, NotificationExpense parsed) async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    final repo = ref.read(repositoryProvider);
    final ledger = await ref.read(ledgerByIdProvider(ledgerId).future);
    if (ledger == null || ledger.currency != 'CNY' || ledger.isShared) {
      throw StateError('请先切换到人民币个人账本；共享账本与外币账本请手工记账');
    }
    // Stable UUID-shaped sync ID: a crash after DB commit but before resolve is safe to retry.
    final h = event.id;
    final syncId =
        '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20, 32)}';
    final existing = await repo.getTransactionBySyncId(syncId);
    if (existing != null) {
      await _service.resolve(event.id, confirmed: true);
      return;
    }
    final amount = parsed.cents! / 100;
    final recent = await repo.getRecentTransactionsWithCategory(
        ledgerId: ledgerId, limit: 300);
    final duplicates = recent
        .where((r) =>
            r.t.type == 'expense' &&
            (r.t.amount - amount).abs() < 0.005 &&
            r.t.happenedAt.difference(event.postedAt).inMinutes.abs() <= 10)
        .length;
    if (!mounted) return;
    final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text('确认支出 ¥${amount.toStringAsFixed(2)}'),
              content: SingleChildScrollView(
                  child: Text(
                      '账本：${ledger.name}\n时间：${event.postedAt.toLocal()}\n来源：${event.packageName}\n\n${event.text}\n\n'
                      '${duplicates > 0 ? '⚠ 附近已有 $duplicates 笔同金额支出，可能已手记、导入或由银行重复通知，请优先取消核对。\n\n' : ''}'
                      '请自行核对是否真实消费和交易时间。将保存为未分类、无账户支出，不改变银行卡余额。原文不写入账本或同步，只保存本地来源指纹。')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('已核对，记入账本'))
              ],
            ));
    if (accepted != true) return;
    await repo.addTransaction(
        ledgerId: ledgerId,
        type: 'expense',
        amount: amount,
        happenedAt: event.postedAt,
        currencyCode: 'CNY',
        nativeAmount: amount,
        syncId: syncId,
        note: '通知采集 · ${event.packageName} · ${event.id.substring(0, 12)}');
    await _service.resolve(event.id, confirmed: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('支出通知采集'), actions: [
          IconButton(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
              tooltip: '刷新诊断')
        ]),
        body: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              const Text('通知 → 本地候选 → 人工确认',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                  '不读取支付账户、不发起支付或划转、不使用无障碍、不上传通知原文。只有你主动授予系统“通知使用权”后才能采集。'),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用本地采集'),
                  subtitle: const Text('默认关闭；停用后不再采集，已有候选仍保留'),
                  value: _status['enabled'] == true,
                  onChanged: _busy
                      ? null
                      : (v) => _run(() => _service.configure(enabled: v))),
              Wrap(spacing: 8, children: [
                OutlinedButton(
                    onPressed: _busy ? null : () => _run(_service.openAccess),
                    child: const Text('手动授予／撤销通知使用权')),
                OutlinedButton(
                    onPressed: _busy ? null : () => _run(_service.reconnect),
                    child: const Text('请求重新连接')),
                TextButton(
                    onPressed: _busy ? null : _sources,
                    child: const Text('管理微信／支付宝／银行来源')),
              ]),
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                          '系统授权：${_status['granted'] == true ? '已授权' : '未授权'}\n'
                          '监听连接：${_status['connected'] == true ? '已连接' : '未连接'}\n'
                          '最近连接：${_time(_status['connectedAt'])}\n最近采集：${_time(_status['lastCapturedAt'])}\n'
                          '待确认：${_events.length}\n${_status['error'] ?? ''}'))),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
              const Text(
                  'Android 无法保证 100% 获取流水：支付应用可能不发通知或隐藏金额，Android 15+ 敏感内容、锁屏、工作资料与厂商后台限制均可能导致缺失。强制停止后需重新打开应用；系统重连只可恢复仍显示的通知。请开启来源应用的交易通知，并在系统电池／自启动设置中允许运行。'),
              TextButton.icon(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const ImportPage())),
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('微信／支付宝账单导入补漏与对账')),
              const Divider(),
              const Text('待确认（无法明确识别的通知仅供核对，不可一键入账）'),
              if (_events.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('暂无候选。启用并授权后，下一条含交易信息的通知才会进入此处；不会读取历史账单。')),
              ..._events.map((event) {
                final parsed = NotificationExpenseParser.parse(event.text);
                return Card(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  parsed.canConfirm
                                      ? '支出候选 ¥${(parsed.cents! / 100).toStringAsFixed(2)}'
                                      : '需人工核对',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              Text(
                                  '${event.packageName}\n通知时间：${event.postedAt.toLocal()}\n采集时间：${event.capturedAt.toLocal()}'),
                              Text(parsed.reason),
                              ExpansionTile(
                                  title: const Text('查看原文（仅本地）'),
                                  children: [SelectableText(event.text)]),
                              Wrap(spacing: 8, children: [
                                if (parsed.canConfirm)
                                  FilledButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _run(
                                              () => _confirm(event, parsed)),
                                      child: const Text('核对并确认支出')),
                                TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _run(() => _service.resolve(
                                            event.id,
                                            confirmed: false)),
                                    child: const Text('忽略并删除原文')),
                              ]),
                            ])));
              }),
              const Divider(),
              const Text(
                  '原文保存在应用私有、不参与系统备份的本地目录；确认或忽略后立即删除原文，仅保留去重指纹及来源／时间。卸载会清除。请勿把原文截图分享给他人。队列上限 5000 条，满时停止采集并在此提示。'),
              TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final yes = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                      title: const Text('清空全部采集数据？'),
                                      content: const Text(
                                          '包含尚未确认的原文及去重历史；不删除已记入的账单。仍显示的旧通知可能在重新连接时再次采集。'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('取消')),
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text('清空'))
                                      ]));
                          if (yes == true) await _run(_service.clear);
                        },
                  child: const Text('清空本地采集原文及去重历史')),
            ])),
      );
}
