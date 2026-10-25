import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beecount/services/automation/notification_capture_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('local expense parser', () {
    test(
        'wechat, alipay and bank debit amount rather than balance or card tail',
        () {
      for (final text in [
        '微信支付\n支付成功：12.30元',
        '微信支付\n支付成功 ￥12.30',
        '工商银行\n消费（人民币）32.50元，余额10000元',
        '支付宝\n付款人民币 1,234.56元',
        '招商银行\n您尾号1234卡10月25日消费人民币32.50元，余额10000.00元',
        '工商银行\n支出人民币100元，余额900元',
      ]) {
        expect(NotificationExpenseParser.parse(text).canConfirm, true,
            reason: text);
      }
      expect(
          NotificationExpenseParser.parse('尾号1234卡消费人民币32.50元，余额10000元').cents,
          3250);
      expect(NotificationExpenseParser.parse('付款人民币 1,234.56元').cents, 123456);
    });
    test('reject transfers, income, marketing, failures, ambiguous and non-CNY',
        () {
      for (final text in [
        '转账支付100元',
        '消费退款20元',
        '支付失败20元',
        '待付款20元',
        '收款到账20元',
        '红包支付20元',
        '充值付款20元',
        '还款支出20元',
        '消费美元20元',
        '优惠支付20元',
        '余额10000元',
        '银行卡尾号1234',
        '支付10元，消费20元',
        '支付0元',
        '支付12.345元',
        '支付-12元',
        '支付成功',
        '向张三转账成功20元',
        '支付20元，立减3元',
      ]) {
        expect(NotificationExpenseParser.parse(text).canConfirm, false,
            reason: text);
      }
    });
    test('never treats a date or card tail as amount', () {
      expect(
          NotificationExpenseParser.parse('消费提醒：卡1234，2026-10-25，余额500元')
              .canConfirm,
          false);
    });
  });
  test('durable native queue read and resolve use registered channel',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NotificationCaptureService.channel,
            (call) async {
      calls.add(call);
      if (call.method == 'status') return {'enabled': true, 'granted': false};
      if (call.method == 'events')
        return jsonEncode([
          {
            'id': 'sample',
            'package': 'com.tencent.mm',
            'postedAt': 1000,
            'capturedAt': 2000,
            'text': '支付20元',
            'state': 'pending',
          }
        ]);
      return null;
    });
    final service = NotificationCaptureService();
    expect((await service.status())['granted'], false);
    final event = (await service.events()).single;
    expect(event.packageName, 'com.tencent.mm');
    expect(event.postedAt.millisecondsSinceEpoch, 1000);
    await service.configure(enabled: true, packages: ['com.tencent.mm']);
    await service.resolve(event.id, confirmed: true);
    expect(calls.last.arguments, {'id': 'sample', 'state': 'confirmed'});
    await service.reconnect();
    expect(calls.last.method, 'reconnect');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NotificationCaptureService.channel, null);
  });
}
