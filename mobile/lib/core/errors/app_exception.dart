import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Normalised application error. UI only ever shows [message].
class AppException implements Exception {
  const AppException(this.message, {this.kind = AppErrorKind.unknown, this.cause});

  final String message;
  final AppErrorKind kind;
  final Object? cause;

  @override
  String toString() => message;
}

enum AppErrorKind {
  network,
  unauthorized,
  forbidden,
  validation,
  notFound,
  conflict,
  unknown,
}

/// Maps low-level errors (Supabase, socket, timeout) to friendly messages.
/// Never exposes tokens, keys or raw SQL to the user.
class ErrorMapper {
  ErrorMapper._();

  static AppException map(Object error) {
    if (error is AppException) return error;

    if (error is TimeoutException) {
      return const AppException(
        'The request took too long. Please check your connection and try again.',
        kind: AppErrorKind.network,
      );
    }

    if (error is SocketException || error is HandshakeException) {
      return const AppException(
        'No internet connection. Please try again.',
        kind: AppErrorKind.network,
      );
    }

    if (error is AuthException) {
      final lower = error.message.toLowerCase();
      if (lower.contains('invalid login') || lower.contains('invalid credentials')) {
        return const AppException(
          'Incorrect email or password.',
          kind: AppErrorKind.unauthorized,
        );
      }
      if (lower.contains('already registered')) {
        return const AppException(
          'An account with this email already exists.',
          kind: AppErrorKind.conflict,
        );
      }
      if (lower.contains('email not confirmed')) {
        return const AppException(
          'Please confirm your email address before signing in.',
          kind: AppErrorKind.unauthorized,
        );
      }
      if (lower.contains('password should be at least')) {
        return const AppException(
          'Password must be at least 6 characters.',
          kind: AppErrorKind.validation,
        );
      }
      if (lower.contains('rate limit')) {
        return const AppException(
          'Too many attempts. Please wait a moment and try again.',
          kind: AppErrorKind.conflict,
        );
      }
      return AppException(error.message, kind: AppErrorKind.unknown);
    }

    if (error is PostgrestException) {
      switch (error.code) {
        case '42501':
          return AppException(
            error.message.isNotEmpty ? error.message : 'You are not allowed to do that.',
            kind: AppErrorKind.forbidden,
          );
        case 'P0002':
          return const AppException('Not found.', kind: AppErrorKind.notFound);
        case '22023':
        case '23514':
        case '23505':
          return AppException(error.message, kind: AppErrorKind.validation);
        case '401':
          return const AppException(
            'Your session has expired. Please sign in again.',
            kind: AppErrorKind.unauthorized,
          );
        default:
          // 23xxx = RLS denial, database errors are logged separately
          if (error.code != null && error.code!.startsWith('PGRST')) {
            return const AppException(
              'The server could not complete that action. Please try again.',
              kind: AppErrorKind.unknown,
            );
          }
          return AppException(
            error.message.isNotEmpty ? error.message : 'Something went wrong.',
            kind: AppErrorKind.unknown,
          );
      }
    }

    if (error is AppException) return error;

    return const AppException(
      'Something went wrong. Please try again.',
      kind: AppErrorKind.unknown,
    );
  }
}
