import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/department_hours.dart';

class DepartmentHoursService {
  DepartmentHoursService._internal();

  static final DepartmentHoursService instance = DepartmentHoursService._internal();

  static const String _table = 'department_hours';
  final _supabase = Supabase.instance.client;

  bool _isDayOfWeekNotNull(PostgrestException e) {
    final msg = e.message.toLowerCase();
    // Catch any PostgrestException that mentions day_of_week constraint violation
    final result = msg.contains('day_of_week') && 
           (msg.contains('null value') || msg.contains('not-null constraint') || 
            msg.contains('constraint') || e.code == '23502' || e.code == '23514');
    print('DEBUG: _isDayOfWeekNotNull check: code=${e.code}, msg="$msg", result=$result');
    return result;
  }

  int? _parseDayIndex(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  String? _pickString(Map<String, dynamic> row, List<String> keys) {
    for (final k in keys) {
      final v = row[k];
      if (v == null) continue;
      final s = v.toString();
      if (s.trim().isNotEmpty) return s;
    }
    return null;
  }

  Map<String, dynamic> _normalizedBasePayload(DepartmentHours item) {
    final dept = item.name.trim();
    final loc = item.location.trim();
    if (dept.isEmpty) {
      throw Exception('Department/Office name is required');
    }
    return <String, dynamic>{
      'department': dept,
      'location': loc,
      'phone': item.phone,
      'is_office': item.isOffice,
    };
  }

  Future<void> _createNormalizedRows(DepartmentHours item, {String? previousDepartmentKey}) async {
    final base = _normalizedBasePayload(item);

    final rows = <Map<String, dynamic>>[];
    for (final entry in item.weeklyHours.entries) {
      final day = entry.key;
      for (final tr in entry.value) {
        rows.add({
          'id': const Uuid().v4(),
          ...base,
          'day_of_week': day,
          'open_time': tr.start,
          'close_time': tr.end,
        });
      }
    }

    if (rows.isEmpty) {
      throw Exception('Please add at least one time range');
    }

    // Replace existing rows for this department (normalized schema stores multiple rows per department).
    final deleteKey = (previousDepartmentKey?.trim().isNotEmpty ?? false)
        ? previousDepartmentKey!.trim()
        : item.name.trim();
    if (deleteKey.isNotEmpty) {
      try {
        await _supabase.from(_table).delete().eq('department', deleteKey);
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST204') rethrow;
      }
    }

    // Insert all rows; retry by dropping unknown columns if schema differs.
    for (final r in rows) {
      try {
        await _insertWithRetry(r);
      } on PostgrestException catch (e) {
        // If schema doesn't have start_time/end_time, try alternate column names start/end.
        if ((e.code == 'PGRST204' || e.code == '42703') && e.message.toLowerCase().contains("'start_time'")) {
          final retry = Map<String, dynamic>.from(r);
          final start = retry.remove('start_time');
          final end = retry.remove('end_time');
          retry['start'] = start;
          retry['end'] = end;
          await _insertWithRetry(retry);
          continue;
        }
        if ((e.code == 'PGRST204' || e.code == '42703') && e.message.toLowerCase().contains("'end_time'")) {
          final retry = Map<String, dynamic>.from(r);
          final start = retry.remove('start_time');
          final end = retry.remove('end_time');
          retry['start'] = start;
          retry['end'] = end;
          await _insertWithRetry(retry);
          continue;
        }
        // Some schemas use 1..7 where Sunday=7. If we inserted 0 and hit a check constraint, retry.
        final msg = e.message.toLowerCase();
        final isDayCheck = (e.code == '23514' || e.code == '22007') && msg.contains('day_of_week');
        if (!isDayCheck) rethrow;
        final dayAny = r['day_of_week'];
        final dayIdx = _parseDayIndex(dayAny);
        if (dayIdx == null) rethrow;
        if (dayIdx != 0) rethrow;
        final retry = Map<String, dynamic>.from(r);
        retry['day_of_week'] = 7;
        await _insertWithRetry(retry);
      }
    }
  }

  Map<String, dynamic> _removeMissingColumnIfPossible(Map<String, dynamic> payload, PostgrestException e) {
    final msg = e.message;
    String? bad;

    // Supabase/PostgREST can format this in a few different ways depending on the operation.
    final patterns = <RegExp>[
      RegExp(
        r"could not find the '([^']+)' column of (?:'department_hours'|department_hours)",
        caseSensitive: false,
      ),
      RegExp(
        r"column '([^']+)' of relation 'department_hours' does not exist",
        caseSensitive: false,
      ),
      RegExp(
        r'column "([^"]+)" of relation "department_hours" does not exist',
        caseSensitive: false,
      ),
      RegExp(
        r'column department_hours\\.([a-zA-Z0-9_]+) does not exist',
        caseSensitive: false,
      ),
    ];

    for (final p in patterns) {
      final m = p.firstMatch(msg);
      if (m != null) {
        bad = m.group(1);
        break;
      }
    }

    if (bad == null || !payload.containsKey(bad)) return payload;
    final next = Map<String, dynamic>.from(payload);
    next.remove(bad);
    return next;
  }

  Future<Map<String, dynamic>> _insertWithRetry(Map<String, dynamic> payload) async {
    var p = Map<String, dynamic>.from(payload);
    for (var i = 0; i < 5; i++) {
      try {
        final res = await _supabase.from(_table).insert(p).select().single();
        return Map<String, dynamic>.from(res as Map);
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST204' && e.code != '42703') rethrow;
        final next = _removeMissingColumnIfPossible(p, e);
        if (identical(next, p)) rethrow;
        p = next;
      }
    }
    final res = await _supabase.from(_table).insert(p).select().single();
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> _upsertWithRetry(Map<String, dynamic> payload) async {
    var p = Map<String, dynamic>.from(payload);
    for (var i = 0; i < 5; i++) {
      try {
        final res = await _supabase.from(_table).upsert(p, onConflict: 'id').select().single();
        return Map<String, dynamic>.from(res as Map);
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST204' && e.code != '42703') rethrow;
        final next = _removeMissingColumnIfPossible(p, e);
        if (identical(next, p)) rethrow;
        p = next;
      }
    }
    final res = await _supabase.from(_table).upsert(p, onConflict: 'id').select().single();
    return Map<String, dynamic>.from(res as Map);
  }

  // Realtime list stream
  Stream<List<DepartmentHours>> list() {
    return _supabase
        .from(_table)
        .stream(primaryKey: ['id'])
        .map((rows) {
          final mapped = rows.map((r) => Map<String, dynamic>.from(r)).toList(growable: false);
          final isNormalized = mapped.any((r) => r.containsKey('day_of_week'));
          if (!isNormalized) {
            final items = mapped.map((r) => DepartmentHours.fromMap(r)).toList();
            items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
            return items;
          }

          // Normalized schema: one row per department/day/time-range.
          final byDept = <String, DepartmentHours>{};
          final hours = <String, Map<int, List<TimeRange>>>{};

          for (final r in mapped) {
            final dept = _pickString(r, const ['department', 'name']) ?? '';
            if (dept.trim().isEmpty) continue;

            final key = dept.trim();
            final loc = _pickString(r, const ['location', 'office_location', 'office', 'room']) ?? '';
            final phone = _pickString(r, const ['phone', 'contact', 'tel']);
            final isOfficeAny = r['is_office'];
            final bool isOffice = switch (isOfficeAny) {
              bool v => v,
              num v => v != 0,
              String v => v.toLowerCase() == 'true' || v == '1' || v.toLowerCase() == 't',
              _ => true,
            };

            byDept.putIfAbsent(
              key,
              () => DepartmentHours(
                id: key, // use department as id so edit/delete can affect all its rows
                name: key,
                location: loc,
                phone: phone,
                isOffice: isOffice,
                weeklyHours: const <int, List<TimeRange>>{},
              ),
            );

            var dayIdx = _parseDayIndex(r['day_of_week']);
            if (dayIdx == 7) dayIdx = 0;
            final start = _pickString(r, const ['open_time', 'start_time', 'start']);
            final end = _pickString(r, const ['close_time', 'end_time', 'end']);
            if (dayIdx == null || start == null || end == null) continue;
            final h = hours.putIfAbsent(key, () => <int, List<TimeRange>>{});
            final list = h.putIfAbsent(dayIdx, () => <TimeRange>[]);
            list.add(TimeRange(start, end));
          }

          final out = <DepartmentHours>[];
          for (final entry in byDept.entries) {
            final key = entry.key;
            final base = entry.value;
            final wh = hours[key] ?? const <int, List<TimeRange>>{};
            // Sort ranges by start time
            final normalizedHours = <int, List<TimeRange>>{};
            for (final e in wh.entries) {
              final list = List<TimeRange>.from(e.value)..sort((a, b) => a.start.compareTo(b.start));
              normalizedHours[e.key] = list;
            }
            out.add(base.copyWith(weeklyHours: normalizedHours));
          }

          out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          return out;
        });
  }

  // Create
  Future<DepartmentHours> create(DepartmentHours item) async {
    final payload = item.copyWith(id: item.id.isEmpty ? const Uuid().v4() : item.id).toMap();
    try {
      final res = await _insertWithRetry(payload);
      return DepartmentHours.fromMap(res);
    } on PostgrestException catch (e) {
      print('DEBUG: PostgrestException in create: ${e.code} - ${e.message}');
      if (_isDayOfWeekNotNull(e)) {
        print('DEBUG: Detected day_of_week constraint, trying normalized rows');
        try {
          await _createNormalizedRows(item);
          return item;
        } catch (normalizedError) {
          print('DEBUG: Normalized rows failed: $normalizedError');
          // Re-throw the normalized error with more context
          throw Exception('Schema requires day_of_week: $normalizedError');
        }
      }
      rethrow;
    }
  }

  // Upsert by id
  Future<DepartmentHours> upsert(DepartmentHours item) async {
    final payload = item.toMap();
    try {
      final res = await _upsertWithRetry(payload);
      return DepartmentHours.fromMap(res);
    } on PostgrestException catch (e) {
      if (_isDayOfWeekNotNull(e)) {
        try {
          // If list() is normalized, item.id is the previous department key (dept name).
          await _createNormalizedRows(item, previousDepartmentKey: item.id);
          return item;
        } catch (normalizedError) {
          // Re-throw the normalized error with more context
          throw Exception('Schema requires day_of_week: $normalizedError');
        }
      }
      rethrow;
    }
  }

  // Delete by id
  Future<void> delete(String id) async {
    // Try delete by record id first
    await _supabase.from(_table).delete().eq('id', id);
    // If normalized, remove all rows for a department key as well
    try {
      await _supabase.from(_table).delete().eq('department', id);
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST204') rethrow;
    }
  }
}
