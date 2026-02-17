import 'dart:ui';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/glass_container.dart';
import '../../models/room.dart';
import '../../repositories/profiles_repository.dart';
import '../../services/room_service.dart';
import '../navigate/ar_navigate_view.dart';
import '../navigate/qr_start_screen.dart';
import '../navigate/custom_destination_screen.dart';
import '../navigate/room_coordinates_screen.dart';
import '../navigate/admin_settings_screen.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../navigation/qr_marker_service.dart';
import '../../navigation/map_data.dart';
import '../../core/debug_logger.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  static const Color _appAccent = Color(0xFF63C1E3);
  String _incident = 'Idle'; // Idle | Fire | Earthquake | Other
  bool _guiding = false;
  String? _selectedDestination;
  bool _isAdmin = false;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<List<Room>>? _roomsSub;
  List<Room> _managedRooms = const <Room>[];

  // Camera controller for AR-only preview
  final MobileScannerController _cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    torchEnabled: false,
    facing: CameraFacing.back,
  );

  static const MethodChannel _arCoreChannel = MethodChannel('com.example.gabay/arcore');

  bool get _isArSupportedPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<bool> _isArCoreReady() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    try {
      for (int i = 0; i < 3; i++) {
        final status = await _arCoreChannel.invokeMethod<String>('checkArCoreAvailability');
        logger.info('ARCore availability check', tag: 'Emergency', error: {'status': status, 'attempt': i + 1});

        if (status == 'SUPPORTED_INSTALLED') return true;
        if (status == 'UNSUPPORTED_DEVICE_NOT_CAPABLE') return false;
        if (status == 'UNKNOWN_TIMED_OUT') return false;

        if (status == 'UNKNOWN_CHECKING') {
          await Future.delayed(const Duration(milliseconds: 350));
          continue;
        }

        if (status == 'SUPPORTED_NOT_INSTALLED' || status == 'SUPPORTED_APK_TOO_OLD') {
          return false;
        }

        return false;
      }
    } catch (e, st) {
      logger.warning('ARCore availability check failed', tag: 'Emergency', error: e, stackTrace: st);
      return false;
    }
    return false;
  }

  bool _isExit(Room r) {
    final s = '${r.name} ${r.code}'.toLowerCase();
    return s.contains('exit');
  }

  bool _isSafeArea(Room r) {
    final s = '${r.name} ${r.code}'.toLowerCase();
    return s.contains('safe') || s.contains('assembly');
  }

  // Emergency destinations (exits and safe areas)
  Map<String, List<Room>> get _emergencyDestinations => {
    'Exits': _managedRooms.where(_isExit).toList(),
    'Safe Areas': _managedRooms.where(_isSafeArea).toList(),
    'All Rooms': _managedRooms,
  };

  String _activeEmergencyCategory = 'Exits';

  @override
  void initState() {
    super.initState();
    _loadAdminStatus();
    _subscribeManagedRooms();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _roomsSub?.cancel();
    _cameraController.dispose();
    super.dispose();
  }

  void _subscribeManagedRooms() {
    _roomsSub?.cancel();
    try {
      _roomsSub = RoomService.instance.streamAll().listen(
        (rooms) {
          if (mounted) {
            final list = rooms.toList()
              ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
            setState(() => _managedRooms = list);
          }
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  Future<void> _loadAdminStatus() async {
    final isAdmin = await _checkIsAdmin();
    if (mounted) {
      setState(() {
        _isAdmin = isAdmin;
      });
    }
  }

  Future<T?> _pushRouteWithCameraPaused<T>(Route<T> route, {required String reason}) async {
    logger.info('Pausing camera before navigation', tag: 'Emergency', error: {'reason': reason});
    try {
      _cameraController.stop();
    } catch (e, st) {
      logger.warning('Failed to stop camera controller', tag: 'Emergency', error: e, stackTrace: st);
    }

    await Future.delayed(const Duration(milliseconds: 250));

    final result = await Navigator.of(context).push<T>(route);

    if (!mounted) return result;
    logger.info('Resuming camera after navigation', tag: 'Emergency', error: {'reason': reason});
    try {
      await Future.delayed(const Duration(milliseconds: 600));
      _cameraController.start();
    } catch (e, st) {
      logger.warning('Failed to start camera controller', tag: 'Emergency', error: e, stackTrace: st);
    }
    return result;
  }

  Future<void> _startAr(String room) async {
    logger.info('Start AR navigation requested', tag: 'Emergency', error: {'room': room});
    final canStart = await _guardArStart(room: room, source: 'emergency_room_tile');
    if (!canStart) return;

    if (!mounted) return;
    setState(() => _selectedDestination = room);
    await _pushRouteWithCameraPaused(
      MaterialPageRoute(
        builder: (_) => ARNavigateView(destinationCode: room),
      ),
      reason: 'start_ar_emergency',
    );
  }

  Future<void> _scanQr() async {
    final data = await _pushRouteWithCameraPaused<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const QRStartScreen()),
      reason: 'scan_qr_emergency',
    );
    if (data == null) return;

    String? room;
    vm.Vector3? origin;
    double? yawRad;
    String? markerId;

    if (data.containsKey('room')) {
      room = data['room'] as String?;
    }
    if (data.containsKey('pos')) {
      final pos = (data['pos'] as List).cast<double>();
      origin = vm.Vector3(pos[0], pos[1], pos[2]);
    }
    if (data.containsKey('yawDeg')) {
      final deg = data['yawDeg'] as double;
      yawRad = deg * math.pi / 180.0;
    }
    if (data.containsKey('markerId')) {
      markerId = (data['markerId'] as String?)?.trim();
    }

    if (markerId != null && markerId.isNotEmpty) {
      try {
        final svc = QrMarkerService();
        final mk = await svc.fetchBySlug(markerId);
        if (mk != null) {
          if (mk.position != null) origin = mk.position;
          if (mk.yawDeg != null) yawRad = mk.yawDeg! * math.pi / 180.0;
          if (mk.roomCode != null && (room == null || room!.isEmpty)) room = mk.roomCode;
        }
      } catch (_) {}
    }

    room ??= _selectedDestination ?? 'CL 1';
    setState(() => _selectedDestination = room);

    final canStart = await _guardArStart(room: room!, source: 'qr_emergency');
    if (!canStart) return;
    await _pushRouteWithCameraPaused(
      MaterialPageRoute(
        builder: (_) => ARNavigateView(
          destinationCode: room!,
          initialOrigin: origin,
          initialYawRad: yawRad,
        ),
      ),
      reason: 'start_ar_emergency_from_qr',
    );
  }

  Future<bool> _checkIsAdmin() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return false;

      final isAdmin = await ProfilesRepository.instance.isCurrentUserAdmin();
      logger.info('Admin check (profiles.is_admin)', tag: 'Emergency', error: {
        'email': user.email,
        'isAdmin': isAdmin,
      });
      return isAdmin;
    } catch (e, st) {
      logger.error('Failed to check admin status', tag: 'Emergency', error: e, stackTrace: st);
      return false;
    }
  }

  Future<bool> _guardArStart({required String room, required String source}) async {
    if (!_isArSupportedPlatform) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AR navigation is not supported on this device')),
        );
      }
      return false;
    }

    final arReady = await _isArCoreReady();
    if (!arReady) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AR services are not available. Please ensure ARCore is installed and updated.')),
        );
      }
      return false;
    }

    return true;
  }

  void _openEmergencyDestinationPicker() async {
    final categories = _emergencyDestinations.keys.toList();
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        String tempCategory = _activeEmergencyCategory;
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return GlassContainer(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Select Emergency Destination', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                      Icon(Icons.emergency, color: _incidentColor()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: StatefulBuilder(
                      builder: (context, setSheetState) {
                        void setCategory(String c) {
                          setSheetState(() => tempCategory = c);
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final c in categories)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8.0),
                                      child: _EmergencyCategoryChip(
                                        label: c,
                                        selected: c == tempCategory,
                                        onTap: () => setCategory(c),
                                        incidentColor: _incidentColor(),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: ListView.builder(
                                controller: scrollController,
                                itemCount: _emergencyDestinations[tempCategory]?.length ?? 0,
                                itemBuilder: (context, index) {
                                  final room = _emergencyDestinations[tempCategory]![index];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                    leading: Icon(
                                      tempCategory == 'Exits' ? Icons.exit_to_app : 
                                      tempCategory == 'Safe Areas' ? Icons.safety_check : Icons.room,
                                      color: Colors.white70,
                                    ),
                                    title: Text(room.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                    subtitle: Text(room.code, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                                    onTap: () => Navigator.of(context).pop(room.code),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (selected != null && selected.isNotEmpty) {
      setState(() {
        _selectedDestination = selected;
        final matches = _emergencyDestinations.entries.where((e) => e.value.any((r) => r.code == selected)).toList();
        if (matches.isNotEmpty) {
          _activeEmergencyCategory = matches.first.key;
        }
      });
      if (mounted) {
        logger.info('Starting AR navigation from emergency destination picker', tag: 'Emergency', error: {'room': selected});
        final canStart = await _guardArStart(room: selected, source: 'emergency_picker');
        if (!canStart) return;
        await _pushRouteWithCameraPaused(
          MaterialPageRoute(
            builder: (_) => ARNavigateView(destinationCode: selected),
          ),
          reason: 'start_ar_emergency_picker',
        );
      }
    }
  }

  List<String> get _tips {
    switch (_incident) {
      case 'Fire':
        return const [
          'Stay low and cover your nose/mouth.',
          'Do not use elevators.',
          'Check doors for heat before opening.',
        ];
      case 'Earthquake':
        return const [
          'Drop, Cover, and Hold On.',
          'Stay away from windows.',
          'After shaking stops, proceed calmly to nearest exit.',
        ];
      default:
        return const [
          'Remain calm and follow the marked route.',
          'Assist others if safe to do so.',
        ];
    }
  }

  Color _incidentColor() {
    switch (_incident) {
      case 'Fire':
        return const Color(0xFFEF4444);
      case 'Earthquake':
        return const Color(0xFFF59E0B);
      default:
        return _appAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Emergency'),
        foregroundColor: Colors.white,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.shield_outlined),
          )
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Real camera preview
          Positioned.fill(
            child: MobileScanner(
              controller: _cameraController,
            ),
          ),
          // Emergency AR overlay
          Positioned.fill(
            child: _EmergencyArOverlay(
              incident: _incident,
              tips: _tips,
              accent: _appAccent,
              onIncidentChange: (i) => setState(() => _incident = i),
              selectedDestination: _selectedDestination,
              emergencyDestinations: _emergencyDestinations,
              activeCategory: _activeEmergencyCategory,
              onCategoryChange: (c) => setState(() => _activeEmergencyCategory = c),
              onSelectRoom: (room) => _startAr(room),
              onOpenPicker: _openEmergencyDestinationPicker,
              onScanQr: _scanQr,
              onClearDestination: () => setState(() => _selectedDestination = null),
              incidentColor: _incidentColor(),
            ),
          ),
        ],
      ),
    );
  }
}

// Simple AR route painter: draws a smooth path from bottom center upward to suggest direction
class _ArRoutePainter extends CustomPainter {
  _ArRoutePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final start = Offset(size.width * 0.5, size.height * 0.85);
    final mid1 = Offset(size.width * 0.5, size.height * 0.6);
    final mid2 = Offset(size.width * 0.6, size.height * 0.35);
    final end = Offset(size.width * 0.65, size.height * 0.18);

    path.moveTo(start.dx, start.dy);
    path.cubicTo(
      start.dx, start.dy - 80,
      mid1.dx + 40, mid1.dy - 60,
      mid1.dx + 20, mid1.dy - 40,
    );
    path.quadraticBezierTo(mid2.dx - 10, mid2.dy, end.dx, end.dy);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, stroke);

    // Draw arrow head at end
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    const arrowSize = 10.0;
    final arrowPath = Path();
    arrowPath.moveTo(end.dx, end.dy);
    arrowPath.lineTo(end.dx - arrowSize, end.dy + arrowSize * 1.6);
    arrowPath.lineTo(end.dx + arrowSize, end.dy + arrowSize * 1.6);
    arrowPath.close();
    canvas.drawPath(arrowPath, arrowPaint);

    // Subtle dashed halo
    final dash = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, dash);
  }

  @override
  bool shouldRepaint(covariant _ArRoutePainter oldDelegate) => oldDelegate.color != color;
}

