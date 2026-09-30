import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/models.dart';

/// Thin data-access layer for `auth.users` + `profiles`.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  User? get currentUser => _auth.currentUser;
  Session? get currentSession => _auth.currentSession;
  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;

  Future<User> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final res = await _auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': fullName.trim()},
    );
    final user = res.user;
    if (user == null) {
      throw const AuthException('Sign up failed. Please try again.');
    }
    await AppLogger.event('REGISTER_SUCCESS', entityType: 'profile', entityId: user.id);
    return user;
  }

  Future<User> signIn({required String email, required String password}) async {
    try {
      final res = await _auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      await AppLogger.event('LOGIN_SUCCESS', entityType: 'profile',
          entityId: res.user?.id);
      return res.user!;
    } on AuthException catch (e) {
      await AppLogger.event('LOGIN_FAILED',
          data: {'reason': e.message.split('.').first});
      rethrow;
    }
  }

  Future<void> signOut() async {
    await AppLogger.event('LOGOUT');
    await _auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    await _auth.resetPasswordForEmail(email.trim());
    await AppLogger.event('PASSWORD_RESET_REQUESTED');
  }

  /// Current user's profile row (RLS: self only).
  Future<Profile?> fetchProfile(String userId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  Future<void> updateProfile({
    required String userId,
    required String fullName,
    String? phone,
  }) async {
    await _client
        .from('profiles')
        .update({'full_name': fullName.trim(), 'phone': phone?.trim()})
        .eq('id', userId);
    await AppLogger.event('PROFILE_UPDATED', entityType: 'profile', entityId: userId);
  }
}
