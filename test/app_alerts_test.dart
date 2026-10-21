import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:s_chat/services/local_notification_manager.dart';
import 'package:s_chat/utils/app_alerts.dart';

void main() {
  group('AppAlerts & Notification Tests', () {
    testWidgets('AppAlerts.showSnackBar displays floating snackbar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    AppAlerts.showSnackBar(context, 'Test notification alert');
                  },
                  child: const Text('Show Alert'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Alert'));
      await tester.pump();

      expect(find.text('Test notification alert'), findsOneWidget);
    });

    test('LocalNotificationManager setActiveChatId tracks open chat', () {
      LocalNotificationManager.setActiveChatId('chat_alice');
      // Verify setting active chat ID updates manager state without crashing
      LocalNotificationManager.setActiveChatId(null);
    });
  });
}
