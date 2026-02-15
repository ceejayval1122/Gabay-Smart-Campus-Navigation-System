import 'dart:async';
import 'dart:math' as math;

import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin/datatypes/node_types.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin/models/ar_node.dart';
import 'package:ar_flutter_plugin/widgets/ar_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../../navigation/a_star.dart';
import '../../navigation/map_data.dart';
import '../../navigation/room_coordinates_service.dart';
import '../../core/debug_logger.dart';

class ARNavigateView extends StatefulWidget {
  final String destinationCode;
  final vm.Vector3? initialOrigin;
  final double? initialYawRad;
  const ARNavigateView({super.key, required this.destinationCode, this.initialOrigin, this.initialYawRad});
  @override
  State<ARNavigateView> createState() => _ARNavigateViewState();
}

class _ARNavigateViewState extends State<ARNavigateView> with WidgetsBindingObserver {
  bool _disposed = false;
  Timer? _gpsUpdateTimer;
  Timer? _arrowUpdateTimer;
  
  ARSessionManager? sessionManager;
  ARObjectManager? objectManager;
  ARAnchorManager? anchorManager;
  ARLocationManager? locationManager;
  
  ARNode? _userMarker;
  ARNode? _directionArrow;
  ARNode? _destNode;
  
  final List<ARNode> _roomMarkers = [];
  final List<ARNode> _breadcrumbs = [];
  
  bool ready = false;
  bool originSet = false;
  double currentDistance = 0.0;
  vm.Vector3 origin = vm.Vector3.zero();
  vm.Vector3? _lastGpsPosition;
  vm.Vector3? _destWorld;
  vm.Vector3? _targetWorld;
  double? _originYawRad;
  bool _arrivalNotified = false;

  static const double _arrivalThresholdMeters = 2.0;

  double? _refLat;
  double? _refLon;

  // Fixed building-to-world mapping established once at origin
  vm.Vector3? _worldOrigin;
  vm.Vector3? _buildingOrigin;
  double? _worldYaw;

  // GPS smoothing
  vm.Vector3? _smoothedGps;
  static const double _gpsSmoothAlpha = 0.3;

  // When true, render a straight line to the destination instead of a waypoint/A* path.
  // This is better for indoor environments where GPS + no floorplan can make curved paths misleading.
  final bool _useDirectGuidance = true;

  // Resolve real destination for the selected room
  vm.Vector3? get _destinationWorld {
    // Check custom destinations first
    if (kCustomDestinations.containsKey(widget.destinationCode)) {
      return kCustomDestinations[widget.destinationCode];
    }
    
    // Check for saved room coordinates
    final roomCoords = RoomCoordinatesService().getCoordinates(widget.destinationCode);
    if (roomCoords != null) {
      logger.info('Using saved coordinates for room', tag: 'AR', error: {
        'room': widget.destinationCode,
        'coords': [roomCoords.x, roomCoords.y, roomCoords.z],
      });
      return roomCoords;
    }
    
    // Fall back to predefined waypoints
    final waypointId = kRoomToWaypoint[widget.destinationCode];
    if (waypointId == null) {
      logger.warning('No waypoint mapping for destination', tag: 'AR', error: {'destinationCode': widget.destinationCode});
      return null;
    }
    final waypoint = kWaypoints[waypointId];
    if (waypoint == null) {
      logger.warning('Waypoint not found', tag: 'AR', error: {'waypointId': waypointId});
      return null;
    }
    return waypoint.pos;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRoomCoordinates();
  }

  void _ensureReferenceLatLon({required double lat, required double lon}) {
    _refLat ??= lat;
    _refLon ??= lon;
  }

  vm.Vector3 _latLonToLocalMeters({required double lat, required double lon, required double heightMeters}) {
    final refLat = _refLat;
    final refLon = _refLon;
    if (refLat == null || refLon == null) {
      return vm.Vector3.zero();
    }

    // Approx meters per degree. Good enough for campus scale.
    const metersPerDegLat = 111320.0;
    final metersPerDegLon = 111320.0 * math.cos(refLat * math.pi / 180.0);

    final dx = (lon - refLon) * metersPerDegLon;
    final dz = (lat - refLat) * metersPerDegLat;
    return vm.Vector3(dx, heightMeters, dz);
  }

