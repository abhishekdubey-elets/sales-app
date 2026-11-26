import 'package:flutter/material.dart';

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(cancelLabel)),
          FilledButton(
            style: destructive ? FilledButton.styleFrom(backgroundColor: scheme.error) : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Single text input dialog; returns null when cancelled.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String? label,
  String? initialValue,
  String confirmLabel = 'Save',
  int maxLines = 1,
  TextInputType? keyboardType,
  String? Function(String?)? validator,
}) {
  final controller = TextEditingController(text: initialValue);
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(labelText: label),
          validator: validator,
          onFieldSubmitted: maxLines == 1
              ? (_) {
                  if (formKey.currentState?.validate() ?? true) Navigator.of(context).pop(controller.text.trim());
                }
              : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() ?? true) Navigator.of(context).pop(controller.text.trim());
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
