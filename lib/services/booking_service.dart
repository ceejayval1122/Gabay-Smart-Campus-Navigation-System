import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/booking.dart';

class BookingService {
  BookingService._internal();
  static final BookingService instance = BookingService._internal();

  static const String _table = 'bookings';
  final _supabase = Supabase.instance.client;

  Stream<List<Booking>> streamAll() {
    return _supabase
        .from(_table)
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map((rows) => rows.map((r) => Booking.fromMap(Map<String, dynamic>.from(r))).toList());
  }

  Stream<List<Booking>> streamMine() {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      return Stream.value(const <Booking>[]);
    }
    return _supabase
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at')
        .map((rows) => rows.map((r) => Booking.fromMap(Map<String, dynamic>.from(r))).toList());
  }

  Future<Booking> create({
    required String facility,
    required DateTime date,
    required String startTime,
    required String endTime,
    required String purpose,
    int? attendees,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    final payload = <String, dynamic>{
      'id': id,
      'user_id': uid,
      'facility': facility,
      'date': DateTime(date.year, date.month, date.day).toIso8601String(),
      'start_time': startTime,
      'end_time': endTime,
      'purpose': purpose,
      'status': 'pending',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    if (attendees != null) {
      payload['attendees'] = attendees;
    }

    try {
      final res = await _supabase.from(_table).insert(payload).select().single();
      return Booking.fromMap(Map<String, dynamic>.from(res as Map));
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST204' && e.message.toLowerCase().contains("'bookings'")) {
        // Extract the column name from the error message and retry without it
        final msg = e.message.toLowerCase();
        final match = RegExp(r"column '([^']+)' of relation 'bookings' does not exist").firstMatch(msg);
        final badColumn = match?.group(1);
        if (badColumn != null && payload.containsKey(badColumn)) {
          final retryPayload = Map<String, dynamic>.from(payload);
          retryPayload.remove(badColumn);
          final res = await _supabase.from(_table).insert(retryPayload).select().single();
          return Booking.fromMap(Map<String, dynamic>.from(res as Map));
        }
      }
      // Debug: print full error and payload for manual inspection
      debugPrint('=== BookingService.create PGRST204 debug ===');
      debugPrint('Error: ${e.code} - ${e.message}');
      debugPrint('Payload keys: ${payload.keys.join(', ')}');
      rethrow;
    }
  }

  Future<void> updateStatus(String id, String status) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final normalizedStatus = status == 'declined' ? 'rejected' : status;
    await _supabase.from(_table).update({'status': normalizedStatus, 'updated_at': now}).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _supabase.from(_table).delete().eq('id', id);
  }
}