class _EmergencyArOverlay extends StatelessWidget {
  const _EmergencyArOverlay({
    required this.incident,
    required this.tips,
    required this.accent,
    required this.onIncidentChange,
    required this.selectedDestination,
    required this.emergencyDestinations,
    required this.activeCategory,
    required this.onCategoryChange,
    required this.onSelectRoom,
    required this.onOpenPicker,
    required this.onScanQr,
    required this.onClearDestination,
    required this.incidentColor,
  });

  final String incident;
  final List<String> tips;
  final Color accent;
  final ValueChanged<String> onIncidentChange;
  final String? selectedDestination;
  final Map<String, List<Room>> emergencyDestinations;
  final String activeCategory;
  final ValueChanged<String> onCategoryChange;
  final ValueChanged<String> onSelectRoom;
  final VoidCallback onOpenPicker;
  final VoidCallback onScanQr;
  final VoidCallback onClearDestination;
  final Color incidentColor;

  @override
  Widget build(BuildContext context) {
    final rooms = emergencyDestinations[activeCategory] ?? const <Room>[];
    return Stack(
      fit: StackFit.expand,
      children: [
        // Center guidance arrow and text
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.keyboard_arrow_up_rounded, size: 96, color: Colors.white),
              const SizedBox(height: 8),
              Text(
                incident == 'Idle'
                    ? 'Select an incident'
                    : (selectedDestination == null
                        ? 'Pick an emergency destination'
                        : 'Navigating to $selectedDestination...'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              if (selectedDestination != null) ...[
                const SizedBox(height: 6),
                GlassContainer(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.assistant_navigation, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      const Text('Follow AR guidance', style: TextStyle(color: Colors.white)),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: onClearDestination,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.close, color: Colors.white70, size: 16),
                            SizedBox(width: 4),
                            Text('Clear', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ]
            ],
          ),
        ),
        // Incident selector at top
        Positioned(
          top: 80,
          left: 16,
          right: 16,
          child: GlassContainer(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Emergency Type', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _IncidentChip(
                      label: 'Fire',
                      selected: incident == 'Fire',
                      onTap: () => onIncidentChange('Fire'),
                      color: const Color(0xFFEF4444),
                    ),
                    _IncidentChip(
                      label: 'Earthquake',
                      selected: incident == 'Earthquake',
                      onTap: () => onIncidentChange('Earthquake'),
                      color: const Color(0xFFF59E0B),
                    ),
                    _IncidentChip(
                      label: 'Other',
                      selected: incident == 'Other',
                      onTap: () => onIncidentChange('Other'),
                      color: accent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Emergency destination list at bottom
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: GlassContainer(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Emergency Destinations', style: TextStyle(color: incidentColor, fontWeight: FontWeight.w600)),
                    Row(
                      children: [
                        IconButton(
                          onPressed: onScanQr,
                          icon: const Icon(Icons.qr_code_scanner, color: Colors.white70),
                          tooltip: 'Scan QR Code',
                        ),
                        IconButton(
                          onPressed: onOpenPicker,
                          icon: const Icon(Icons.list, color: Colors.white70),
                          tooltip: 'Show All Destinations',
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Category chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: emergencyDestinations.keys.map((category) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _EmergencyCategoryChip(
                          label: category,
                          selected: category == activeCategory,
                          onTap: () => onCategoryChange(category),
                          incidentColor: incidentColor,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                // Room list
                if (rooms.isEmpty)
                  const Text('No destinations available', style: TextStyle(color: Colors.white70))
                else
                  Column(
                    children: rooms.take(3).map((room) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          activeCategory == 'Exits' ? Icons.exit_to_app : 
                          activeCategory == 'Safe Areas' ? Icons.safety_check : Icons.room,
                          color: Colors.white70,
                          size: 20,
                        ),
                        title: Text(room.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
                        onTap: () => onSelectRoom(room.code),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
        // Tips button
        Positioned(
          top: 80,
          right: 16,
          child: IconButton(
            onPressed: () => showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (_) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Wrap(
                    children: [
                      GlassContainer(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Safety Tips', style: TextStyle(color: incidentColor, fontWeight: FontWeight.w700, fontSize: 16)),
                            const SizedBox(height: 8),
                            for (final t in tips.take(3)) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.info_outline, color: Colors.white70),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(t, style: const TextStyle(color: Colors.white))),
                                ],
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            icon: const Icon(Icons.info_outline, color: Colors.white70),
            tooltip: 'Safety Tips',
          ),
        ),
      ],
    );
  }
}

class _IncidentChip extends StatelessWidget {
  const _IncidentChip({required this.label, required this.selected, required this.color, required this.onTap});
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color tint = selected ? color : Colors.white.withOpacity(0.2);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: tint.withOpacity(0.15),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: selected ? color : Colors.white54, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _EmergencyCategoryChip extends StatelessWidget {
  const _EmergencyCategoryChip({required this.label, required this.selected, required this.onTap, required this.incidentColor});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color incidentColor;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? incidentColor.withOpacity(0.9) : Colors.white.withOpacity(0.08);
    final fg = selected ? Colors.white : Colors.white.withOpacity(0.85);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
