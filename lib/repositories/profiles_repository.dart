import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilesRepository {
  ProfilesRepository._();
  static final ProfilesRepository instance = ProfilesRepository._();

  final SupabaseClient _client = Supabase.instance.client;

  static const String table = 'profiles';

  String? _missingColumnFromMessage(String message) {
    final m = RegExp(r"Could not find the '([^']+)' column").firstMatch(message);
    return m?.group(1);
  }

  Future<Map<String, dynamic>?> getMyProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final res = await _client.from(table).select().eq('id', uid).maybeSingle();
    return res;
  }

  Future<Map<String, dynamic>?> getProfile(String userId) async {
    final res = await _client.from(table).select().eq('id', userId).maybeSingle();
    return res;
  }

  Future<void> upsertMyProfile({
    required String name,
    required String email,
    String? course,
    String? department,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('No authenticated user.');

    final payload = <String, dynamic>{
      'id': uid,
      'name': name,
      'email': email,
      if (course != null) 'course': course,
      if (department != null) 'department': department,
      'active': true,
      'last_sign_in_at': DateTime.now().toIso8601String(),
    };

    var attemptPayload = Map<String, dynamic>.from(payload);
    for (var i = 0; i < 6; i++) {
      try {
        await _client.from(table).upsert(attemptPayload);
        return;
      } catch (e) {
        if (e is PostgrestException && e.code == 'PGRST204') {
          final missing = _missingColumnFromMessage(e.message);
          if (missing != null && attemptPayload.containsKey(missing)) {
            attemptPayload.remove(missing);
            continue;
          }
        }
        rethrow;
      }
    }
  }

  Future<bool> isCurrentUserAdmin() async {
    final p = await getMyProfile();
    if (p == null) return false;
    return (p['is_admin'] == true);
  }

  Future<void> updateLastSignInNow() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _client.from(table).update({
        'last_sign_in_at': DateTime.now().toIso8601String(),
      }).eq('id', uid);
    } catch (e) {
      if (e is PostgrestException && e.code == 'PGRST204') {
        return;
      }
      rethrow;
    }
  }

  // Realtime stream of all profiles; requires RLS to allow select for admin (or all users if public)
  Stream<List<Map<String, dynamic>>> streamAll() {
    return _client.from(table).stream(primaryKey: ['id']).order('created_at');
  }

  // One-time fetch of all profiles
  Future<List<Map<String, dynamic>>> listAll() async {
    final res = await _client.from(table).select();
    return (res as List).cast<Map<String, dynamic>>();
  }

  // Admin: update profile fields
  Future<void> updateFields(
    String id, {
    String? name,
    String? course,
    String? department,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (course != null) data['course'] = course;
    if (department != null) data['department'] = department;
    if (data.isEmpty) return;
    var attemptData = Map<String, dynamic>.from(data);
    for (var i = 0; i < 6; i++) {
      try {
        await _client.from(table).update(attemptData).eq('id', id);
        return;
      } catch (e) {
        if (e is PostgrestException && e.code == 'PGRST204') {
          final missing = _missingColumnFromMessage(e.message);
          if (missing != null && attemptData.containsKey(missing)) {
            attemptData.remove(missing);
            if (attemptData.isEmpty) return;
            continue;
          }
        }
        rethrow;
      }
    }
  }

  // Admin: set active flag
  Future<void> setActive(String id, bool active) async {
    await _client.from(table).update({'active': active}).eq('id', id);
  }

  // Admin: delete profile row (does not delete auth user)
  Future<void> deleteProfile(String id) async {
    await _client.from(table).delete().eq('id', id);
  }
}
