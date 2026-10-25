import '../../data/db.dart';
import '../../data/repositories/base_repository.dart';

/// 通用记账 AI 工具协议。
///
/// 该协议只依赖 [BaseRepository]，与 OpenAI、智谱或本地模型无关，
/// 可直接映射到 function calling / tool calling 的 name、description 和
/// JSON schema。
abstract class BookkeepingAiTool {
  String get name;
  String get description;
  Map<String, dynamic> get parametersSchema;

  Future<BookkeepingToolResult> execute(Map<String, dynamic> arguments);
}

class BookkeepingToolResult {
  final bool success;
  final String? error;
  final Map<String, dynamic> data;

  const BookkeepingToolResult.success([this.data = const {}])
      : success = true,
        error = null;

  const BookkeepingToolResult.failure(this.error, {this.data = const {}})
      : success = false;

  Map<String, dynamic> toJson() => {
        'success': success,
        if (error != null) 'error': error,
        'data': data,
      };
}

/// 面向 AI 的账本工具实现。
///
/// 支持：账本和交易 CRUD、总账修复、时间核对以及重复记账检测。
class DefaultBookkeepingAiTool implements BookkeepingAiTool {
  final BaseRepository repository;
  final Duration duplicateTimeTolerance;

  DefaultBookkeepingAiTool({
    required this.repository,
    this.duplicateTimeTolerance = const Duration(minutes: 2),
  });

  @override
  String get name => 'bookkeeping';

