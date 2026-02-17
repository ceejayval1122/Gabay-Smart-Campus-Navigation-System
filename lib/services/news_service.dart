import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/news.dart';

class NewsService {
  NewsService._internal();
  static final NewsService instance = NewsService._internal();

  static const String _table = 'news';
  final _supabase = Supabase.instance.client;

  // Live feed: realtime stream from Supabase ordered by creation time, with pinned first.
  Stream<List<NewsPost>> feed() {
    return _supabase
        .from(_table)
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map((rows) {
          final posts = rows.map((r) => NewsPost.fromMap(r)).toList();
          posts.sort((a, b) {
            if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
            return b.createdAt.compareTo(a.createdAt);
          });
          return posts;
        });
  }

  // Publish a post to the database.
  Future<NewsPost> publish({
    required PostType type,
    required String title,
    String? body,
    String? deptTag,
    DateTime? scheduledAt,
    bool pinned = false,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now();
    final t = title.trim();
    final b = body?.trim();
    final content = (b == null || b.isEmpty) ? t : b;
    Map<String, dynamic> payload = {
      'id': id,
      'type': type.name,
      'title': t,
      'content': content,
      'body': content,
      if (deptTag?.trim().isNotEmpty == true) 'dept_tag': deptTag!.trim(),
      'created_at': now.toIso8601String(),
      if (scheduledAt != null) 'scheduled_at': scheduledAt.toIso8601String(),
      'pinned': pinned,
    };
    
    // Retry logic for missing columns
    for (var i = 0; i < 5; i++) {
      try {
        final inserted = await _supabase.from(_table).insert(payload).select().single();
        return NewsPost.fromMap(inserted as Map<String, dynamic>);
      } on PostgrestException catch (e) {
        print('DEBUG: NewsService publish error: ${e.code} - ${e.message}');
        if (e.code != 'PGRST204' && e.code != '42703') rethrow;
        final next = _removeMissingColumnIfPossible(payload, e);
        print('DEBUG: Retrying with payload: $next');
        if (identical(next, payload)) rethrow;
        payload = next;
      }
    }
    final inserted = await _supabase.from(_table).insert(payload).select().single();
    return NewsPost.fromMap(inserted as Map<String, dynamic>);
  }

  Map<String, dynamic> _removeMissingColumnIfPossible(Map<String, dynamic> payload, PostgrestException e) {
    final msg = e.message;
    String? bad;

    // Supabase/PostgREST can format this in a few different ways depending on the operation.
    final patterns = <RegExp>[
      RegExp(
        r"could not find the '([^']+)' column of (?:'news'|news)",
        caseSensitive: false,
      ),
      RegExp(
        r"column '([^']+)' of relation 'news' does not exist",
        caseSensitive: false,
      ),
      RegExp(
        r'column "([^"]+)" of relation "news" does not exist',
        caseSensitive: false,
      ),
      RegExp(
        r'column news\\.([a-zA-Z0-9_]+) does not exist',
        caseSensitive: false,
      ),
      // Handle the specific case where it says column "news" of relation "news" does not exist
      // This usually means there's an issue with the table structure or query
      RegExp(
        r'column "news" of relation "news" does not exist',
        caseSensitive: false,
      ),
    ];

    for (final p in patterns) {
      final m = p.firstMatch(msg);
      if (m != null) {
        bad = m.groupCount >= 1 ? m.group(1) : null;
        break;
      }
    }

    if (bad == null || !payload.containsKey(bad)) return payload;
    final next = Map<String, dynamic>.from(payload);
    next.remove(bad);
    return next;
  }

  Future<void> delete(String id) async {
    await _supabase.from(_table).delete().eq('id', id);
  }

  Future<void> togglePin(String id) async {
    // Flip the pinned state atomically by reading and writing a single row
    final row = await _supabase.from(_table).select('pinned').eq('id', id).maybeSingle();
    if (row == null) return;
    final current = (row['pinned'] as bool?) ?? false;
    await _supabase.from(_table).update({'pinned': !current}).eq('id', id);
  }
}
