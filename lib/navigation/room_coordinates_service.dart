import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../core/debug_logger.dart';

class RoomCoordinatesService {
  static final RoomCoordinatesService _instance = RoomCoordinatesService._internal();
  factory RoomCoordinatesService() => _instance;
  RoomCoordinatesService._internal();

  static const String _table = 'room_coordinates';
  final SupabaseClient _supabase = Supabase.instance.client;

  final Map<String, vm.Vector3> _coordinates = {};
  final Map<String, int> _floors = {};
  bool _loaded = false;

  bool _isMissingColumn(PostgrestException e) {
    return e.code == 'PGRST204' || e.code == '42703';
  }

  Future<void> loadCoordinates({bool force = false}) async {
    if (_loaded && !force) return;

    try {
      _coordinates.clear();
      _floors.clear();

      final response = await _supabase.from(_table).select();
      if (response is List) {
        for (final row in response) {
          if (row is! Map) continue;
          final r = Map<String, dynamic>.from(row as Map);

          final room = (r['room_code'] ?? r['code'] ?? r['room'])?.toString();
          if (room == null || room.trim().isEmpty) continue;

          final latAny = r['lat'] ?? r['latitude'];
          final lonAny = r['lon'] ?? r['lng'] ?? r['longitude'];
          final heightAny = r['height'] ?? r['altitude'];
          final floorAny = r['floor'] ?? r['level'];

          final lat = latAny is num ? latAny.toDouble() : double.tryParse(latAny?.toString() ?? '');
          final lon = lonAny is num ? lonAny.toDouble() : double.tryParse(lonAny?.toString() ?? '');
          final height = heightAny is num ? heightAny.toDouble() : double.tryParse(heightAny?.toString() ?? '');
          final floor = floorAny is num ? floorAny.toInt() : int.tryParse(floorAny?.toString() ?? '');

          if (lat != null && lon != null) {
            // Store as Vector3(lon, height, lat) - using lon as X, lat as Z
            _coordinates[room] = vm.Vector3(lon, height ?? 0.0, lat);
            _floors[room] = floor ?? 1;
            logger.info('Loaded coordinates for $room', tag: 'RoomCoords', error: {
              'lat': lat,
              'lon': lon,
              'height': height,
              'floor': floor,
            });
          }
        }
      }

      _loaded = true;
      logger.info('Room coordinates loaded', tag: 'RoomCoords', error: {'count': _coordinates.length});
    } on PostgrestException catch (e, st) {
      logger.error('Failed to load room coordinates', tag: 'RoomCoords', error: e, stackTrace: st);
      _loaded = true;
    } catch (e, st) {
      logger.error('Failed to load room coordinates', tag: 'RoomCoords', error: e, stackTrace: st);
      _loaded = true;
    }
  }

  Future<void> upsertCoordinates({
    required String roomCode,
    required double lat,
    required double lon,
    double height = 0.0,
    int floor = 1,
  }) async {
    final payloads = <({Map<String, dynamic> payload, String conflict})>[
      (
        payload: {
          'room_code': roomCode,
          'lat': lat,
          'lon': lon,
          'height': height,
          'floor': floor,
        },
        conflict: 'room_code',
      ),
      (
        payload: {
          'code': roomCode,
          'lat': lat,
          'lon': lon,
          'height': height,
          'floor': floor,
        },
        conflict: 'code',
      ),
      (
        payload: {
          'room': roomCode,
          'lat': lat,
          'lon': lon,
          'height': height,
          'floor': floor,
        },
        conflict: 'room',
      ),
      (
        payload: {
          'room_code': roomCode,
          'latitude': lat,
          'longitude': lon,
          'altitude': height,
          'level': floor,
        },
        conflict: 'room_code',
      ),
      (
        payload: {
          'code': roomCode,
          'latitude': lat,
          'longitude': lon,
          'altitude': height,
          'level': floor,
        },
        conflict: 'code',
      ),
      (
        payload: {
          'room': roomCode,
          'latitude': lat,
          'longitude': lon,
          'altitude': height,
          'level': floor,
        },
        conflict: 'room',
      ),
      (
        payload: {
          'room_code': roomCode,
          'lat': lat,
          'lng': lon,
          'height': height,
          'floor': floor,
        },
        conflict: 'room_code',
      ),
      (
        payload: {
          'room_code': roomCode,
          'lat': lat,
          'longitude': lon,
          'height': height,
          'floor': floor,
        },
        conflict: 'room_code',
      ),
    ];

    PostgrestException? lastMissing;
    for (final p in payloads) {
      try {
        await _supabase.from(_table).upsert(p.payload, onConflict: p.conflict);
        _coordinates[roomCode] = vm.Vector3(lon, height, lat);
        _floors[roomCode] = floor;
        _loaded = true;
        return;
      } on PostgrestException catch (e) {
        if (_isMissingColumn(e)) {
          lastMissing = e;
          continue;
        }
        rethrow;
      }
    }

    if (lastMissing != null) throw lastMissing;
  }

  Future<void> clearCoordinates(String roomCode) async {
    final keys = <String>['room_code', 'code', 'room'];
    PostgrestException? lastMissing;
    for (final k in keys) {
      try {
        await _supabase.from(_table).delete().eq(k, roomCode);
        _coordinates.remove(roomCode);
        _floors.remove(roomCode);
        _loaded = true;
        return;
      } on PostgrestException catch (e) {
        if (_isMissingColumn(e)) {
          lastMissing = e;
          continue;
        }
        rethrow;
      }
    }

    if (lastMissing != null) throw lastMissing;
    _coordinates.remove(roomCode);
    _floors.remove(roomCode);
    _loaded = true;
  }

  vm.Vector3? getCoordinates(String room) {
    if (!_loaded) {
      logger.warning('Coordinates not loaded yet', tag: 'RoomCoords');
      return null;
    }
    return _coordinates[room];
  }

  int? getFloor(String room) {
    if (!_loaded) return null;
    return _floors[room];
  }

  bool hasCoordinates(String room) {
    return _coordinates.containsKey(room);
  }

  Map<String, vm.Vector3> get allCoordinates => Map.unmodifiable(_coordinates);
  Map<String, int> get allFloors => Map.unmodifiable(_floors);
}
