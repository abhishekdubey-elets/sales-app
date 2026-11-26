import 'package:elets_salescall_ai/core/models/enums.dart';
import 'package:elets_salescall_ai/core/theme/app_theme.dart';
import 'package:elets_salescall_ai/features/auth/presentation/login_screen.dart';
import 'package:elets_salescall_ai/features/calls/data/call_models.dart';
import 'package:elets_salescall_ai/features/dialer/presentation/device_call_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget home) => ProviderScope(
  child: MaterialApp(theme: AppTheme.light(), home: home),
);

void main() {
  testWidgets('sign-in starts with Continue as Admin / Continue as Employee', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(const LoginScreen()));
    await tester.pump();

    expect(find.text('Continue as Admin'), findsOneWidget);
    expect(find.text('Continue as Employee'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);

    await tester.tap(find.byKey(const ValueKey('portal-employee')));
    await tester.pump();
    expect(find.text('Employee sign in'), findsOneWidget);
    expect(find.text('Sign in as Employee'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));

    // "Change" goes back to the choice
    await tester.tap(find.byKey(const ValueKey('portal-change')));
    await tester.pump();
    expect(find.text('Continue as Admin'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('portal-admin')));
    await tester.pump();
    expect(find.text('Admin sign in'), findsOneWidget);
  });

  testWidgets('phone call screen asks how the call went', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final start = DeviceCallStart(
      call: HumanCall.fromJson({
        'id': 'c1',
        'direction': 'outbound',
        'lead_id': 'l1',
        'lead_name': 'Asha Verma',
        'phone_number': '+91•••••••3210',
        'salesperson_id': 'u1',
        'salesperson_name': 'Rohit Sharma',
        'provider': 'device',
        'status': 'initiated',
        'started_at': '2026-11-26T10:00:00Z',
        'duration_seconds': 0,
        'talk_seconds': 0,
        'notes': <dynamic>[],
        'created_at': '2026-11-26T10:00:00Z',
      }),
      dialNumber: '+919876543210',
    );
    expect(start.call.status, CallStatus.initiated);

    final dialed = <Uri>[];
    await tester.pumpWidget(
      _app(
        DeviceCallScreen(
          start: start,
          openDialer: (uri) async {
            dialed.add(uri);
            return false; // simulate a phone where the dialer can't be opened
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(dialed.single.toString(), 'tel:+919876543210');

    expect(find.text('Asha Verma'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('How did it go?'), findsOneWidget);
    expect(find.textContaining('Dial +919876543210 manually'), findsOneWidget);

    // Talk time is asked only for connected calls.
    expect(find.text('Talk time (min:sec)'), findsNothing);
    await tester.tap(find.text('Connected'));
    await tester.pump();
    expect(find.text('Talk time (min:sec)'), findsOneWidget);

    // Saving without a valid duration explains the format instead of submitting.
    await tester.enterText(find.byType(TextField), '2:75');
    await tester.tap(find.text('Save and add outcome'));
    await tester.pump();
    expect(find.text('Enter the duration as minutes:seconds, e.g. 2:30'), findsOneWidget);
  });
}
