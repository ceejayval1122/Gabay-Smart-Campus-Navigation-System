import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../navigation/map_data.dart';
import '../../navigation/room_coordinates_service.dart';
import '../../core/debug_logger.dart';

class RoomCoordinatesScreen extends StatefulWidget {
  const RoomCoordinatesScreen({super.key});

  @override
  State<RoomCoordinatesScreen> createState() => _RoomCoordinatesScreenState();
}

class _RoomCoordinatesScreenState extends State<RoomCoordinatesScreen> {
  final Map<String, TextEditingController> _nameControllers = {};
  final Map<String, TextEditingController> _latControllers = {};
  final Map<String, TextEditingController> _lonControllers = {};
  final Map<String, TextEditingController> _heightControllers = {};
  final Map<String, TextEditingController> _floorControllers = {};

  @override
  void initState() {
    super.initState();
    _loadCoordinates();
  }

  Future<void> _loadCoordinates() async {
    final svc = RoomCoordinatesService();
    await svc.loadCoordinates(force: true);
    
    // Initialize controllers for all predefined rooms
    for (final room in kRoomToWaypoint.keys) {
      _nameControllers[room] = TextEditingController(text: room);
      final existing = svc.getCoordinates(room);
      final existingFloor = svc.getFloor(room);
      _latControllers[room] = TextEditingController(text: existing?.z.toString() ?? '');
      _lonControllers[room] = TextEditingController(text: existing?.x.toString() ?? '');
      _heightControllers[room] = TextEditingController(text: existing?.y.toString() ?? '');
      _floorControllers[room] = TextEditingController(text: existingFloor?.toString() ?? '');
    }
    setState(() {});
  }

  Future<void> _saveCoordinates() async {
    final svc = RoomCoordinatesService();
    try {
      for (final room in kRoomToWaypoint.keys) {
        final latText = _latControllers[room]?.text.trim() ?? '';
        final lonText = _lonControllers[room]?.text.trim() ?? '';
        final heightText = _heightControllers[room]?.text.trim() ?? '';
        final floorText = _floorControllers[room]?.text.trim() ?? '';

        if (latText.isEmpty && lonText.isEmpty) {
          await svc.clearCoordinates(room);
          continue;
        }

        final lat = double.tryParse(latText);
        final lon = double.tryParse(lonText);
        if (lat == null || lon == null) continue;

        final height = double.tryParse(heightText) ?? 0.0;
        final floor = int.tryParse(floorText) ?? 1;

        await svc.upsertCoordinates(
          roomCode: room,
          lat: lat,
          lon: lon,
          height: height,
          floor: floor,
        );
      }

      await svc.loadCoordinates(force: true);

      logger.info('Room coordinates saved', tag: 'RoomCoords');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Room coordinates saved')),
        );
      }
    } catch (e, st) {
      logger.error('Failed to save room coordinates', tag: 'RoomCoords', error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save coordinates: $e')),
        );
      }
    }
  }

  Future<void> _useCurrentLocation(String room) async {
    // Request location permission
    final status = await Permission.location.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required')),
        );
      }
      return;
    }

    try {
      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // Update the text controllers
      _latControllers[room]?.text = position.latitude.toStringAsFixed(6);
      _lonControllers[room]?.text = position.longitude.toStringAsFixed(6);
      
      // Estimate height based on floor if not set
      if (_heightControllers[room]?.text.isEmpty == true) {
        final floor = int.tryParse(_floorControllers[room]?.text ?? '') ?? 1;
        final estimatedHeight = (floor - 1) * 3.0; // Roughly 3 meters per floor
        _heightControllers[room]?.text = estimatedHeight.toStringAsFixed(1);
      }

      logger.info('Current location set for room', tag: 'RoomCoords', error: {
        'room': room,
        'lat': position.latitude,
        'lon': position.longitude,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Current location set for $room')),
        );
      }
    } catch (e, st) {
      logger.error('Failed to get current location', tag: 'RoomCoords', error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to get current location')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Room Locations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveCoordinates,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Set GPS coordinates for each room. Leave fields empty to use default locations.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ...kRoomToWaypoint.keys.map((room) => _buildRoomCard(room)),
        ],
      ),
    );
  }

  Widget _buildRoomCard(String room) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  room,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: () => _useCurrentLocation(room),
                  icon: const Icon(Icons.my_location, size: 16),
                  label: const Text('Use Current Location', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Use a more compact layout to prevent overflow
            Column(
              children: [
                TextField(
                  controller: _latControllers[room],
                  decoration: const InputDecoration(
                    labelText: 'Latitude',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _lonControllers[room],
                  decoration: const InputDecoration(
                    labelText: 'Longitude',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _heightControllers[room],
                        decoration: const InputDecoration(
                          labelText: 'Height (m)',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _floorControllers[room],
                        decoration: const InputDecoration(
                          labelText: 'Floor',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
