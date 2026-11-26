import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state_views.dart';

/// Renders loading / error (with retry) / data for an [AsyncValue].
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.loading,
    this.compactError = false,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final Widget? loading;
  final bool compactError;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () => loading ?? const LoadingView(),
      error: (e, _) => ErrorState(error: e, onRetry: onRetry, compact: compactError),
    );
  }
}
