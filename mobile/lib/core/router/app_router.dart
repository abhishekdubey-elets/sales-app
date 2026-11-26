import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/ai_agents/presentation/agent_editor_screen.dart';
import '../../features/ai_agents/presentation/agent_test_screen.dart';
import '../../features/ai_agents/presentation/ai_call_detail_screen.dart';
import '../../features/ai_agents/presentation/ai_home_screen.dart';
import '../../features/analytics/presentation/analytics_screen.dart';
import '../../features/analytics/presentation/my_performance_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/calls/data/call_models.dart';
import '../../features/calls/presentation/call_history_screen.dart';
import '../../features/campaigns/presentation/campaign_detail_screen.dart';
import '../../features/campaigns/presentation/campaign_wizard_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/dialer/presentation/active_call_screen.dart';
import '../../features/dialer/presentation/dialer_screen.dart';
import '../../features/followups/presentation/followups_screen.dart';
import '../../features/leads/presentation/lead_detail_screen.dart';
import '../../features/leads/presentation/lead_form_screen.dart';
import '../../features/leads/presentation/lead_import_screen.dart';
import '../../features/leads/presentation/leads_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/profile/presentation/change_password_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/sessions_screen.dart';
import '../../features/settings/presentation/audit_log_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/team/presentation/team_screen.dart';
import '../../features/team/presentation/user_form_screen.dart';
import '../models/enums.dart';
import 'app_shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Paths only admins may open.
const _adminOnly = ['/settings', '/audit-logs', '/team/users', '/ai/agents/new', '/ai/campaigns/new'];

/// Paths for managers and admins (executives are redirected to the dashboard).
const _managerPlus = ['/analytics', '/team', '/ai/agents', '/ai/calls', '/ai/campaigns'];

String? roleRedirect(UserRole role, String location) {
  bool matches(String prefix) => location == prefix || location.startsWith('$prefix/');
  if (role != UserRole.admin && _adminOnly.any(matches)) return '/dashboard';
  if (role == UserRole.executive && _managerPlus.any(matches)) return '/dashboard';
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen<AuthState>(authControllerProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/dashboard',
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      if (auth.status == AuthStatus.unknown) return loc == '/splash' ? null : '/splash';
      if (!auth.isAuthenticated) return loc == '/login' ? null : '/login';
      if (loc == '/login' || loc == '/splash') return '/dashboard';
      return roleRedirect(auth.user!.role, loc);
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/leads',
                builder: (_, _) => const LeadsScreen(),
                routes: [
                  GoRoute(path: 'new', builder: (_, _) => const LeadFormScreen()),
                  GoRoute(path: 'import', builder: (_, _) => const LeadImportScreen()),
                  GoRoute(
                    path: ':id',
                    builder: (_, s) => LeadDetailScreen(leadId: s.pathParameters['id']!),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        builder: (_, s) => LeadFormScreen(leadId: s.pathParameters['id']),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/dialer', builder: (_, _) => const DialerScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ai',
                builder: (_, s) => AiHomeScreen(initialTab: s.uri.queryParameters['tab']),
                routes: [
                  GoRoute(path: 'agents/new', builder: (_, _) => const AgentEditorScreen()),
                  GoRoute(
                    path: 'agents/:id',
                    builder: (_, s) => AgentEditorScreen(agentId: s.pathParameters['id']),
                    routes: [
                      GoRoute(
                        path: 'test',
                        builder: (_, s) => AgentTestScreen(agentId: s.pathParameters['id']!),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'calls/:id',
                    builder: (_, s) => AiCallDetailScreen(callId: s.pathParameters['id']!),
                  ),
                  GoRoute(path: 'campaigns/new', builder: (_, _) => const CampaignWizardScreen()),
                  GoRoute(
                    path: 'campaigns/:id',
                    builder: (_, s) => CampaignDetailScreen(campaignId: s.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const ProfileScreen(),
                routes: [
                  GoRoute(path: 'sessions', builder: (_, _) => const SessionsScreen()),
                  GoRoute(path: 'password', builder: (_, _) => const ChangePasswordScreen()),
                ],
              ),
            ],
          ),
        ],
      ),
      // Full-screen routes above the bottom navigation.
      GoRoute(
        path: '/call/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, s) => ActiveCallScreen(
          callId: s.pathParameters['id']!,
          initial: s.extra is HumanCall ? s.extra as HumanCall : null,
        ),
      ),
      GoRoute(path: '/calls', parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const CallHistoryScreen()),
      GoRoute(path: '/followups', parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const FollowupsScreen()),
      GoRoute(
        path: '/notifications',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/performance',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const MyPerformanceScreen(),
      ),
      GoRoute(path: '/analytics', parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const AnalyticsScreen()),
      GoRoute(
        path: '/team',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const TeamScreen(),
        routes: [
          GoRoute(path: 'users/new', builder: (_, _) => const UserFormScreen()),
          GoRoute(
            path: 'users/:id',
            builder: (_, s) => UserFormScreen(userId: s.pathParameters['id']),
          ),
        ],
      ),
      GoRoute(path: '/settings', parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/audit-logs', parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const AuditLogScreen()),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
