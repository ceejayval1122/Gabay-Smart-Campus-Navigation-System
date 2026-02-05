import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/debug_logger.dart';
import '../../repositories/profiles_repository.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadAdminStatus();
  }

  Future<void> _loadAdminStatus() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      
      if (user == null) {
        setState(() {
          _isAdmin = false;
        });
        return;
      }
      
      final isAdmin = await ProfilesRepository.instance.isCurrentUserAdmin();
      setState(() {
        _isAdmin = isAdmin;
      });
      
      logger.info('Admin status loaded', tag: 'Admin', error: {
        'email': user.email,
        'isAdmin': isAdmin,
      });
    } catch (e, st) {
      logger.error('Failed to load admin status', tag: 'Admin', error: e, stackTrace: st);
      setState(() {
        _isAdmin = false;
      });
    }
  }

  Future<void> _toggleAdmin(bool value) async {
    // Admin status is now based on Supabase authentication, not toggleable
    // This function is kept for compatibility but doesn't actually change anything
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No authenticated user')),
        );
      }
      return;
    }
    
    final actualIsAdmin = user.email == 'admin@seait.edu';
    
    logger.info('Admin status checked (read-only)', tag: 'Admin', error: {
      'email': user.email,
      'actualIsAdmin': actualIsAdmin,
      'attemptedValue': value,
    });
    
    if (mounted) {
      if (actualIsAdmin) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin access granted (admin@seait.edu)')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Regular user access (${user.email})')),
        );
      }
      Navigator.of(context).pop(); // Go back to refresh the parent
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Admin Access',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isAdmin ? 'Logged in as admin@seait.edu' : 'Regular user access',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Admin Status'),
                    subtitle: Text(_isAdmin ? 'Admin access granted' : 'Regular user access'),
                    value: _isAdmin,
                    onChanged: null, // Read-only - based on Supabase authentication
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadAdminStatus,
                    child: const Text('Refresh Admin Status'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Debug: $_isAdmin',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Admin Features',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildFeatureItem('Set Room Locations', 'Assign GPS coordinates to rooms'),
                  _buildFeatureItem('Manage Destinations', 'Add/edit navigation destinations'),
                  _buildFeatureItem('System Settings', 'Configure app-wide settings'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(String title, String description) {
    final isEnabled = _isAdmin;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isEnabled ? Icons.check_circle : Icons.lock,
            color: isEnabled ? Colors.green : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isEnabled ? Colors.black : Colors.grey,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: isEnabled ? Colors.grey.shade600 : Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
