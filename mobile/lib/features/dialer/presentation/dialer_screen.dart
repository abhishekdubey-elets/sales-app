import 'dart:async';

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
      body: TabBarView(controller: _tabs, children: const [_KeypadTab(), _RecentsTab(), _FavouritesTab()]),
    );
  }
}

class _KeypadTab extends ConsumerStatefulWidget {
  const _KeypadTab();

  @override
  ConsumerState<_KeypadTab> createState() => _KeypadTabState();
}

class _KeypadTabState extends ConsumerState<_KeypadTab> with AutomaticKeepAliveClientMixin {
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
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final searchActive = _search.text.trim().length >= 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    children: [
                      TextField(
                        controller: _search,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'Search leads by name or company',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searching
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : (_search.text.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          _search.clear();
                                          _onSearchChanged('');
                                        },
                                      )),
                        ),
                      ),
                      if (searchActive)
                        Card(
                          margin: const EdgeInsets.only(top: 8),
                          child: _results.isEmpty && !_searching
                              ? const Padding(padding: EdgeInsets.all(16), child: Text('No matching leads'))
                              : Column(
                                  children: [
                                    for (final lead in _results)
                                      ListTile(
                                        leading: AppAvatar(name: lead.fullName, radius: 18),
                                        title: Text(lead.fullName),
                                        subtitle: Text(
                                          [
                                            lead.companyName ?? '',
                                            lead.displayPhone,
                                          ].where((s) => s.isNotEmpty).join(' · '),
                                        ),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.call, color: AppColors.success),
                                          onPressed: lead.optedOut
                                              ? null
                                              : () => launchCall(
                                                  context,
                                                  ref,
                                                  leadId: lead.id,
                                                  displayName: lead.fullName,
                                                ),
                                        ),
                                        onTap: () => context.go('/leads/${lead.id}'),
                                      ),
                                  ],
                                ),
                        ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const ValueKey('dialer-number'),
                        controller: _number,
                        onChanged: (_) => _onNumberChanged(),
                        keyboardType: TextInputType.phone,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 1.5),
                        decoration: const InputDecoration(
                          hintText: 'Enter number',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                        ),
                      ),
                      SizedBox(
                        height: 28,
                        child: _lookingUp
                            ? const Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : _matched != null
                            ? InkWell(
                                onTap: () => context.go('/leads/${_matched!.id}'),
                                child: Text(
                                  '${_matched!.fullName}${_matched!.companyName != null ? ' · ${_matched!.companyName}' : ''}',
                                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
                                ),
                              )
                            : (_digits.length >= 10
                                  ? Text(
                                      'Not in your leads',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    )
                                  : null),
                      ),
                      const SizedBox(height: 8),
                      DialerKeypad(onKey: _press, onBackspace: _backspace, onClear: _clear),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 72,
                        height: 72,
                        child: FloatingActionButton(
                          heroTag: 'dial',
                          tooltip: 'Call',
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          shape: const CircleBorder(),
                          onPressed: _digits.isEmpty && _matched == null ? null : _call,
                          child: const Icon(Icons.call, size: 32),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
