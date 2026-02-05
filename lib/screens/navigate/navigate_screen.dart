import 'dart:ui';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../repositories/profiles_repository.dart';
import '../../widgets/glass_container.dart';
import 'ar_navigate_view.dart';
import 'qr_start_screen.dart';
import 'custom_destination_screen.dart';
import 'room_coordinates_screen.dart';
import 'admin_settings_screen.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../../navigation/qr_marker_service.dart';
import '../../navigation/map_data.dart';
import '../../core/debug_logger.dart';

class NavigateScreen extends StatefulWidget {
  const NavigateScreen({super.key});

  @override
  State<NavigateScreen> createState() => _NavigateScreenState();
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFF63C1E3).withOpacity(0.9) : Colors.white.withOpacity(0.08);
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

class _NavigateScreenState extends State<NavigateScreen> {
  // Using AR-only mock UI for now (frontend-first)
  String? _selectedDestination;
  bool _isAdmin = false;
  StreamSubscription<AuthState>? _authSub;

  static const MethodChannel _arCoreChannel = MethodChannel('com.example.gabay/arcore');

  bool get _isArSupportedPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<bool> _isArCoreReady() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    // If the platform channel isn't available for some reason, fail closed to avoid native crashes.
    try {
      // ARCore availability can be transient; re-check a few times.
      for (int i = 0; i < 3; i++) {
        final status = await _arCoreChannel.invokeMethod<String>('checkArCoreAvailability');
        logger.info('ARCore availability check', tag: 'Navigate', error: {'status': status, 'attempt': i + 1});

        // Native returns ArCoreApk.Availability enum name.
        // Only allow AR when ARCore is supported AND installed.
        if (status == 'SUPPORTED_INSTALLED') return true;
        if (status == 'UNSUPPORTED_DEVICE_NOT_CAPABLE') return false;
        if (status == 'UNKNOWN_TIMED_OUT') return false;

        // Keep retrying while transient.
        if (status == 'UNKNOWN_CHECKING') {
          await Future.delayed(const Duration(milliseconds: 350));
          continue;
        }

        // Supported but not ready/installed/updated.
        // Treat as not-ready so we don't start ARCore and risk native crashes.
        if (status == 'SUPPORTED_NOT_INSTALLED' || status == 'SUPPORTED_APK_TOO_OLD') {
          return false;
        }

        // Unknown state: fail closed.
        return false;
      }
      return false;
    } catch (e, st) {
      logger.error('ARCore availability check failed', tag: 'Navigate', error: e, stackTrace: st);
      return false;
    }
  }

  Future<bool> _guardArStart({required String room, required String source}) async {
    if (!_isArSupportedPlatform) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AR Navigation is only supported on Android/iOS devices.')),
      );
      return false;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      String? status;
      try {
        status = await _arCoreChannel.invokeMethod<String>('checkArCoreAvailability');
      } catch (e, st) {
        logger.error('ARCore availability check failed (guard)', tag: 'Navigate', error: e, stackTrace: st);
      }

      logger.info('ARCore guard result', tag: 'Navigate', error: {'room': room, 'source': source, 'status': status});

      if (status != 'SUPPORTED_INSTALLED') {
        logger.warning('Blocked AR start; ARCore not ready/installed', tag: 'Navigate', error: {'room': room, 'source': source, 'status': status});
        if (!mounted) return false;
        final msg = (status == 'SUPPORTED_NOT_INSTALLED')
            ? 'Please install/enable Google Play Services for AR (ARCore).'
            : (status == 'SUPPORTED_APK_TOO_OLD')
                ? 'Please update Google Play Services for AR (ARCore).'
                : (status == 'UNSUPPORTED_DEVICE_NOT_CAPABLE')
                    ? 'This device does not support AR navigation.'
                    : 'ARCore is not ready on this device ($status).';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return false;
      }
    } else {
      final ok = await _isArCoreReady();
      if (!ok) {
        logger.warning('Blocked AR start; AR not ready/supported', tag: 'Navigate', error: {'room': room, 'source': source});
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AR is not supported on this device.')),
        );
        return false;
      }
    }

    return true;
  }

  // Mock data categories and rooms (matching map_data.dart)
  final Map<String, List<String>> _mockCategories = {
    'CL Rooms': ['CL 1', 'CL 2', 'CL 3', 'CL 4', 'CL 5', 'CL 6', 'CL 7', 'CL 8', 'CL 9', 'CL 10'],
    'Admin Offices': ['Admin Office 1', 'Admin Office 2', 'Admin Office 3', 'Admin Office 4', 'Admin Office 5'],
  };

  String _activeCategory = 'CL Rooms';

  // Camera controller for real preview
  final MobileScannerController _cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    torchEnabled: false,
    facing: CameraFacing.back,
  );

  @override
  void initState() {
    super.initState();
    _loadAdminStatus();

    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (!mounted) return;
      _loadAdminStatus();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _cameraController.dispose();
    super.dispose();
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
    logger.info('Pausing camera before navigation', tag: 'Navigate', error: {'reason': reason});
    try {
      _cameraController.stop();
    } catch (e, st) {
      logger.warning('Failed to stop camera controller', tag: 'Navigate', error: e, stackTrace: st);
    }

    // Give CameraX a moment to release resources before ARCore tries to open the camera.
    await Future.delayed(const Duration(milliseconds: 250));

    final result = await Navigator.of(context).push<T>(route);

    if (!mounted) return result;
    logger.info('Resuming camera after navigation', tag: 'Navigate', error: {'reason': reason});
    try {
      // ARCore/Filament teardown can take a moment; avoid immediately re-opening the camera.
      await Future.delayed(const Duration(milliseconds: 600));
      _cameraController.start();
    } catch (e, st) {
      logger.warning('Failed to start camera controller', tag: 'Navigate', error: e, stackTrace: st);
    }
    return result;
  }

  Future<void> _startAr(String room) async {
    logger.info('Start AR navigation requested', tag: 'Navigate', error: {'room': room});
    final canStart = await _guardArStart(room: room, source: 'room_tile');
    if (!canStart) return;

    if (!mounted) return;
    setState(() => _selectedDestination = room);
    await _pushRouteWithCameraPaused(
      MaterialPageRoute(
        builder: (_) => ARNavigateView(destinationCode: room),
      ),
      reason: 'start_ar_room_tile',
    );
  }

  Future<void> _scanQr() async {
    final data = await _pushRouteWithCameraPaused<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const QRStartScreen()),
      reason: 'scan_qr',
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
      markerId = (data['markerId'] as String).trim();
    }

    // If a marker ID is present, resolve from backend and merge metadata
    if (markerId != null && markerId.isNotEmpty) {
      try {
        final svc = QrMarkerService();
        final mk = await svc.fetchBySlug(markerId);
        if (mk != null) {
          // Prefer backend metadata when available
          if (mk.position != null) origin = mk.position;
          if (mk.yawDeg != null) yawRad = mk.yawDeg! * math.pi / 180.0;
          if (mk.roomCode != null && (room == null || room!.isEmpty)) room = mk.roomCode;
        }
      } catch (_) {}
    }

    // If only anchor was scanned without room, keep previous selection
    room ??= _selectedDestination ?? 'CL 1';
    setState(() => _selectedDestination = room);

    logger.info('Starting AR navigation from QR', tag: 'Navigate', error: {'room': room, 'markerId': markerId});
    final canStart = await _guardArStart(room: room!, source: 'qr');
    if (!canStart) return;
    await _pushRouteWithCameraPaused(
      MaterialPageRoute(
        builder: (_) => ARNavigateView(
          destinationCode: room!,
          initialOrigin: origin,
          initialYawRad: yawRad,
        ),
      ),
      reason: 'start_ar_from_qr',
    );
  }

  Future<void> _setCustomDestination() async {
    final data = await _pushRouteWithCameraPaused<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const CustomDestinationScreen()),
      reason: 'custom_destination',
    );
    if (data == null) return;

    final name = data['name'] as String;
    final lat = data['lat'] as double;
    final lon = data['lon'] as double;
    final height = data['height'] as double;

    // Store custom destination in runtime map
    kCustomDestinations[name] = vm.Vector3(lon, height, lat); // using lon as X, lat as Z
    setState(() => _selectedDestination = name);

    logger.info('Starting AR navigation to custom destination', tag: 'Navigate', error: data);
    final canStart = await _guardArStart(room: name, source: 'custom');
    if (!canStart) return;
    await _pushRouteWithCameraPaused(
      MaterialPageRoute(
        builder: (_) => ARNavigateView(destinationCode: name),
      ),
      reason: 'start_ar_custom',
    );
  }

  Future<void> _openRoomCoordinates() async {
    // Check if user is admin
    final isAdmin = await _checkIsAdmin();
    if (!isAdmin) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only admin users can set room locations')),
        );
      }
      return;
    }
    
    await _pushRouteWithCameraPaused<void>(
      MaterialPageRoute(builder: (_) => const RoomCoordinatesScreen()),
      reason: 'room_coordinates',
    );
  }

  Future<bool> _checkIsAdmin() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return false;

      final isAdmin = await ProfilesRepository.instance.isCurrentUserAdmin();
      logger.info('Admin check (profiles.is_admin)', tag: 'Navigate', error: {
        'email': user.email,
        'isAdmin': isAdmin,
      });
      return isAdmin;
    } catch (e, st) {
      logger.error('Failed to check admin status', tag: 'Navigate', error: e, stackTrace: st);
      return false;
    }
  }

  Future<void> _openAdminSettings() async {
    await _pushRouteWithCameraPaused<void>(
      MaterialPageRoute(builder: (_) => const AdminSettingsScreen()),
      reason: 'admin_settings',
    );

    // Refresh admin status in case session changed while this screen was open.
    await _loadAdminStatus();
  }

  @override
  void didUpdateWidget(NavigateScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh admin status when returning to this screen
    _loadAdminStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh admin status when dependencies change (e.g., auth state)
    _loadAdminStatus();
  }

  void _openDestinationPicker() async {
    final categories = _mockCategories.keys.toList();
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        String tempCategory = _activeCategory;
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
                    children: const [
                      Text('Select Destination', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                      Icon(Icons.place, color: Colors.white70),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // We need local state to update the list when a chip is tapped
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
                                      child: _CategoryChip(
                                        label: c,
                                        selected: c == tempCategory,
                                        onTap: () => setCategory(c),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: ListView.builder(
                                controller: scrollController,
                                itemCount: _mockCategories[tempCategory]?.length ?? 0,
                                itemBuilder: (context, index) {
                                  final room = _mockCategories[tempCategory]![index];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                    leading: const Icon(Icons.room, color: Colors.white70),
                                    title: Text(room, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                    subtitle: Text('Tap to navigate', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                                    onTap: () => Navigator.of(context).pop(room),
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
        _activeCategory = _mockCategories.entries.firstWhere((e) => e.value.contains(selected)).key;
      });
      if (mounted) {
        logger.info('Starting AR navigation from destination picker', tag: 'Navigate', error: {'room': selected});
        final canStart = await _guardArStart(room: selected, source: 'picker');
        if (!canStart) return;
        await _pushRouteWithCameraPaused(
          MaterialPageRoute(
            builder: (_) => ARNavigateView(destinationCode: selected),
          ),
          reason: 'start_ar_from_picker',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Navigation'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Real camera preview
          Positioned.fill(
            child: MobileScanner(
              controller: _cameraController,
              // No onDetect needed; we only need preview for AR UI
            ),
          ),
          // AR overlay UI on top of the camera
          Positioned.fill(
            child: _ArMockOverlay(
              selectedDestination: _selectedDestination,
              categories: _mockCategories,
              activeCategory: _activeCategory,
              onCategoryChange: (c) => setState(() => _activeCategory = c),
              onSelectRoom: (room) => _startAr(room),
              onOpenPicker: _openDestinationPicker,
              onScanQr: _scanQr,
              onSetCustomDestination: _setCustomDestination,
              onOpenRoomCoordinates: _openRoomCoordinates,
              onOpenAdminSettings: _openAdminSettings,
              onClearDestination: () => setState(() => _selectedDestination = null),
              isAdmin: _isAdmin,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipPill extends StatelessWidget {
  const _ChipPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

class _Background extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF63C1E3), Color(0xFF1E2931)],
            ),
          ),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
          child: Container(color: Colors.black.withOpacity(0)),
        ),
      ],
    );
  }
}

class _ArMockOverlay extends StatelessWidget {
  const _ArMockOverlay({
    this.selectedDestination,
    required this.categories,
    required this.activeCategory,
    required this.onCategoryChange,
    required this.onSelectRoom,
    required this.onOpenPicker,
    required this.onScanQr,
    required this.onSetCustomDestination,
    required this.onOpenRoomCoordinates,
    required this.onOpenAdminSettings,
    required this.onClearDestination,
    required this.isAdmin,
  });

  final String? selectedDestination;
  final Map<String, List<String>> categories;
  final String activeCategory;
  final ValueChanged<String> onCategoryChange;
  final ValueChanged<String> onSelectRoom;
  final VoidCallback onOpenPicker;
  final VoidCallback onScanQr;
  final VoidCallback onSetCustomDestination;
  final VoidCallback onOpenRoomCoordinates;
  final VoidCallback onOpenAdminSettings;
  final VoidCallback onClearDestination;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final rooms = categories[activeCategory] ?? const <String>[];
    return Stack(
      fit: StackFit.expand,
      children: [
        // Transparent layer over the real camera
        // Direction arrow
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.keyboard_arrow_up_rounded, size: 80, color: Color(0xFF63C1E3)),
              const SizedBox(height: 6),
              Text(
                selectedDestination == null ? 'Pick a destination' : 'Head straight for 20m',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        // In-camera top controls: category chips and rooms row
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row with Browse, Scan QR, Custom, Set Rooms (admin only), Admin, and Clear
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        GlassContainer(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: InkWell(
                            onTap: onOpenPicker,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.list, color: Colors.white, size: 16),
                                SizedBox(width: 6),
                                Text('Browse', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GlassContainer(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: InkWell(
                            onTap: onScanQr,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.qr_code_scanner, color: Colors.white, size: 16),
                                SizedBox(width: 6),
                                Text('Scan QR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GlassContainer(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: InkWell(
                            onTap: onSetCustomDestination,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.edit_location, color: Colors.white, size: 16),
                                SizedBox(width: 6),
                                Text('Custom', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                        // Only show Set Rooms for admin users
                        if (isAdmin) ...[
                          const SizedBox(width: 8),
                          GlassContainer(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: InkWell(
                              onTap: onOpenRoomCoordinates,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.room_preferences, color: Colors.white, size: 16),
                                  SizedBox(width: 6),
                                  Text('Set Rooms', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        GlassContainer(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: InkWell(
                            onTap: onOpenAdminSettings,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.admin_panel_settings, color: Colors.white, size: 16),
                                SizedBox(width: 6),
                                Text('Admin', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (selectedDestination != null)
                          GlassContainer(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: InkWell(
                              onTap: onClearDestination,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.clear, color: Colors.white, size: 16),
                                  SizedBox(width: 6),
                                  Text('Clear', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Category chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final c in categories.keys)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: _CategoryChip(
                              label: c,
                              selected: c == activeCategory,
                              onTap: () => onCategoryChange(c),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Rooms quick select for active category
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final r in rooms)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: GlassContainer(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: InkWell(
                                onTap: () => onSelectRoom(r),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      selectedDestination == r ? Icons.check_circle : Icons.navigation,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(r, style: const TextStyle(color: Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
