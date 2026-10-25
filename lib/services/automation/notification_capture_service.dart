import 'dart:convert';
import 'package:flutter/services.dart';

class CapturedNotification {
  final String id, packageName, text, state;
  final DateTime postedAt, capturedAt;
  CapturedNotification.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        packageName = json['package'] as String,
        text = json['text'] as String? ?? '',
        state = json['state'] as String,
        postedAt = DateTime.fromMillisecondsSinceEpoch(json['postedAt'] as int),
        capturedAt =
            DateTime.fromMillisecondsSinceEpoch(json['capturedAt'] as int);
}

class NotificationExpense {
  final int? cents;
  final String reason;
  const NotificationExpense(this.cents, this.reason);
  bool get canConfirm => cents != null;
}

/// Deterministic, local-only and deliberately conservative. No AI/network calls.
class NotificationExpenseParser {
  static NotificationExpense parse(String text) {
    if (RegExp(
            r'转账|划转|提现|充值|还款|退款|退回|收款|到账|收入|红包|收钱|失败|取消|待支付|待付款|验证码|优惠|立减|外币|美元|港币|USD|HKD|EUR|(?<![A-Za-z])分(?!钟)')
        .hasMatch(text)) {
      return const NotificationExpense(null, '转账、收入、退款、营销或状态不明确，不自动视为日常支出');
    }
    // Amount must directly follow an explicit debit verb (not card tail, date or balance).
    final normalized = text.replaceAllMapped(
      RegExp(r'([¥￥])\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)(?![0-9.])'),
      (m) => '${m[2]}元',
    );
    final matches = RegExp(
      r'(?:支付成功|付款成功|消费成功|扣款成功|支付|付款|消费|支出|扣款)(?:人民币|金额|成功|[：:\s()（）])*\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)\s*(?:元|人民币|RMB|CNY)',
      caseSensitive: false,
    ).allMatches(normalized).toList();
    if (matches.length != 1) {
      return const NotificationExpense(null, '未找到唯一、明确的人民币支出金额，请核对原文或使用账单导入');
    }
    final amount = matches.single.group(1)!.replaceAll(',', '');
    final parts = amount.split('.');
    final cents = int.tryParse(parts.first);
    if (cents == null || cents > 100000000) {
      return const NotificationExpense(null, '金额超出安全范围');
    }
    final value = cents * 100 +
        int.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
    if (value <= 0) return const NotificationExpense(null, '金额必须大于零');
    return NotificationExpense(value, '已提取人民币支出，仍需人工确认；银行与支付平台可能重复通知同一笔交易');
  }
}

class NotificationCaptureService {
  static const channel = MethodChannel('beecount/notification_capture');
  Future<Map<String, dynamic>> status() async => Map<String, dynamic>.from(
      await channel.invokeMapMethod<String, dynamic>('status') ?? {});
  Future<void> configure({bool? enabled, List<String>? packages}) =>
      channel.invokeMethod('configure', {
        if (enabled != null) 'enabled': enabled,
        if (packages != null) 'packages': packages,
      });
  Future<void> openAccess() => channel.invokeMethod('openAccess');
  Future<void> reconnect() => channel.invokeMethod('reconnect');
  Future<void> clear() => channel.invokeMethod('clear');
  Future<List<CapturedNotification>> events() async {
    final data =
        jsonDecode(await channel.invokeMethod<String>('events') ?? '[]')
            as List;
    return data
        .map((e) =>
            CapturedNotification.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> resolve(String id, {required bool confirmed}) =>
      channel.invokeMethod('resolve', {
        'id': id,
        'state': confirmed ? 'confirmed' : 'ignored',
      });
}
