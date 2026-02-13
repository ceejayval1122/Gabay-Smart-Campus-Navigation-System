import 'dart:convert';

import 'package:Gabay/core/debug_logger.dart';
import 'package:Gabay/core/env.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin-only actions that require Supabase Edge Functions.
///
/// You must deploy the following Edge Functions in your Supabase project:
/// - admin_create_user
/// - admin_delete_user
/// - admin_send_reset (or similar)
///
/// These functions should use the Service Role key on the server side ONLY.
/// Never embed the service role in the mobile app.
class AdminRepository {
  AdminRepository._();
  static final AdminRepository instance = AdminRepository._();

  SupabaseClient get _client => Supabase.instance.client;

  String _projectRefFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      if (host.isEmpty) return '';
      return host.split('.').first;
    } catch (_) {
      return '';
    }
  }

  Map<String, dynamic>? _jwtPayload(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final v = jsonDecode(decoded);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  void _logInvokeContext(String functionName) {
    final url = Env.supabaseUrl;
    final urlRef = _projectRefFromUrl(url);
    final token = _client.auth.currentSession?.accessToken;
    final looksJwt = token != null && token.split('.').length == 3;
    final payload = token != null ? _jwtPayload(token) : null;
    final tokenRef = (payload?['ref'] ?? '').toString();

    logger.info(
      'Invoking Edge Function: $functionName',
      tag: 'AdminRepository',
    );
    logger.debug(
      'supabaseUrlRef=$urlRef tokenLooksJwt=$looksJwt tokenRef=$tokenRef tokenRefMatches=${tokenRef.isNotEmpty && urlRef.isNotEmpty && tokenRef == urlRef}',
      tag: 'AdminRepository',
    );
  }

  Future<void> _validateSessionToken() async {
    try {
      await _client.auth.getUser();
    } on AuthException catch (e) {
      throw Exception('Your session is invalid or expired. Please sign out and sign in again. (${e.message})');
    } catch (_) {
      // If this fails in a non-AuthException way, let the normal function call
      // error handling surface the underlying issue.
    }
  }

  Map<String, String> _authHeaders() {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Not authenticated. Please sign in again.');
    }
    final anonKey = Env.supabaseAnonKey;
    if (anonKey.isEmpty) {
      throw Exception('Supabase is not configured. Missing SUPABASE_ANON_KEY.');
    }

    return {
      'Authorization': 'Bearer $token',
      'apikey': anonKey,
    };
  }

  String _friendlyFunctionError(Object e, {required String functionName}) {
    if (e is FunctionException) {
      if (e.status == 404) {
        return 'Admin feature is not configured: Edge Function "$functionName" was not found. Deploy the required Supabase Edge Functions (admin_create_user, admin_delete_user, admin_send_reset).';
      }
      return 'Edge Function "$functionName" failed (${e.status}): ${e.details ?? e.reasonPhrase ?? e.toString()}';
    }
    return e.toString();
  }

  Future<void> createUser({
    required String email,
    required String password,
    required String name,
    bool isAdmin = false,
    String? course,
    String? department,
    String createdBy = 'admin',
  }) async {
    final payload = {
      'email': email,
      'password': password,
      'name': name,
      'is_admin': isAdmin,
      if (course != null) 'course': course,
      if (department != null) 'department': department,
      'created_by': createdBy,
    };

    try {
      _logInvokeContext('admin_create_user');
      await _validateSessionToken();
      final res = await _client.functions.invoke(
        'admin_create_user',
        body: payload,
        headers: _authHeaders(),
      );
      if (res.status >= 400) {
        throw Exception('admin_create_user failed (${res.status}): ${res.data}');
      }
    } catch (e) {
      throw Exception(_friendlyFunctionError(e, functionName: 'admin_create_user'));
    }
  }

  Future<void> deleteUser(String userId) async {
    try {
      _logInvokeContext('admin_delete_user');
      await _validateSessionToken();
      final res = await _client.functions.invoke(
        'admin_delete_user',
        body: {
          'user_id': userId,
        },
        headers: _authHeaders(),
      );
      if (res.status >= 400) {
        throw Exception('admin_delete_user failed (${res.status}): ${res.data}');
      }
    } catch (e) {
      throw Exception(_friendlyFunctionError(e, functionName: 'admin_delete_user'));
    }
  }

  Future<void> sendPasswordReset(String email) async {
    // Optionally forward a redirectTo URL if configured
    String? redirectTo;
    try {
      // Delay import to avoid tight coupling if Env isn't present in some contexts
      // ignore: avoid_dynamic_calls
      redirectTo = (await Future.value(() => null)) as String?; // placeholder to keep analyzer calm
    } catch (_) {}
    // We will import Env at the top instead to follow style
    // and set redirectTo below if available.
    redirectTo = Env.supabaseRedirectUrl.isNotEmpty ? Env.supabaseRedirectUrl : null;

    final body = <String, dynamic>{'email': email};
    if (redirectTo != null) body['redirectTo'] = redirectTo;

    try {
      _logInvokeContext('admin_send_reset');
      await _validateSessionToken();
      final res = await _client.functions.invoke(
        'admin_send_reset',
        body: body,
        headers: _authHeaders(),
      );
      if (res.status >= 400) {
        throw Exception('admin_send_reset failed (${res.status}): ${res.data}');
      }
    } catch (e) {
      throw Exception(_friendlyFunctionError(e, functionName: 'admin_send_reset'));
    }
  }
}
