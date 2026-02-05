import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'map_data.dart';
import '../core/debug_logger.dart';

class RoomCoordinatesService {
  static final RoomCoordinatesService _instance = RoomCoordinatesService._internal();
  factory RoomCoordinatesService() => _instance;
  RoomCoordinatesService._internal();

  final Map<String, vm.Vector3> _coordinates = {};
  final Map<String, int> _floors = {};
  bool _loaded = false;

  Future<void> loadCoordinates() async {
    if (_loaded) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      for (final room in kRoomToWaypoint.keys) {
        final lat = prefs.getDouble('coord_${room}_lat');
        final lon = prefs.getDouble('coord_${room}_lon');
        final height = prefs.getDouble('coord_${room}_height');
        final floor = prefs.getInt('coord_${room}_floor');
        
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
      
      _loaded = true;
      logger.info('Room coordinates loaded', tag: 'RoomCoords', error: {'count': _coordinates.length});
    } catch (e, st) {
      logger.error('Failed to load room coordinates', tag: 'RoomCoords', error: e, stackTrace: st);
    }
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
