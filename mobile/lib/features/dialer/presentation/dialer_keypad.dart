import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 0–9, *, # keypad laid out like a phone dialer. The bottom row holds the [callButton] in the
/// middle and backspace on the right (long-press backspace clears the number).
///
/// [keySize] lets the screen shrink the keys so the whole dialer, call button included, fits
/// without scrolling on small phones.
class DialerKeypad extends StatelessWidget {
  const DialerKeypad({
    super.key,
    required this.onKey,
    required this.onBackspace,
    required this.onClear,
    this.callButton,
    this.keySize = 72,
    this.rowGap = 10,
  });

  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final Widget? callButton;
  final double keySize;

  /// Vertical space between rows.
  final double rowGap;

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

  /// Height the keypad needs: 5 rows of [keySize] plus [rowGap] each.
  static double heightFor(double keySize, double rowGap) => 5 * (keySize + rowGap);

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
                  size: keySize,
                  gap: rowGap,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onKey(keys[row * 3 + col].$1);
                  },
                  // Long-press 0 types "+" for international numbers.
                  onLongPress: keys[row * 3 + col].$1 == '0' ? () => onKey('+') : null,
                ),
            ],
          ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: rowGap / 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SizedBox(width: keySize, height: keySize),
              SizedBox(width: keySize, height: keySize, child: callButton),
              // InkWell instead of IconButton: an IconButton tooltip would swallow the long-press.
              Semantics(
                button: true,
                label: 'Delete digit. Long-press to clear the number',
                child: InkWell(
                  key: const ValueKey('dialer-backspace'),
                  customBorder: const CircleBorder(),
                  onTap: onBackspace,
                  onLongPress: onClear,
                  child: SizedBox(width: keySize, height: keySize, child: const Icon(Icons.backspace_outlined)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.digit,
    required this.letters,
    required this.size,
    required this.gap,
    required this.onTap,
    this.onLongPress,
  });

  final String digit;
  final String letters;
  final double size;
  final double gap;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = size < 60;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: gap / 2),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        shape: const CircleBorder(),
        child: InkWell(
          key: ValueKey('dialer-key-$digit'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: SizedBox(
            width: size,
            height: size,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  digit,
                  style: (compact ? theme.textTheme.titleLarge : theme.textTheme.headlineSmall)?.copyWith(
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
                ),
                if (letters.isNotEmpty && !compact)
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
