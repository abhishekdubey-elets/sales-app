import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 0–9, *, # keypad. Backspace clears one digit; long-press clears all.
class DialerKeypad extends StatelessWidget {
  const DialerKeypad({super.key, required this.onKey, required this.onBackspace, required this.onClear});

  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  static const keys = [
    ('1', ''),
    ('2', 'ABC'),
    ('3', 'DEF'),
    ('4', 'GHI'),
    ('5', 'JKL'),
    ('6', 'MNO'),
    ('7', 'PQRS'),
    ('8', 'TUV'),
    ('9', 'WXYZ'),
    ('*', ''),
    ('0', '+'),
    ('#', ''),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < 4; row++)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var col = 0; col < 3; col++)
                _KeyButton(
                  digit: keys[row * 3 + col].$1,
                  letters: keys[row * 3 + col].$2,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onKey(keys[row * 3 + col].$1);
                  },
                  // Long-press 0 types "+" for international numbers.
                  onLongPress: keys[row * 3 + col].$1 == '0' ? () => onKey('+') : null,
                ),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(width: 72),
            const SizedBox(width: 72),
            // InkWell instead of IconButton: an IconButton tooltip would swallow the long-press.
            Semantics(
              button: true,
              label: 'Delete digit. Long-press to clear the number',
              child: InkWell(
                key: const ValueKey('dialer-backspace'),
                customBorder: const CircleBorder(),
                onTap: onBackspace,
                onLongPress: onClear,
                child: const SizedBox(width: 72, height: 56, child: Icon(Icons.backspace_outlined)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.digit, required this.letters, required this.onTap, this.onLongPress});

  final String digit;
  final String letters;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        shape: const CircleBorder(),
        child: InkWell(
          key: ValueKey('dialer-key-$digit'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: SizedBox(
            width: 72,
            height: 72,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(digit, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w500)),
                if (letters.isNotEmpty)
                  Text(
                    letters,
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 9,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
