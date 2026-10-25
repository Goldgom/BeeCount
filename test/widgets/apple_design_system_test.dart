import 'package:beecount/styles/tokens.dart';
import 'package:beecount/theme.dart';
import 'package:beecount/widgets/biz/app_list_tile.dart';
import 'package:beecount/widgets/biz/section_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Grouped themes retain Android platform and distinguish card surfaces',
      () {
    for (final theme in [
      BeeTheme.lightTheme(platform: TargetPlatform.android),
      BeeTheme.darkTheme(platform: TargetPlatform.android),
    ]) {
      expect(theme.platform, TargetPlatform.android);
      expect(theme.scaffoldBackgroundColor, isNot(theme.cardTheme.color));
      expect(theme.cardTheme.elevation, 0);
      expect(theme.textTheme.headlineMedium!.fontSize!,
          greaterThan(theme.textTheme.bodyLarge!.fontSize!));
      final a = theme.colorScheme.primary.computeLuminance();
      final b = theme.colorScheme.onPrimary.computeLuminance();
      final contrast =
          (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
      expect(contrast, greaterThan(4.5));
    }
  });

  for (final dark in [false, true]) {
    testWidgets('Grouped row supports large text, semantics and tap ($dark)',
        (tester) async {
      var taps = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        theme: dark ? BeeTheme.darkTheme() : BeeTheme.lightTheme(),
        home: Scaffold(body: Builder(builder: (context) {
          return MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: SectionCard(
                child: AppListTile(
              leading: Icons.account_balance_wallet_outlined,
              title: '投资账户',
              subtitle: '当前估值与账户明细',
              onTap: () => taps++,
            )),
          );
        })),
      ));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(InkWell)).height,
          greaterThanOrEqualTo(48));
      await tester.tap(find.text('投资账户'));
      expect(taps, 1);
      final context = tester.element(find.byType(SectionCard));
      expect(BeeTokens.surface(context), Theme.of(context).cardTheme.color);
      semantics.dispose();
    });
  }
}
