import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository._();
  static final AuthRepository instance = AuthRepository._();

  final SupabaseClient _client = Supabase.instance.client;

  String _formatAuthError(Object e) {
    if (e is AuthException) {
      if (e.message.contains('invalid email')) {
        return 'Invalid email address';
      } else if (e.message.contains('password should be at least')) {
        return 'Password should be at least 8 characters long';
      } else {
        return e.message;
      }
    } else {
      return e.toString();
    }
  }

  Future<AuthResponse> signUp({required String email, required String password}) async {
    try {
      return await _client.auth.signUp(email: email, password: password);
    } catch (e) {
      throw Exception(_formatAuthError(e));
    }
  }

  Future<AuthResponse> signIn({required String email, required String password}) async {
    try {
      return await _client.auth.signInWithPassword(email: email, password: password);
    } catch (e) {
      throw Exception(_formatAuthError(e));
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  User? get currentUser => _client.auth.currentUser;
}
