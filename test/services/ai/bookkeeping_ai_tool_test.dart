import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/ai/bookkeeping_ai_tool.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BeeDatabase db;
  late LocalRepository repository;
  late int ledgerId;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repository = LocalRepository(db);
    ledgerId = await repository.createLedger(name: 'AI');
  });

  tearDown(() => db.close());

  test('exposes tool schema and ledger CRUD', () async {
    final tool = DefaultBookkeepingAiTool(repository: repository);
    expect(tool.name, 'bookkeeping');
    expect(tool.parametersSchema['properties'], isA<Map>());

    final listed = await tool.execute({'operation': 'list_ledgers'});
    expect(listed.success, isTrue);
    expect((listed.data['ledgers'] as List), hasLength(1));

    final updated = await tool.execute({
      'operation': 'update_ledger',
      'ledgerId': ledgerId,
      'name': 'AI updated',
    });
    expect(updated.success, isTrue);
    expect((await repository.getLedgerById(ledgerId))!.name, 'AI updated');
  });

  test('prevents duplicate transaction creation', () async {
    final tool = DefaultBookkeepingAiTool(repository: repository);
    final args = {
      'operation': 'create_transaction',
      'ledgerId': ledgerId,
      'type': 'expense',
      'amount': 12.5,
      'happenedAt': '2026-09-04T10:00:00Z',
      'note': 'coffee',
    };
    final first = await tool.execute(args);
    final second = await tool.execute(args);
    expect(first.success, isTrue);
    expect(second.success, isFalse);
    expect(second.data['duplicate'], isTrue);
    expect((await repository.getTransactionsByLedger(ledgerId)), hasLength(1));
  });
}
