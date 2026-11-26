import 'package:elets_salescall_ai/core/theme/app_theme.dart';
import 'package:elets_salescall_ai/features/dialer/presentation/dialer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The keypad tab must show the whole dialer (number, keypad, call button) without scrolling on
/// common phone screens. Sizes are the space left for the tab body after status bar, app bar with
/// tabs, and bottom navigation.
void main() {
  const phoneBodies = <String, Size>{
    'small phone (320x568)': Size(320, 380),
    'typical Android (360x800)': Size(360, 560),
    'large phone (412x915)': Size(412, 680),
  };

  for (final entry in phoneBodies.entries) {
    testWidgets('call button is on screen without scrolling: ${entry.key}', (tester) async {
      final body = entry.value;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: body.width, height: body.height, child: const KeypadTab()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final call = find.byTooltip('Call');
      expect(call, findsOneWidget);
      final rect = tester.getRect(call);
      expect(rect.bottom, lessThanOrEqualTo(body.height), reason: 'call button bottom ${rect.bottom}');
      expect(rect.right, lessThanOrEqualTo(body.width));
      expect(tester.getRect(find.byKey(const ValueKey('dialer-backspace'))).bottom, lessThanOrEqualTo(body.height));
      expect(tester.getRect(find.byKey(const ValueKey('dialer-key-1'))).top, greaterThan(0));
    });
  }

  testWidgets('typing on the keypad fills the number; call with no number explains what to do', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SizedBox(width: 360, height: 560, child: KeypadTab())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Call'));
    await tester.pump();
    expect(find.text('Enter a number, or search for a lead to call.'), findsOneWidget);

    for (final key in ['9', '8', '7']) {
      await tester.tap(find.byKey(ValueKey('dialer-key-$key')));
    }
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(const ValueKey('dialer-number')));
    expect(field.controller!.text, '987');
    expect(field.keyboardType, TextInputType.none, reason: 'the system keyboard must not cover the keypad');
  });
}
