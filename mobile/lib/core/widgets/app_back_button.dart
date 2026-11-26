import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Back arrow for full-screen routes. When the page was opened directly
/// (deep link, browser reload) there is nothing to pop, so it goes home.
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BackButton(
      onPressed: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/dashboard');
        }
      },
    );
  }
}
