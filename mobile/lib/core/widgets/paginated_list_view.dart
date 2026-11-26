import 'package:flutter/material.dart';

import '../models/page_result.dart';
import 'state_views.dart';

typedef PageFetcher<T> = Future<PageResult<T>> Function(int page);

/// Lets a parent refresh a [PaginatedListView] (e.g. after creating an item).
class PaginatedListController extends ChangeNotifier {
  void refresh() => notifyListeners();
}

/// Infinite-scroll list with pull-to-refresh and loading/empty/error states.
///
/// Changing [resetKey] (e.g. when filters change) reloads from page 1.
class PaginatedListView<T> extends StatefulWidget {
  const PaginatedListView({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    this.resetKey,
    this.controller,
    this.empty,
    this.separator = true,
    this.padding = const EdgeInsets.only(bottom: 96),
    this.header,
  });

  final PageFetcher<T> fetch;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Object? resetKey;
  final PaginatedListController? controller;
  final Widget? empty;
  final bool separator;
  final EdgeInsets padding;
  final Widget? header;

  @override
  State<PaginatedListView<T>> createState() => PaginatedListViewState<T>();
}

class PaginatedListViewState<T> extends State<PaginatedListView<T>> {
  final _items = <T>[];
  final _scroll = ScrollController();
  int _page = 0;
  bool _hasMore = true;
  bool _loading = true;
  Object? _error;
  int _generation = 0;

  List<T> get items => List.unmodifiable(_items);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    widget.controller?.addListener(refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(reset: true);
    });
  }

  @override
  void didUpdateWidget(covariant PaginatedListView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(refresh);
      widget.controller?.addListener(refresh);
    }
    if (oldWidget.resetKey != widget.resetKey) _load(reset: true);
  }

  @override
  void dispose() {
    widget.controller?.removeListener(refresh);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> refresh() => _load(reset: true);

  void _onScroll() {
    if (!_scroll.hasClients || _loading || !_hasMore || _error != null) return;
    if (_scroll.position.extentAfter < 400) _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    final generation = reset ? ++_generation : _generation;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _page = 0;
        _hasMore = true;
      }
    });
    try {
      final result = await widget.fetch(_page + 1);
      if (!mounted || generation != _generation) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(result.items);
        _page = result.page;
        _hasMore = result.hasMore && result.items.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      Widget body;
      if (_loading) {
        body = const SkeletonList();
      } else if (_error != null) {
        body = ErrorState(error: _error!, onRetry: refresh);
      } else {
        body = widget.empty ?? const EmptyState(title: 'Nothing here yet');
      }
      return RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: widget.padding,
          children: [
            if (widget.header != null) widget.header!,
            SizedBox(height: 360, child: body),
          ],
        ),
      );
    }

    final headerCount = widget.header != null ? 1 : 0;
    final footer = _hasMore || _error != null ? 1 : 0;
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.padding,
        itemCount: headerCount + _items.length + footer,
        separatorBuilder: (_, i) =>
            widget.separator && i >= headerCount ? const Divider(indent: 72, height: 1) : const SizedBox.shrink(),
        itemBuilder: (context, i) {
          if (headerCount == 1 && i == 0) return widget.header!;
          final index = i - headerCount;
          if (index < _items.length) return widget.itemBuilder(context, _items[index], index);
          if (_error != null) {
            return ErrorState(error: _error!, onRetry: _load, compact: true);
          }
          // Footer spinner also triggers loading when the list is shorter than the screen.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_loading && _hasMore) _load();
          });
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        },
      ),
    );
  }
}
