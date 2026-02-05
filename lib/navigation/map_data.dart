import 'package:vector_math/vector_math_64.dart' as vm;

class Waypoint {
  final String id;
  final vm.Vector3 pos;
  final List<String> neighbors;
  Waypoint(this.id, this.pos, this.neighbors);
}

// Simple floor plan: corridor along X, rooms on both sides
// Origin (0,0,0) is near the entrance; +X is east, -Z is north
final Map<String, Waypoint> kWaypoints = {
  // Entrance/origin area
  'W_ENTRANCE': Waypoint('W_ENTRANCE', vm.Vector3(0, 0, 0), ['W_CORRIDOR_1']),
  // Corridor waypoints
  'W_CORRIDOR_1': Waypoint('W_CORRIDOR_1', vm.Vector3(2, 0, 0), ['W_ENTRANCE', 'W_CORRIDOR_2']),
  'W_CORRIDOR_2': Waypoint('W_CORRIDOR_2', vm.Vector3(4, 0, 0), ['W_CORRIDOR_1', 'W_CORRIDOR_3', 'W_CL1', 'W_CL2']),
  'W_CORRIDOR_3': Waypoint('W_CORRIDOR_3', vm.Vector3(6, 0, 0), ['W_CORRIDOR_2', 'W_CORRIDOR_4', 'W_CL3', 'W_CL4']),
  'W_CORRIDOR_4': Waypoint('W_CORRIDOR_4', vm.Vector3(8, 0, 0), ['W_CORRIDOR_3', 'W_CORRIDOR_5', 'W_CL5', 'W_CL6']),
  'W_CORRIDOR_5': Waypoint('W_CORRIDOR_5', vm.Vector3(10, 0, 0), ['W_CORRIDOR_4', 'W_CORRIDOR_6', 'W_CL7', 'W_CL8']),
  'W_CORRIDOR_6': Waypoint('W_CORRIDOR_6', vm.Vector3(12, 0, 0), ['W_CORRIDOR_5', 'W_ADMIN1', 'W_ADMIN2']),
  // CL Rooms (north side of corridor)
  'W_CL1': Waypoint('W_CL1', vm.Vector3(4, 0, -3), ['W_CORRIDOR_2']),
  'W_CL2': Waypoint('W_CL2', vm.Vector3(4, 0, 3), ['W_CORRIDOR_2']),
  'W_CL3': Waypoint('W_CL3', vm.Vector3(6, 0, -3), ['W_CORRIDOR_3']),
  'W_CL4': Waypoint('W_CL4', vm.Vector3(6, 0, 3), ['W_CORRIDOR_3']),
  'W_CL5': Waypoint('W_CL5', vm.Vector3(8, 0, -3), ['W_CORRIDOR_4']),
  'W_CL6': Waypoint('W_CL6', vm.Vector3(8, 0, 3), ['W_CORRIDOR_4']),
  'W_CL7': Waypoint('W_CL7', vm.Vector3(10, 0, -3), ['W_CORRIDOR_5']),
  'W_CL8': Waypoint('W_CL8', vm.Vector3(10, 0, 3), ['W_CORRIDOR_5']),
  // Admin Offices (end of corridor)
  'W_ADMIN1': Waypoint('W_ADMIN1', vm.Vector3(12, 0, -2), ['W_CORRIDOR_6']),
  'W_ADMIN2': Waypoint('W_ADMIN2', vm.Vector3(12, 0, 2), ['W_CORRIDOR_6']),
};

final Map<String, String> kRoomToWaypoint = {
  // CL Rooms
  'CL 1': 'W_CL1',
  'CL 2': 'W_CL2',
  'CL 3': 'W_CL3',
  'CL 4': 'W_CL4',
  'CL 5': 'W_CL5',
  'CL 6': 'W_CL6',
  'CL 7': 'W_CL7',
  'CL 8': 'W_CL8',
  'CL 9': 'W_CL1', // fallback to CL1 for demo
  'CL 10': 'W_CL2', // fallback to CL2 for demo
  // Admin Offices
  'Admin Office 1': 'W_ADMIN1',
  'Admin Office 2': 'W_ADMIN2',
  'Admin Office 3': 'W_ADMIN1', // fallback
  'Admin Office 4': 'W_ADMIN2', // fallback
  'Admin Office 5': 'W_ADMIN1', // fallback
};

// Runtime storage for custom destinations
final Map<String, vm.Vector3> kCustomDestinations = {};

String getStartWaypointForCurrentArea() {
  return 'W_ENTRANCE';
}

String findNearestWaypointId(vm.Vector3 p, Map<String, Waypoint> waypoints) {
  String? bestId;
  double bestD = double.infinity;
  for (final entry in waypoints.entries) {
    final d = (entry.value.pos - p).length;
    if (d < bestD) {
      bestD = d;
      bestId = entry.key;
    }
  }
  return bestId ?? 'W_START';
}
