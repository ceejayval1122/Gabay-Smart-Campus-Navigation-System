import 'package:flutter/material.dart';
import '../../services/booking_service.dart';
import '../../models/booking.dart';

class BookingManagementScreen extends StatelessWidget {
  const BookingManagementScreen({super.key});

  Future<void> _showConfirmation(
    BuildContext context, {
    required String title,
    required String content,
    required String confirmText,
    required VoidCallback onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onConfirm();
    }
  }

  void _handleAction(
    BuildContext context, {
    required Future<void> Function() action,
    required String successMessage,
    required String errorMessage,
  }) async {
    try {
      await action();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$errorMessage: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Bookings'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: StreamBuilder<List<Booking>>(
                stream: BookingService.instance.streamAll(),
                builder: (context, snapshot) {
                  final bookings = snapshot.data ?? const <Booking>[];
                  if (bookings.isEmpty) {
                    return const Center(
                      child: Text('No bookings yet', style: TextStyle(color: Colors.white70)),
                    );
                  }
                  return ListView.separated(
                    itemCount: bookings.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final b = bookings[i];
                      final statusColor = {
                        'pending': Colors.amber,
                        'approved': Colors.lightGreenAccent,
                        'declined': Colors.redAccent,
                        'rejected': Colors.redAccent,
                      }[b.status] ?? Colors.white70;
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.12)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: statusColor.withOpacity(0.6)),
                                  ),
                                  child: Text(b.status.toUpperCase(), style: TextStyle(color: statusColor, fontWeight: FontWeight.w700)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${b.facility} • ${_fmtDate(b.date)} • ${b.startTime}-${b.endTime}',
                                    style: const TextStyle(color: Colors.white),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('Purpose: ${b.purpose}', style: const TextStyle(color: Colors.white70)),
                            if (b.attendees != null) Text('Attendees: ${b.attendees}', style: const TextStyle(color: Colors.white70)),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                TextButton.icon(
                                  onPressed: b.status == 'approved'
                                      ? null
                                      : () => _showConfirmation(
                                            context,
                                            title: 'Approve Booking',
                                            content: 'Approve booking for ${b.facility} on ${_fmtDate(b.date)}?',
                                            confirmText: 'Approve',
                                            onConfirm: () => _handleAction(
                                              context,
                                              action: () => BookingService.instance.updateStatus(b.id, 'approved'),
                                              successMessage: 'Booking approved',
                                              errorMessage: 'Failed to approve booking',
                                            ),
                                          ),
                                  icon: const Icon(Icons.check_circle, color: Colors.white),
                                  label: const Text('Approve', style: TextStyle(color: Colors.white)),
                                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                                ),
                                TextButton.icon(
                                  onPressed: (b.status == 'declined' || b.status == 'rejected')
                                      ? null
                                      : () => _showConfirmation(
                                            context,
                                            title: 'Decline Booking',
                                            content: 'Decline booking for ${b.facility} on ${_fmtDate(b.date)}?',
                                            confirmText: 'Decline',
                                            onConfirm: () => _handleAction(
                                              context,
                                              action: () => BookingService.instance.updateStatus(b.id, 'rejected'),
                                              successMessage: 'Booking declined',
                                              errorMessage: 'Failed to decline booking',
                                            ),
                                          ),
                                  icon: const Icon(Icons.cancel, color: Colors.white),
                                  label: const Text('Decline', style: TextStyle(color: Colors.white)),
                                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  onPressed: () => _showConfirmation(
                                    context,
                                    title: 'Delete Booking',
                                    content: 'Permanently delete this booking?',
                                    confirmText: 'Delete',
                                    onConfirm: () => _handleAction(
                                      context,
                                      action: () => BookingService.instance.delete(b.id),
                                      successMessage: 'Booking deleted',
                                      errorMessage: 'Failed to delete booking',
                                    ),
                                  ),
                                  icon: const Icon(Icons.delete_outline, color: Colors.white70),
                                ),
                              ],
                            )
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
