import 'dart:convert';

import 'package:flutter/foundation.dart';

@immutable
class TimeRange {
  final String start; // HH:MM 24h
  final String end;   // HH:MM 24h
  const TimeRange(this.start, this.end);

  Map<String, dynamic> toMap() => {'start': start, 'end': end};
  factory TimeRange.fromMap(Map<String, dynamic> map) => TimeRange(
        map['start'] as String,
        map['end'] as String,
      );
}

@immutable
class DepartmentHours {
  final String id;
  final String name;
  final String location;
  final String? phone;
  final bool isOffice; // true for offices (Registrar, Library, etc.)
  // key: 0=Sun..6=Sat
  final Map<int, List<TimeRange>> weeklyHours;

  const DepartmentHours({
    required this.id,
    required this.name,
    required this.location,
    required this.weeklyHours,
    this.phone,
    this.isOffice = true,
  });

  DepartmentHours copyWith({
    String? id,
    String? name,
    String? location,
    String? phone,
    bool? isOffice,
    Map<int, List<TimeRange>>? weeklyHours,
  }) => DepartmentHours(
        id: id ?? this.id,
        name: name ?? this.name,
        location: location ?? this.location,
        phone: phone ?? this.phone,
        isOffice: isOffice ?? this.isOffice,
        weeklyHours: weeklyHours ?? this.weeklyHours,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'department': name,
        'location': location,
        'phone': phone,
        'is_office': isOffice,
        // store as {"0":[{start,end}],"1":[...],...}
        'weekly_hours': weeklyHours.map((k, v) => MapEntry(k.toString(), v.map((e) => e.toMap()).toList())),
      };

  factory DepartmentHours.fromMap(Map<String, dynamic> map) {
    final weeklyAny = map['weekly_hours'];
    Map<String, dynamic> raw;
    if (weeklyAny is Map) {
      raw = weeklyAny.map((k, v) => MapEntry(k.toString(), v));
    } else if (weeklyAny is String) {
      try {
        final decoded = jsonDecode(weeklyAny);
        if (decoded is Map) {
          raw = decoded.map((k, v) => MapEntry(k.toString(), v));
        } else {
          raw = <String, dynamic>{};
        }
      } catch (_) {
        raw = <String, dynamic>{};
      }
    } else {
      raw = <String, dynamic>{};
    }

    final parsed = <int, List<TimeRange>>{};
    for (final entry in raw.entries) {
      final dayIdx = int.tryParse(entry.key) ?? 0;
      final listAny = entry.value;
      if (listAny is! List) continue;
      final list = listAny
          .whereType<Map>()
          .map((e) => TimeRange.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      if (list.isNotEmpty) parsed[dayIdx] = list;
    }

    final isOfficeAny = map['is_office'];
    final bool isOffice = switch (isOfficeAny) {
      bool v => v,
      num v => v != 0,
      String v => v.toLowerCase() == 'true' || v == '1' || v.toLowerCase() == 't',
      _ => true,
    };
    return DepartmentHours(
      id: map['id']?.toString() ?? '',
      name: (map['name'] ?? map['department'])?.toString() ?? '',
      location: (map['location'] ?? map['office_location'] ?? map['office'] ?? map['room'])?.toString() ?? '',
      phone: (map['phone'] ?? map['contact'] ?? map['tel'])?.toString(),
      isOffice: isOffice,
      weeklyHours: parsed,
    );
  }
}