  /// Maps building coordinates to AR world coordinates using the fixed origin mapping.
  vm.Vector3 _buildingToWorld(vm.Vector3 buildingPos) {
    if (_worldOrigin == null || _buildingOrigin == null || _worldYaw == null) {
      return buildingPos;
    }
    final delta = buildingPos - _buildingOrigin!;
    final rot = vm.Matrix3.rotationY(_worldYaw!);
    final rotated = rot.transformed(vm.Vector3(delta.x, 0, delta.z));
    final groundY = _worldOrigin!.y - 1.2;
    return vm.Vector3(
      _worldOrigin!.x + rotated.x,
      groundY + delta.y,
      _worldOrigin!.z + rotated.z,
    );
  }

  /// Places or replaces the destination marker at the given AR world position.
  Future<void> _placeDestinationMarker(vm.Vector3 worldPos) async {
    if (_disposed || objectManager == null) return;
    if (_destNode != null) {
      try { await objectManager?.removeNode(_destNode!); } catch (_) {}
      _destNode = null;
    }
    final marker = ARNode(
      type: NodeType.coloredBox,
      uri: 'coloredBox',
      scale: vm.Vector3(0.25, 0.25, 0.25),
      position: worldPos,
    );
    try {
      await objectManager?.addNode(marker);
      _destNode = marker;
    } catch (e, st) {
      logger.error('Failed to add destination marker', tag: 'AR', error: e, stackTrace: st);
    }
  }

  Future<void> _loadRoomCoordinates() async {
    await RoomCoordinatesService().loadCoordinates();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No explicit pause/resume API in the plugin; disposing is handled on screen exit.
    logger.info('AR lifecycle', tag: 'AR', error: {'state': state.name});
  }