  @override
  String get description =>
      '管理 BeeCount 账本和交易，支持增删改查、总账修复、时间核对和重复记账检测';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'operation': {
            'type': 'string',
            'enum': [
              'list_ledgers',
              'query_ledgers',
              'get_ledger',
              'create_ledger',
              'update_ledger',
              'delete_ledger',
              'list_transactions',
              'query_transactions',
              'get_transaction',
              'create_transaction',
              'update_transaction',
              'delete_transaction',
              'repair_ledger',
              'repair_general_ledger',
              'check_time',
              'find_duplicates',
              'check_duplicates',
            ],
          },
          'ledgerId': {'type': 'integer'},
          'transactionId': {'type': 'integer'},
          'name': {'type': 'string'},
          'currency': {'type': 'string'},
          'type': {'type': 'string', 'enum': ['income', 'expense', 'transfer']},
          'amount': {'type': 'number'},
          'categoryId': {'type': 'integer'},
          'accountId': {'type': 'integer'},
          'toAccountId': {'type': 'integer'},
          'happenedAt': {'type': 'string', 'format': 'date-time'},
          'note': {'type': 'string'},
          'start': {'type': 'string', 'format': 'date-time'},
          'end': {'type': 'string', 'format': 'date-time'},
          'limit': {'type': 'integer', 'minimum': 1, 'maximum': 500},
          'monthStartDay': {'type': 'integer', 'minimum': 1, 'maximum': 28},
          'currencyCode': {'type': 'string'},
          'nativeAmount': {'type': 'number'},
        },
        'required': ['operation'],
      };

  @override
  Future<BookkeepingToolResult> execute(Map<String, dynamic> arguments) async {
    try {
      final operation = arguments['operation']?.toString();
      if (operation == null || operation.isEmpty) {
        return const BookkeepingToolResult.failure('缺少 operation');
      }
      switch (operation) {
        case 'list_ledgers':
        case 'query_ledgers':
          return _listLedgers();
        case 'get_ledger':
          return _getLedger(_int(arguments['ledgerId']));
        case 'create_ledger':
          return _createLedger(arguments);
        case 'update_ledger':
          return _updateLedger(arguments);
        case 'delete_ledger':
          return _deleteLedger(_int(arguments['ledgerId']));
        case 'list_transactions':
        case 'query_transactions':
          return _listTransactions(arguments);
        case 'get_transaction':
          return _getTransaction(_int(arguments['transactionId']));
        case 'create_transaction':
          return _createTransaction(arguments);
        case 'update_transaction':
          return _updateTransaction(arguments);
        case 'delete_transaction':
          return _deleteTransaction(_int(arguments['transactionId']));
        case 'repair_ledger':
        case 'repair_general_ledger':
          return _repairLedger(_int(arguments['ledgerId']));
        case 'check_time':
          return _checkTime(arguments);
        case 'find_duplicates':
        case 'check_duplicates':
          return _findDuplicates(arguments);
        default:
          return BookkeepingToolResult.failure('不支持的 operation: $operation');
      }
    } catch (e) {
      return BookkeepingToolResult.failure(e.toString());
    }
  }

  int _int(dynamic value) {
    if (value is int) return value;
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null) throw ArgumentError('ID 必须是整数');
    return parsed;
  }

  double _double(dynamic value) {
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value?.toString() ?? '');
    if (parsed == null) throw ArgumentError('金额必须是数字');
    return parsed;
  }

  DateTime _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) throw ArgumentError('时间必须是 ISO-8601 格式');
    return date;
  }

  Map<String, dynamic> _ledgerJson(Ledger l) => {
        'id': l.id,
        'name': l.name,
        'currency': l.currency,
        'type': l.type,
        'isShared': l.isShared,
        'myRole': l.myRole,
        'monthStartDay': l.monthStartDay,
      };

  Map<String, dynamic> _txJson(Transaction t) => {
        'id': t.id,
        'ledgerId': t.ledgerId,
        'type': t.type,
        'amount': t.amount,
        'categoryId': t.categoryId,
        'accountId': t.accountId,
        'toAccountId': t.toAccountId,
        'happenedAt': t.happenedAt.toIso8601String(),
        'note': t.note,
        'currencyCode': t.currencyCode,
        'nativeAmount': t.nativeAmount,
      };

  Future<BookkeepingToolResult> _listLedgers() async {
    final ledgers = await repository.getAllLedgers();
    return BookkeepingToolResult.success({
      'ledgers': ledgers.map(_ledgerJson).toList(),
    });
  }

  Future<BookkeepingToolResult> _getLedger(int id) async {
    final ledger = await repository.getLedgerById(id);
    if (ledger == null) return BookkeepingToolResult.failure('账本不存在: $id');
    final stats = await repository.getLedgerStats(ledgerId: id);
    return BookkeepingToolResult.success({
      'ledger': _ledgerJson(ledger),
      'stats': {'balance': stats.balance, 'transactionCount': stats.transactionCount},
    });
  }

  Future<BookkeepingToolResult> _createLedger(Map<String, dynamic> a) async {
    final name = a['name']?.toString().trim();
    if (name == null || name.isEmpty) return const BookkeepingToolResult.failure('缺少账本名称');
    final id = await repository.createLedger(
      name: name,
      currency: (a['currency']?.toString().trim().toUpperCase().isNotEmpty ?? false)
          ? a['currency'].toString().trim().toUpperCase()
          : 'CNY',
    );
    return BookkeepingToolResult.success({'ledgerId': id});
  }

  Future<BookkeepingToolResult> _updateLedger(Map<String, dynamic> a) async {
    final id = _int(a['ledgerId']);
    if (await repository.getLedgerById(id) == null) {
      return BookkeepingToolResult.failure('账本不存在: $id');
    }
    await repository.updateLedger(
      id: id,
      name: a['name']?.toString(),
      currency: a['currency']?.toString().toUpperCase(),
      monthStartDay: a['monthStartDay'] == null ? null : _int(a['monthStartDay']),
    );
    return const BookkeepingToolResult.success();
  }

  Future<BookkeepingToolResult> _deleteLedger(int id) async {
    if (await repository.getLedgerById(id) == null) {
      return BookkeepingToolResult.failure('账本不存在: $id');
    }
    await repository.deleteLedger(id);
    return BookkeepingToolResult.success({'deletedLedgerId': id});
  }

  Future<BookkeepingToolResult> _listTransactions(Map<String, dynamic> a) async {
    final ledgerId = _int(a['ledgerId']);
    var txs = await repository.getTransactionsByLedger(ledgerId);
    final start = a['start'] == null ? null : _date(a['start']);
    final end = a['end'] == null ? null : _date(a['end']);
    if (start != null || end != null) {
      txs = txs.where((t) {
        if (start != null && t.happenedAt.isBefore(start)) return false;
        if (end != null && !t.happenedAt.isBefore(end)) return false;
        return true;
      }).toList();
    }
    final limit = (a['limit'] == null ? 100 : _int(a['limit'])).clamp(1, 500).toInt();
    txs.sort((x, y) => y.happenedAt.compareTo(x.happenedAt));
    return BookkeepingToolResult.success({
      'transactions': txs.take(limit).map(_txJson).toList(),
      'total': txs.length,
    });
  }

  Future<BookkeepingToolResult> _getTransaction(int id) async {
    final tx = await repository.getTransactionById(id);
    if (tx == null) return BookkeepingToolResult.failure('交易不存在: $id');
    return BookkeepingToolResult.success({'transaction': _txJson(tx)});
  }

  Future<BookkeepingToolResult> _createTransaction(Map<String, dynamic> a) async {
    final ledgerId = _int(a['ledgerId']);
    final type = a['type']?.toString();
    if (type == null || !{'income', 'expense', 'transfer'}.contains(type)) {
      return const BookkeepingToolResult.failure('type 必须是 income、expense 或 transfer');
    }
    final amount = _double(a['amount']);
    if (amount == 0) return const BookkeepingToolResult.failure('金额不能为 0');
    final happenedAt = a['happenedAt'] == null ? DateTime.now() : _date(a['happenedAt']);
    // 幂等保护：同一账本内相同类型、金额、备注且时间接近的记录视为重复，
    // 不再写入数据库，并把已有交易返回给模型/UI 进行确认。
    final existing = await repository.getTransactionsByLedger(ledgerId);
    Transaction? duplicate;
    for (final candidate in existing) {
      final closeInTime = candidate.happenedAt
              .difference(happenedAt)
              .inMilliseconds
              .abs() <=
          duplicateTimeTolerance.inMilliseconds;
      if (candidate.type == type &&
          (candidate.amount - amount.abs()).abs() < 0.000001 &&
          closeInTime &&
          (candidate.note ?? '').trim() == (a['note']?.toString() ?? '').trim()) {
        duplicate = candidate;
        break;
      }
    }
    if (duplicate != null) {
      return BookkeepingToolResult.failure('检测到疑似重复记账', data: {
        'duplicate': true,
        'existingTransaction': _txJson(duplicate),
      });
    }
    final id = await repository.addTransaction(
      ledgerId: ledgerId,
      type: type,
      amount: amount.abs(),
      categoryId: a['categoryId'] == null ? null : _int(a['categoryId']),
      accountId: a['accountId'] == null ? null : _int(a['accountId']),
      toAccountId: a['toAccountId'] == null ? null : _int(a['toAccountId']),
      happenedAt: happenedAt,
      note: a['note']?.toString(),
      currencyCode: a['currencyCode']?.toString().toUpperCase(),
      nativeAmount: a['nativeAmount'] == null ? null : _double(a['nativeAmount']),
    );
    return BookkeepingToolResult.success({'transactionId': id});
  }

  Future<BookkeepingToolResult> _updateTransaction(Map<String, dynamic> a) async {
    final id = _int(a['transactionId']);
    final old = await repository.getTransactionById(id);
    if (old == null) return BookkeepingToolResult.failure('交易不存在: $id');
    await repository.updateTransaction(
      id: id,
      type: a['type']?.toString() ?? old.type,
      amount: a['amount'] == null ? old.amount : _double(a['amount']).abs(),
      categoryId: a['categoryId'] == null ? old.categoryId : _int(a['categoryId']),
      note: a.containsKey('note') ? a['note']?.toString() : old.note,
      happenedAt: a['happenedAt'] == null ? old.happenedAt : _date(a['happenedAt']),
      currencyCode: a['currencyCode']?.toString(),
      nativeAmount: a['nativeAmount'] == null ? null : _double(a['nativeAmount']),
    );
    if (a.containsKey('accountId') || a.containsKey('toAccountId')) {
      await repository.updateTransactionFields(
        id: id,
        accountId: a.containsKey('accountId') ? (a['accountId'] == null ? null : _int(a['accountId'])) : null,
        toAccountId: a.containsKey('toAccountId') ? (a['toAccountId'] == null ? null : _int(a['toAccountId'])) : null,
        writeAccountSyncIdOverride: false,
        writeToAccountSyncIdOverride: false,
      );
    }
    return const BookkeepingToolResult.success();
  }

  Future<BookkeepingToolResult> _deleteTransaction(int id) async {
    if (await repository.getTransactionById(id) == null) {
      return BookkeepingToolResult.failure('交易不存在: $id');
    }
    await repository.deleteTransaction(id);
    return BookkeepingToolResult.success({'deletedTransactionId': id});
  }

  Future<BookkeepingToolResult> _repairLedger(int ledgerId) async {
    final ledger = await repository.getLedgerById(ledgerId);
    if (ledger == null) {
      return BookkeepingToolResult.failure('账本不存在: $ledgerId');
    }
    final recalculated = await repository.recalcNativeAmountsForLedger(
      ledgerId,
      ledger.currency.toUpperCase(),
    );
    final changed = await repository.recomputeForeignTxForLedger(ledgerId);
    final pendingForeign = await repository.countUnconvertedForeignTx(ledgerId);
    final stats = await repository.getLedgerStats(ledgerId: ledgerId);
    return BookkeepingToolResult.success({
      'ledgerId': ledgerId,
      'recomputedTransactions': changed,
      'recalculatedNativeAmounts': recalculated,
      'unconvertedForeignTransactions': pendingForeign,
      'balance': stats.balance,
      'transactionCount': stats.transactionCount,
    });
  }

  Future<BookkeepingToolResult> _checkTime(Map<String, dynamic> a) async {
    final ledgerId = _int(a['ledgerId']);
    final txs = await repository.getTransactionsByLedger(ledgerId);
    final start = a['start'] == null ? null : _date(a['start']);
    final end = a['end'] == null ? null : _date(a['end']);
    final now = DateTime.now();
    final issues = <Map<String, dynamic>>[];
    for (final tx in txs) {
      final t = tx.happenedAt;
      String? reason;
      if (t.isAfter(now.add(const Duration(minutes: 5)))) reason = 'future';
      if (start != null && t.isBefore(start)) reason = 'before_start';
      if (end != null && !t.isBefore(end)) reason = 'after_end';
      if (reason != null) issues.add({'transactionId': tx.id, 'happenedAt': t.toIso8601String(), 'reason': reason});
    }
    return BookkeepingToolResult.success({'ledgerId': ledgerId, 'checked': txs.length, 'issues': issues});
  }

  Future<BookkeepingToolResult> _findDuplicates(Map<String, dynamic> a) async {
    final ledgerId = _int(a['ledgerId']);
    final txs = await repository.getTransactionsByLedger(ledgerId);
    txs.sort((x, y) => x.happenedAt.compareTo(y.happenedAt));
    final groups = <List<int>>[];
    for (var i = 0; i < txs.length; i++) {
      for (var j = i + 1; j < txs.length; j++) {
        final left = txs[i];
        final right = txs[j];
        if (right.happenedAt.difference(left.happenedAt) > duplicateTimeTolerance) break;
        if (left.type == right.type &&
            (left.amount - right.amount).abs() < 0.000001 &&
            left.categoryId == right.categoryId &&
            left.accountId == right.accountId &&
            (left.note ?? '').trim() == (right.note ?? '').trim()) {
          groups.add([left.id, right.id]);
        }
      }
    }
    return BookkeepingToolResult.success({'ledgerId': ledgerId, 'duplicates': groups});
  }
}
