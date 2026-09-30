import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'domain/enums.dart';
import 'presentation/navigation/navigation.dart';
import 'state/providers.dart';
import 'presentation/screens/create_request_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/profile_screen.dart';
import 'presentation/screens/register_screen.dart';
import 'presentation/screens/request_details_screen.dart';
import 'presentation/screens/requests_screen.dart';
import 'presentation/screens/services_screen.dart';
import 'presentation/screens/shell.dart';
import 'presentation/screens/splash_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authRepositoryProvider);

  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/splash',
    redirect: (context, state) {
      final loggedIn = auth.currentSession != null;
      final location = state.matchedLocation;
      final isPublic = location == '/splash' ||
          location == '/login' ||
          location == '/register';

      if (!loggedIn && !isPublic) return '/login';
      if (loggedIn && (location == '/login' || location == '/register')) {
        return '/home';
      }
      if (loggedIn && location == '/splash') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
          GoRoute(path: '/services', builder: (_, _) => const ServicesScreen()),
          GoRoute(path: '/requests', builder: (_, _) => const RequestsScreen()),
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        ],
      ),
      GoRoute(
        path: '/requests/new',
        builder: (_, state) => CreateRequestScreen(
          initialServiceId: state.uri.queryParameters['service'],
        ),
      ),
      GoRoute(
        path: '/requests/:id',
        builder: (_, state) =>
            RequestDetailsScreen(requestId: state.pathParameters['id']!),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.uri}')),
    ),
  );
});

/// Whether the signed-in role should see "create request" affordances.
bool canCreateRequest(UserRole role) =>
    role == UserRole.customer || role == UserRole.admin;
