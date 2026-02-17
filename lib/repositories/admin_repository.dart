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

  String _stringifyDetails(dynamic details) {
    if (details == null) return '';
    if (details is String) return details;
    try {
      return jsonEncode(details);
    } catch (_) {
      return details.toString();
    }
  }

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

  String _projectRefFromJwt(String token) {
    final payload = _jwtPayload(token);
    final iss = (payload?['iss'] ?? '').toString();
    if (iss.isNotEmpty) {
      final fromIss = _projectRefFromUrl(iss);
      if (fromIss.isNotEmpty) return fromIss;
    }
    // Some tokens (e.g. anon key) include a direct "ref" claim.
    final ref = (payload?['ref'] ?? '').toString();
    return ref;
  }

  void _logInvokeContext(String functionName) {
    final url = Env.supabaseUrl;
    final urlRef = _projectRefFromUrl(url);
    final token = _client.auth.currentSession?.accessToken;
    final looksJwt = token != null && token.split('.').length == 3;
    final tokenRef = token != null ? _projectRefFromJwt(token) : '';

    logger.info(
      'Invoking Edge Function: $functionName',
      tag: 'AdminRepository',
    );
    logger.debug(
      'supabaseUrlRef=$urlRef tokenLooksJwt=$looksJwt tokenRef=$tokenRef tokenRefMatches=${tokenRef.isNotEmpty && urlRef.isNotEmpty && tokenRef == urlRef}',
      tag: 'AdminRepository',
    );
  }

  void _ensureTokenMatchesProject() {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) return;
    final parts = token.split('.');
    if (parts.length != 3) {
      throw Exception('Not authenticated (invalid session token). Please sign out and sign in again.');
    }

    final urlRef = _projectRefFromUrl(Env.supabaseUrl);
    final tokenRef = _projectRefFromJwt(token);
    if (urlRef.isNotEmpty && tokenRef.isNotEmpty && urlRef != tokenRef) {
      throw Exception(
        'Supabase project mismatch. Your app is configured for "$urlRef" but your login session belongs to "$tokenRef". '
        'This usually happens after changing SUPABASE_URL / SUPABASE_ANON_KEY. Please sign out and sign in again (or reinstall the app).',
      );
    }
  }

  Future<void> _validateSessionToken() async {
    try {
      _ensureTokenMatchesProject();
      try {
        await _client.auth.refreshSession();
      } catch (_) {
        // If refresh fails (offline, no refresh token, etc), continue and let getUser() decide.
      }
      await _client.auth.getUser();
    } on AuthException catch (e) {
      throw Exception('Your session is invalid or expired. Please sign out and sign in again. (${e.message})');
    } catch (_) {
      // If this fails in a non-AuthException way, let the normal function call
      // error handling surface the underlying issue.
    }
  }

  Map<String, String> _authHeaders() {
    _ensureTokenMatchesProject();
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
      final detailsStr = _stringifyDetails(e.details);
      final reason = detailsStr.isNotEmpty ? detailsStr : (e.reasonPhrase ?? e.toString());
      if (e.status == 401 && reason.toLowerCase().contains('invalid jwt')) {
        final urlRef = _projectRefFromUrl(Env.supabaseUrl);
        final token = _client.auth.currentSession?.accessToken;
        final tokenRef = token != null ? _projectRefFromJwt(token) : '';
        final diag = 'appProject=$urlRef sessionProject=${tokenRef.isEmpty ? 'unknown' : tokenRef}';
        return 'Authentication failed (invalid JWT). ($diag) Please sign out and sign in again. If appProject and sessionProject differ, your app is pointed to a different Supabase project than your session.';
      }
      return 'Edge Function "$functionName" failed (${e.status}): $reason';
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
      );
      if (res.status >= 400) {
        throw Exception('admin_send_reset failed (${res.status}): ${res.data}');
      }
    } catch (e) {
      throw Exception(_friendlyFunctionError(e, functionName: 'admin_send_reset'));
    }
  }
}
