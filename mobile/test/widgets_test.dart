import 'package:elets_salescall_ai/core/models/enums.dart';
import 'package:elets_salescall_ai/core/router/app_router.dart';
import 'package:elets_salescall_ai/core/theme/app_theme.dart';
import 'package:elets_salescall_ai/core/theme/status_colors.dart';
import 'package:elets_salescall_ai/core/widgets/stat_card.dart';
import 'package:elets_salescall_ai/core/widgets/status_chip.dart';
import 'package:elets_salescall_ai/features/dialer/presentation/dialer_keypad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('StatCard shows value and label and handles taps', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 200,
          height: 140,
          child: StatCard(label: 'Connected', value: '25', icon: Icons.call, onTap: () => tapped++),
        ),
      ),
    );
    expect(find.text('25'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    await tester.tap(find.byType(StatCard));
    expect(tapped, 1);
  });

  testWidgets('StatusChip uses the semantic colour for call statuses', (tester) async {
    await tester.pumpWidget(_wrap(StatusChip.callStatus(CallStatus.notAnswered)));
    final text = tester.widget<Text>(find.text('Not Answered'));
    expect(text.style?.color, callStatusColor(CallStatus.notAnswered));
    expect(find.byIcon(Icons.phone_missed), findsOneWidget);

    await tester.pumpWidget(_wrap(StatusChip.leadStatus(LeadStatus.converted)));
    expect(find.text('Converted'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Converted')).style?.color, AppColors.success);
  });

  testWidgets('DialerKeypad emits digits, backspace and clear', (tester) async {
    final typed = <String>[];
    var backspaces = 0;
    var clears = 0;
    await tester.pumpWidget(
      _wrap(DialerKeypad(onKey: typed.add, onBackspace: () => backspaces++, onClear: () => clears++)),
    );

    for (final key in ['9', '8', '*', '0', '#']) {
      await tester.tap(find.byKey(ValueKey('dialer-key-$key')));
    }
    expect(typed, ['9', '8', '*', '0', '#']);

    await tester.longPress(find.byKey(const ValueKey('dialer-key-0')));
    expect(typed.last, '+');

    await tester.tap(find.byKey(const ValueKey('dialer-backspace')));
    expect(backspaces, 1);
    await tester.longPress(find.byKey(const ValueKey('dialer-backspace')));
    expect(clears, 1);
    expect(find.text('ABC'), findsOneWidget);
  });

  test('role guard keeps executives out of management routes', () {
    expect(roleRedirect(UserRole.executive, '/analytics'), '/dashboard');
    expect(roleRedirect(UserRole.executive, '/team'), '/dashboard');
    expect(roleRedirect(UserRole.executive, '/ai/campaigns/abc'), '/dashboard');
    expect(roleRedirect(UserRole.executive, '/ai'), isNull);
    expect(roleRedirect(UserRole.executive, '/performance'), isNull);
    expect(roleRedirect(UserRole.manager, '/analytics'), isNull);
    expect(roleRedirect(UserRole.manager, '/settings'), '/dashboard');
    expect(roleRedirect(UserRole.manager, '/ai/agents/new'), '/dashboard');
    expect(roleRedirect(UserRole.manager, '/team/users/u1'), '/dashboard');
    expect(roleRedirect(UserRole.admin, '/settings'), isNull);
    expect(roleRedirect(UserRole.admin, '/team/users/new'), isNull);
  });
}
