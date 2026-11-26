import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/status_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/paginated_list_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_chip.dart';
import '../../calls/data/call_models.dart';
import '../../calls/data/calls_repository.dart';
import '../../leads/data/lead_models.dart';
import '../../leads/data/leads_repository.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../call_launcher.dart';
import 'dialer_keypad.dart';

class DialerScreen extends ConsumerStatefulWidget {
  const DialerScreen({super.key});

  @override
  ConsumerState<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends ConsumerState<DialerScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dialer'),
        actions: [
          IconButton(tooltip: 'Call history', onPressed: () => context.push('/calls'), icon: const Icon(Icons.history)),
          const NotificationBell(),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Keypad'),
            Tab(text: 'Recents'),
            Tab(text: 'Favourites'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: const [KeypadTab(), _RecentsTab(), _FavouritesTab()]),
    );
  }
}

/// Keypad tab of the dialer: lead search, number, keypad and call button, sized to fit the screen.
class KeypadTab extends ConsumerStatefulWidget {
  const KeypadTab({super.key});

  @override
  ConsumerState<KeypadTab> createState() => _KeypadTabState();
}

class _KeypadTabState extends ConsumerState<KeypadTab> with AutomaticKeepAliveClientMixin {
  final _number = TextEditingController();
  final _search = TextEditingController();
  Timer? _lookupTimer;
  Timer? _searchTimer;
  Lead? _matched;
  bool _lookingUp = false;
  List<Lead> _results = const [];
  bool _searching = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _lookupTimer?.cancel();
    _searchTimer?.cancel();
    _number.dispose();
    _search.dispose();
    super.dispose();
  }

  String get _digits => _number.text.replaceAll(RegExp(r'[^0-9+*#]'), '');

  void _onNumberChanged() {
    setState(() => _matched = null);
    _lookupTimer?.cancel();
    final digits = _digits.replaceAll(RegExp(r'[*#]'), '');
    if (digits.replaceAll('+', '').length < 10) return;
    _lookupTimer = Timer(const Duration(milliseconds: 400), () => _lookup(digits));
  }

  Future<void> _lookup(String phone) async {
    setState(() => _lookingUp = true);
    try {
      final lead = await ref.read(leadsRepositoryProvider).lookup(phone);
      if (mounted && _digits.contains(phone.replaceAll('+', ''))) setState(() => _matched = lead);
    } catch (_) {
      // Lookup is a convenience; dialing still works without a match.
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  void _onSearchChanged(String v) {
    _searchTimer?.cancel();
    final q = v.trim();
    if (q.length < 2) {
      setState(() => _results = const []);
      return;
    }
    _searchTimer = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      try {
        final page = await ref.read(leadsRepositoryProvider).list(LeadQuery(q: q), pageSize: 8);
        if (mounted && _search.text.trim() == q) setState(() => _results = page.items);
      } catch (_) {
        if (mounted) setState(() => _results = const []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  void _press(String key) {
    _number.text += key;
    _onNumberChanged();
  }

  void _backspace() {
    if (_number.text.isEmpty) return;
    _number.text = _number.text.substring(0, _number.text.length - 1);
    _onNumberChanged();
  }

  void _clear() {
    _number.clear();
    _onNumberChanged();
  }

  void _call() {
    final matched = _matched;
    if (matched != null) {
      launchCall(context, ref, leadId: matched.id, displayName: matched.fullName);
    } else if (_digits.isNotEmpty) {
      launchCall(context, ref, phoneNumber: _digits, displayName: _digits);
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Enter a number, or search for a lead to call.')));
    }
  }

  void _clearSearch() {
    _search.clear();
    _onSearchChanged('');
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final searchActive = _search.text.trim().length >= 2;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _search,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search leads by name or company',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : (_search.text.isEmpty
                            ? null
                            : IconButton(tooltip: 'Clear search', icon: const Icon(Icons.clear), onPressed: _clearSearch)),
                ),
              ),
            ),
            Expanded(
              // While searching, results take the keypad's place (the system keyboard is up anyway).
              child: searchActive ? _searchResults() : _dialPad(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchResults() {
    if (_results.isEmpty) {
      return _searching
          ? const Center(child: CircularProgressIndicator())
          : const EmptyState(icon: Icons.person_search_outlined, title: 'No matching leads');
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(indent: 72, height: 1),
      itemBuilder: (context, i) {
        final lead = _results[i];
        return ListTile(
          leading: AppAvatar(name: lead.fullName, radius: 18),
          title: Text(lead.fullName),
          subtitle: Text([lead.companyName ?? '', lead.displayPhone].where((s) => s.isNotEmpty).join(' · ')),
          trailing: IconButton.filled(
            tooltip: 'Call ${lead.fullName}',
            style: IconButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
            icon: const Icon(Icons.call),
            onPressed: lead.optedOut
                ? null
                : () => launchCall(context, ref, leadId: lead.id, displayName: lead.fullName),
          ),
          onTap: () => context.go('/leads/${lead.id}'),
        );
      },
    );
  }

  Widget _dialPad(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Size the keys from the space actually available so the number, keypad and call button all fit
        // on screen without scrolling. Only very short screens (landscape, huge system font) scroll.
        final short = constraints.maxHeight < 420;
        final numberH = short ? 44.0 : 56.0;
        final statusH = short ? 20.0 : 24.0;
        const verticalPadding = 8.0;
        final rowH = (constraints.maxHeight - numberH - statusH - verticalPadding) / 5;
        final rowGap = (rowH * 0.14).clamp(4.0, 10.0).toDouble();
        final byWidth = (constraints.maxWidth - 32) / 3 - 16;
        final keySize = math.min(rowH - rowGap, byWidth).clamp(40.0, 76.0).toDouble();
        final hasNumber = _digits.isNotEmpty || _matched != null;
        final callButton = FloatingActionButton(
          heroTag: 'dial',
          tooltip: 'Call',
          backgroundColor: AppColors.success,
          foregroundColor: Colors.white,
          elevation: hasNumber ? 3 : 0,
          shape: const CircleBorder(),
          onPressed: _call,
          child: Icon(Icons.call, size: keySize * 0.42),
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: ConstrainedBox(
            // Centre vertically when the keys hit their maximum size on tall screens.
            constraints: BoxConstraints(minHeight: math.max(0.0, constraints.maxHeight - verticalPadding)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
              SizedBox(
                height: numberH,
                child: TextField(
                  key: const ValueKey('dialer-number'),
                  controller: _number,
                  onChanged: (_) => _onNumberChanged(),
                  // The on-screen keypad is the input: don't let Android's keyboard cover it.
                  // Long-press still offers paste.
                  keyboardType: TextInputType.none,
                  showCursor: true,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 1.5),
                  decoration: const InputDecoration(
                    hintText: 'Enter number',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
              ),
              SizedBox(
                height: statusH,
                child: _lookingUp
                    ? const Center(
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : _matched != null
                    ? InkWell(
                        onTap: () => context.go('/leads/${_matched!.id}'),
                        child: Text(
                          '${_matched!.fullName}${_matched!.companyName != null ? ' · ${_matched!.companyName}' : ''}',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
                        ),
                      )
                    : (_digits.length >= 10
                          ? Text(
                              'Not in your leads',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            )
                          : null),
              ),
              DialerKeypad(
                onKey: _press,
                onBackspace: _backspace,
                onClear: _clear,
                keySize: keySize,
                rowGap: rowGap,
                callButton: callButton,
              ),
            ],
            ),
          ),
        );
      },
    );
  }
}

class _RecentsTab extends ConsumerWidget {
  const _RecentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentCallsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(recentCallsProvider),
      child: AsyncValueView<List<HumanCall>>(
        value: recents,
        onRetry: () => ref.invalidate(recentCallsProvider),
        loading: const SkeletonList(),
        data: (calls) {
          if (calls.isEmpty) {
            return ListView(
              children: const [
                SizedBox(
                  height: 360,
                  child: EmptyState(title: 'No recent calls', icon: Icons.history),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: calls.length,
            separatorBuilder: (_, _) => const Divider(indent: 72),
            itemBuilder: (context, i) => CallTile(
              call: calls[i],
              onCallAgain: () => calls[i].leadId != null
                  ? launchCall(context, ref, leadId: calls[i].leadId, displayName: calls[i].displayName)
                  : launchCall(context, ref, phoneNumber: calls[i].phoneNumber, displayName: calls[i].displayName),
            ),
          );
        },
      ),
    );
  }
}

class _FavouritesTab extends ConsumerWidget {
  const _FavouritesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PaginatedListView<Lead>(
      fetch: (page) => ref.read(leadsRepositoryProvider).list(const LeadQuery(favourites: true), page: page),
      empty: const EmptyState(
        icon: Icons.star_border,
        title: 'No favourites yet',
        message: 'Tap the star on a lead to add it here for one-tap calling.',
      ),
      itemBuilder: (context, lead, _) => ListTile(
        leading: AppAvatar(name: lead.fullName),
        title: Text(lead.fullName),
        subtitle: Text([lead.companyName ?? '', lead.displayPhone].where((s) => s.isNotEmpty).join(' · ')),
        trailing: IconButton.filledTonal(
          onPressed: lead.optedOut ? null : () => launchCall(context, ref, leadId: lead.id, displayName: lead.fullName),
          icon: const Icon(Icons.call),
        ),
        onTap: () => context.go('/leads/${lead.id}'),
      ),
    );
  }
}

/// One row of call history (used by Recents and the Call history screen).
class CallTile extends StatelessWidget {
  const CallTile({super.key, required this.call, this.onCallAgain, this.onTap, this.showSalesperson = false});

  final HumanCall call;
  final VoidCallback? onCallAgain;
  final VoidCallback? onTap;
  final bool showSalesperson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = callStatusColor(call.status);
    final icon = call.direction == CallDirection.inbound
        ? (call.status == CallStatus.notAnswered ? Icons.call_missed : Icons.call_received)
        : Icons.call_made;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        foregroundColor: color,
        child: Icon(icon, size: 20),
      ),
      title: Text(call.displayName, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          formatRelative(call.startedAt ?? call.createdAt),
          if (call.talkSeconds > 0) formatDuration(call.talkSeconds),
          if (call.outcome != null) call.outcome!.label,
          if (showSalesperson && call.salespersonName != null) call.salespersonName!,
        ].join(' · '),
        style: theme.textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusChip.callStatus(call.status, dense: true),
          if (onCallAgain != null)
            IconButton(tooltip: 'Call again', onPressed: onCallAgain, icon: const Icon(Icons.call_outlined)),
        ],
      ),
    );
  }
}