  Future<void> _startGpsTracking() async {
    // Request location permission first
    final status = await Permission.location.request();
    if (!status.isGranted) {
      logger.warning('Location permission denied', tag: 'AR', error: {'status': status.name});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required for live navigation.')),
        );
      }
      return;
    }
    try {
      final ok = await locationManager?.startLocationUpdates();
      if (ok == true) {
        logger.info('GPS tracking started', tag: 'AR');
        _gpsUpdateTimer = Timer.periodic(const Duration(seconds: 2), (_) => _onGpsUpdate());
      } else {
        logger.warning('Failed to start GPS updates', tag: 'AR');
      }
    } catch (e, st) {
      logger.error('GPS tracking error', tag: 'AR', error: e, stackTrace: st);
    }
  }

  void _onGpsUpdate() {
    if (_disposed || !originSet) return;
    final pos = locationManager?.currentLocation;
    if (pos == null) return;

    _ensureReferenceLatLon(lat: pos.latitude, lon: pos.longitude);
    final gpsPos = _latLonToLocalMeters(lat: pos.latitude, lon: pos.longitude, heightMeters: 0);

    // Smooth GPS to reduce jitter
    if (_smoothedGps == null) {
      _smoothedGps = gpsPos;
    } else {
      _smoothedGps = _smoothedGps! * (1 - _gpsSmoothAlpha) + gpsPos * _gpsSmoothAlpha;
    }

    if (_lastGpsPosition != null && (_smoothedGps! - _lastGpsPosition!).length < 0.5) return;
    _lastGpsPosition = _smoothedGps;
    logger.info('GPS position updated (smoothed)', tag: 'AR', error: {'lat': pos.latitude, 'lon': pos.longitude});
    // Destination stays fixed in AR world; route line is updated by _refreshRouteFromCamera timer.
  }

  Future<void> _updateRouteLineFromPose({
    required vm.Matrix4 camPose,
    required vm.Vector3 camWorld,
    required vm.Vector3 targetWorld,
  }) async {
    if (_disposed || objectManager == null) return;

    for (final n in _breadcrumbs) {
      try {
        await objectManager?.removeNode(n);
      } catch (_) {}
    }
    _breadcrumbs.clear();

    // Use camera-relative coordinates for consistent centering
    final camPos = camPose.getTranslation();
    
    // Ground-align route visuals relative to camera height.
    final groundY = camPos.y - 1.2;
    
    // Start line from camera position projected to ground for perfect centering
    final startGround = vm.Vector3(camPos.x, groundY, camPos.z);
    final endGround = vm.Vector3(targetWorld.x, groundY, targetWorld.z);
    final seg = endGround - startGround;
    final segLen = seg.length;

    // Straight route line from camera-center to destination (ground-aligned).
    if (segLen > 0.3) {
      final yawSeg = math.atan2(seg.x, -seg.z);
      final pathCenter = vm.Vector3(
        startGround.x + seg.x / 2,
        groundY,
        startGround.z + seg.z / 2,
      );
      final pathLine = ARNode(
        type: NodeType.coloredBox,
        uri: 'coloredBox',
        scale: vm.Vector3(0.06, 0.01, segLen),
        position: pathCenter,
        eulerAngles: vm.Vector3(0, yawSeg, 0),
      );
      try {
        await objectManager?.addNode(pathLine);
        _breadcrumbs.add(pathLine);
      } catch (e, st) {
        logger.error('Failed to add path line', tag: 'AR', error: e, stackTrace: st);
      }
    }

    // Destination beacon: vertical pillar from route end up toward the destination height.
    final beaconHeightNum = (targetWorld.y - groundY).clamp(1.2, 12.0);
    final beaconHeight = beaconHeightNum.toDouble();
    final beacon = ARNode(
      type: NodeType.coloredBox,
      uri: 'coloredBox',
      scale: vm.Vector3(0.10, beaconHeight, 0.10),
      position: endGround + vm.Vector3(0, beaconHeight / 2, 0),
    );
    try {
      await objectManager?.addNode(beacon);
      _breadcrumbs.add(beacon);
    } catch (e, st) {
      logger.error('Failed to add destination beacon', tag: 'AR', error: e, stackTrace: st);
    }

    _updateDistance();
  }

  Future<void> _updateArPath(List<vm.Vector3> polyline, vm.Vector3 gpsPos) async {
    // Legacy breadcrumb renderer disabled (Pokémon-Go style markers only).
    return;
  }

  void onARViewCreated(ARSessionManager s, ARObjectManager o, ARAnchorManager a, ARLocationManager l) {
    sessionManager = s;
    objectManager = o;
    anchorManager = a;
    locationManager = l;
    () async {
      if (_disposed) return;
      logger.info('AR view created', tag: 'AR', error: {
        'destination': widget.destinationCode,
        'kIsWeb': kIsWeb,
        'platform': defaultTargetPlatform.name,
      });
      try {
        sessionManager!.onInitialize(
          showAnimatedGuide: false,
          showFeaturePoints: false,
          showPlanes: false,
          showWorldOrigin: false,
          handleTaps: false,
        );
        objectManager!.onInitialize();
        sessionManager!.onPlaneOrPointTap = _onPlaneTap;
        if (mounted && !_disposed) setState(() => ready = true);

        await _startGpsTracking();
        await Future.delayed(const Duration(milliseconds: 900));
        if (_disposed) return;
        await _autoStart();
      } catch (e, st) {
        logger.fatal('Failed to initialize AR session', tag: 'AR', error: e, stackTrace: st);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS is loading, please wait a moment...'),
            duration: Duration(seconds: 3),
          ),
        );
        // Wait a moment before trying to pop, in case GPS is still initializing
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) Navigator.of(context).pop();
      }
    }();
  }

  Future<void> _autoStart() async {
    if (_disposed) return;
    logger.info('AR autoStart begin', tag: 'AR');
    // Always fetch current camera pose to anchor AR world
    vm.Matrix4? camPose;
    for (int i = 0; i < 20; i++) {
      if (_disposed) return;
      try {
        camPose = await sessionManager?.getCameraPose();
      } catch (e, st) {
        logger.error('getCameraPose failed', tag: 'AR', error: e, stackTrace: st);
      }
      if (camPose != null) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (camPose == null) {
      logger.warning('Camera pose not available; AR session may not be supported on this device.', tag: 'AR');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPS is loading, please wait a moment...'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    final camPos = camPose.getTranslation();

    // If QR provided an initial origin (camera position in building space), pass it through
    if (widget.initialOrigin != null) {
      await _setOrigin(
        vm.Vector3(camPos.x, camPos.y, camPos.z),
        auto: true,
        camPose: camPose,
        camPositionBuilding: widget.initialOrigin,
        overrideYaw: widget.initialYawRad,
      );
      return;
    }

    // Fallback: use camera pose as both AR world anchor and building origin
    await _setOrigin(vm.Vector3(camPos.x, camPos.y, camPos.z), auto: true, camPose: camPose);
  }

  Future<void> _onPlaneTap(List<ARHitTestResult> hits) async {
    if (hits.isEmpty) return;
    final h = hits.firstWhere((e) => e.type == ARHitTestResultType.plane, orElse: () => hits.first);
    final m = h.worldTransform;
    final pos = vm.Vector3(m.getColumn(3).x, m.getColumn(3).y, m.getColumn(3).z);
    await _setOrigin(pos);
  }

  Future<void> _setOrigin(vm.Vector3 pos, {bool auto = false, vm.Matrix4? camPose, double? overrideYaw, vm.Vector3? camPositionBuilding}) async {
    if (_disposed) return;
    // Validate destination early
    final destWorld = _destinationWorld;
    if (destWorld == null) {
      logger.warning('Cannot resolve destination; aborting path rendering', tag: 'AR', error: {'destinationCode': widget.destinationCode});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unknown destination: ${widget.destinationCode}')),
        );
        Navigator.of(context).pop();
      }
      return;
    }
    logger.info('Setting AR origin', tag: 'AR', error: {
      'auto': auto,
      'pos': [pos.x, pos.y, pos.z],
      'destination': widget.destinationCode,
      'hasInitialOrigin': camPositionBuilding != null,
    });
    // Clear previous nodes
    for (final n in _breadcrumbs) {
      try { await objectManager?.removeNode(n); } catch (_) {}
    }
    _breadcrumbs.clear();
    for (final marker in _roomMarkers) {
      try { await objectManager?.removeNode(marker); } catch (_) {}
    }
    _roomMarkers.clear();
    if (_destNode != null) {
      try { await objectManager?.removeNode(_destNode!); } catch (_) {}
      _destNode = null;
    }
    if (_directionArrow != null) {
      try { await objectManager?.removeNode(_directionArrow!); } catch (_) {}
      _directionArrow = null;
    }

    origin = pos;
    originSet = true;
    _arrivalNotified = false;

    // Determine forward from provided cam pose or latest
    vm.Vector3 forward = vm.Vector3(0, 0, -1);
    vm.Matrix4? pose = camPose;
    if (pose == null) {
      try {
        pose = await sessionManager?.getCameraPose();
      } catch (e, st) {
        logger.error('getCameraPose failed in _setOrigin', tag: 'AR', error: e, stackTrace: st);
      }
    }
    if (pose != null) {
      final zCol = pose.getColumn(2); // camera forward is -Z
      forward = vm.Vector3(-zCol.x, -zCol.y, -zCol.z).normalized();
    }

    // If the destination comes from saved room lat/lon, use local-meter conversion and direct guidance.
    final roomCoordsDeg = RoomCoordinatesService().getCoordinates(widget.destinationCode);
    vm.Vector3 startPos;
    vm.Vector3 goal;
    List<vm.Vector3> polyline;

    if (roomCoordsDeg != null) {
      final gps = locationManager?.currentLocation;
      if (gps == null) {
        logger.warning('Waiting for GPS fix to use saved room coordinates', tag: 'AR');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('GPS is loading, please wait a moment...'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        // Don't return immediately - wait a bit and retry
        await Future.delayed(const Duration(seconds: 2));
        if (_disposed) return;
        
        // Retry getting GPS location
        final retryGps = locationManager?.currentLocation;
        if (retryGps == null) {
          logger.warning('GPS still not available after retry, falling back to waypoints', tag: 'AR');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('GPS unavailable. Using default navigation.'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          // Fall back to waypoint-based navigation
          startPos = kWaypoints[getStartWaypointForCurrentArea()]?.pos ?? vm.Vector3.zero();
          final destId = kRoomToWaypoint[widget.destinationCode];
          if (destId == null) return;
          goal = kWaypoints[destId]?.pos ?? destWorld;
          polyline = _useDirectGuidance ? <vm.Vector3>[startPos, goal] : () {
            final startId = findNearestWaypointId(startPos, kWaypoints);
            final path = findPathAStar(waypoints: kWaypoints, startId: startId, goalId: destId);
            return path.isEmpty ? <vm.Vector3>[startPos, goal] : waypointsToPolyline(path);
          }();
        } else {
          _ensureReferenceLatLon(lat: retryGps.latitude, lon: retryGps.longitude);
          startPos = _latLonToLocalMeters(lat: retryGps.latitude, lon: retryGps.longitude, heightMeters: 0);
          goal = _latLonToLocalMeters(lat: roomCoordsDeg.z, lon: roomCoordsDeg.x, heightMeters: roomCoordsDeg.y);
          polyline = <vm.Vector3>[startPos, goal];
        }
      } else {
        _ensureReferenceLatLon(lat: gps.latitude, lon: gps.longitude);
        startPos = _latLonToLocalMeters(lat: gps.latitude, lon: gps.longitude, heightMeters: 0);
        goal = _latLonToLocalMeters(lat: roomCoordsDeg.z, lon: roomCoordsDeg.x, heightMeters: roomCoordsDeg.y);
        polyline = <vm.Vector3>[startPos, goal];
      }
    } else {
      // Waypoint-based routing (predefined map coordinates)
      startPos = kWaypoints[getStartWaypointForCurrentArea()]?.pos ?? vm.Vector3.zero();
      final destId = kRoomToWaypoint[widget.destinationCode];
      if (destId == null) {
        // This should never happen because we validated _destinationWorld above
        return;
      }
      goal = kWaypoints[destId]?.pos ?? destWorld; // use resolved destination
      polyline = _useDirectGuidance ? <vm.Vector3>[startPos, goal] : () {
        final startId = findNearestWaypointId(startPos, kWaypoints);
        final path = findPathAStar(waypoints: kWaypoints, startId: startId, goalId: destId);
        return path.isEmpty ? <vm.Vector3>[startPos, goal] : waypointsToPolyline(path);
      }();
    }

    // Establish fixed building-to-world mapping (done once at origin)
    vm.Vector3 camWorldPos;
    if (pose != null) {
      final cp = pose.getTranslation();
      camWorldPos = vm.Vector3(cp.x, cp.y, cp.z);
    } else {
      camWorldPos = pos;
    }
    _worldOrigin = camWorldPos;
    _buildingOrigin = startPos;
    _worldYaw = overrideYaw ?? math.atan2(forward.x, -forward.z);

    // Compute destination in AR world space (fixed — won't drift with GPS)
    _targetWorld = _buildingToWorld(goal);
    _destWorld = _targetWorld;
    _arrivalNotified = false;

    // Place destination marker at the fixed world position
    await _placeDestinationMarker(_targetWorld!);

    // Draw initial route line from camera to destination
    if (pose != null) {
      await _updateRouteLineFromPose(
        camPose: pose,
        camWorld: camWorldPos,
        targetWorld: _targetWorld!,
      );
    }

    if (mounted && !_disposed) setState(() {});
    
    // Start continuous arrow updates
    _startArrowUpdates();
  }

  void _startArrowUpdates() {
    if (_disposed || sessionManager == null) return;
    _arrowUpdateTimer?.cancel();
    _arrowUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_disposed) {
        timer.cancel();
        return;
      }
      await _updateDirectionArrow();
      await _refreshRouteFromCamera();
    });
  }

  Future<void> _refreshRouteFromCamera() async {
    if (_disposed || sessionManager == null || _targetWorld == null) return;
    try {
      final camPose = await sessionManager!.getCameraPose();
      if (camPose == null) return;
      final camPos = camPose.getTranslation();
      final camWorld = vm.Vector3(camPos.x, camPos.y, camPos.z);
      await _updateRouteLineFromPose(
        camPose: camPose,
        camWorld: camWorld,
        targetWorld: _targetWorld!,
      );
    } catch (e, st) {
      logger.error('Failed to refresh route line', tag: 'AR', error: e, stackTrace: st);
    }
  }

  Future<void> _updateDirectionArrow() async {
    if (_disposed || sessionManager == null || !originSet || _destWorld == null) return;

    try {
      final camPose = await sessionManager!.getCameraPose();
      if (camPose == null) return;
      final camPos = camPose.getTranslation();
      
      // Calculate direction to destination
      final direction = _destWorld! - vm.Vector3(camPos.x, camPos.y, camPos.z);
      final flat = vm.Vector3(direction.x, 0, direction.z);
      if (flat.length < 0.01) return;
      final norm = flat.normalized();
      final yaw = math.atan2(norm.x, -norm.z);
      
      // Remove old arrow if exists
      if (_directionArrow != null) {
        await objectManager?.removeNode(_directionArrow!);
      }
      
      // Create arrow at camera position, pointing toward destination
      _directionArrow = ARNode(
        type: NodeType.coloredBox,
        uri: 'coloredBox',
        scale: vm.Vector3(0.50, 0.03, 0.12),
        position: vm.Vector3(camPos.x, camPos.y - 0.7, camPos.z) + (norm * 0.8),
        eulerAngles: vm.Vector3(0, yaw, 0),
      );
      
      await objectManager?.addNode(_directionArrow!);
    } catch (e, st) {
      logger.error('Failed to update direction arrow', tag: 'AR', error: e, stackTrace: st);
    }
  }

  Future<void> _renderRoomMarkers(vm.Vector3 currentPos, vm.Vector3 Function(vm.Vector3) tf) async {
    if (_disposed) return;
    if (objectManager == null) return;

    final allCoords = RoomCoordinatesService().allCoordinates;
    if (allCoords.isEmpty) return;

    // Show markers for rooms within 50 meters
    const maxDistance = 50.0;

    for (final entry in allCoords.entries) {
      final room = entry.key;
      final roomCoords = entry.value;

      // Skip the target room (it already has a destination pin)
      if (room == widget.destinationCode) continue;

      // Convert saved coords (lon,height,lat) to local meters (x,y,z)
      final roomPos = _latLonToLocalMeters(
        lat: roomCoords.z,
        lon: roomCoords.x,
        heightMeters: roomCoords.y,
      );

      final distance = currentPos.distanceTo(roomPos);
      if (distance > maxDistance) continue;

      final worldPos = tf(roomPos);

      final marker = ARNode(
        type: NodeType.coloredBox,
        uri: 'coloredBox',
        scale: vm.Vector3(0.18, 0.18, 0.18),
        position: worldPos + vm.Vector3(0, 0.5, 0), // Same height as target
      );

      try {
        await objectManager?.addNode(marker);
        _roomMarkers.add(marker);
      } catch (e, st) {
        logger.error('Failed to add room marker', tag: 'AR', error: e, stackTrace: st);
      }
    }
  }

  void _updateDistance() {
    if (_disposed || !mounted || _destWorld == null) return;
    // Get latest camera pose for accurate distance
    () async {
      final camPose = await sessionManager?.getCameraPose();
      if (camPose == null) return;
      final camPos = camPose.getTranslation();
      
      // Project both points to ground plane for true walking distance
      final dx = _destWorld!.x - camPos.x;
      final dz = _destWorld!.z - camPos.z;
      currentDistance = math.sqrt(dx * dx + dz * dz);
      
      if (mounted && !_disposed) {
        setState(() {});
        if (!_arrivalNotified && currentDistance <= _arrivalThresholdMeters) {
          _arrivalNotified = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Arrived at ${widget.destinationCode}!')),
          );
        }
      }
    }();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _gpsUpdateTimer?.cancel();
    _arrowUpdateTimer?.cancel();
    locationManager?.stopLocationUpdates();

    logger.info('Disposing ARNavigateView', tag: 'AR');

    // Dispose AR session on platform side to stop camera / sensors / rendering threads.
    // Do not await to avoid blocking Flutter UI teardown.
    unawaited(() async {
      try {
        await sessionManager?.dispose();
      } catch (e, st) {
        logger.error('ARSessionManager.dispose failed', tag: 'AR', error: e, stackTrace: st);
      }
    }());

    // Clean up user marker
    if (_userMarker != null) {
      try { objectManager?.removeNode(_userMarker!); } catch (_) {}
      _userMarker = null;
    }

    // Clean up direction arrow
    if (_directionArrow != null) {
      try { objectManager?.removeNode(_directionArrow!); } catch (_) {}
      _directionArrow = null;
    }

    // Clean up room markers
    for (final marker in _roomMarkers) {
      try { objectManager?.removeNode(marker); } catch (_) {}
    }
    _roomMarkers.clear();

    sessionManager = null;
    objectManager = null;
    anchorManager = null;
    locationManager = null;

    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Navigate to ${widget.destinationCode}')),
      body: Stack(
        children: [
          ARView(
            onARViewCreated: onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(originSet ? 'Tap floor to reset origin' : 'Tap floor to set origin'),
                  if (originSet) 
                    Text('${currentDistance.toStringAsFixed(1)} m to ${widget.destinationCode}') 
                  else 
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
