import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../debug/debug_screen.dart';
import '../../core/debug_logger.dart';

class CustomDestinationScreen extends StatefulWidget {
  const CustomDestinationScreen({super.key});

  @override
  State<CustomDestinationScreen> createState() => _CustomDestinationScreenState();
}

class _CustomDestinationScreenState extends State<CustomDestinationScreen> {
  final _nameController = TextEditingController();
  final _latController = TextEditingController();
  final _lonController = TextEditingController();
  final _heightController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _latController.dispose();
    _lonController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final lat = double.tryParse(_latController.text);
    final lon = double.tryParse(_lonController.text);
    final height = double.tryParse(_heightController.text) ?? 0.0;

    if (name.isEmpty || lat == null || lon == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in name, latitude, and longitude')),
      );
      return;
    }

    final result = {
      'name': name,
      'lat': lat,
      'lon': lon,
      'height': height,
    };
    logger.info('Custom destination set', tag: 'CustomDest', error: result);
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set Custom Destination')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Destination Name'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _latController,
              decoration: const InputDecoration(labelText: 'Latitude'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lonController,
              decoration: const InputDecoration(labelText: 'Longitude'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _heightController,
              decoration: const InputDecoration(labelText: 'Height (meters, optional)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _submit, child: const Text('Set Destination')),
            ),
          ],
        ),
      ),
    );
  }
}
