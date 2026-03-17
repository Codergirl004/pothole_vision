import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pothole_provider.dart';
import '../../providers/calibration_provider.dart';
import '../../widgets/image_preview.dart';
import '../../widgets/loading_indicator.dart';
import '../../utils/image_utils.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<File> _selectedImages = [];
  Position? _currentPosition;
  bool _gettingLocation = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _gettingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable location services')),
          );
        }
        setState(() => _gettingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _gettingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _gettingLocation = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      setState(() {
        _currentPosition = position;
        _gettingLocation = false;
      });
    } catch (e) {
      setState(() => _gettingLocation = false);
    }
  }

  Future<void> _pickFromCamera() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (photo != null) {
      setState(() => _selectedImages.add(File(photo.path)));
    }
  }

  Future<void> _pickFromGallery() async {
    final List<XFile> photos = await _picker.pickMultiImage(
      imageQuality: 85,
    );
    if (photos.isNotEmpty) {
      setState(() {
        _selectedImages.addAll(photos.map((x) => File(x.path)));
      });
    }
  }

  void _removeImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  Future<void> _upload() async {
    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one image')),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final potholeProvider = context.read<PotholeProvider>();
    final calibrationProvider = context.read<CalibrationProvider>();

    // Use current position or default
    final lat = _currentPosition?.latitude ?? 0.0;
    final lng = _currentPosition?.longitude ?? 0.0;

    // Compress images before upload
    final compressed = await ImageUtils.compressImages(_selectedImages);

    final success = await potholeProvider.uploadImages(
      images: compressed,
      lat: lat,
      lng: lng,
      userId: auth.userModel?.uid ?? '',
      cameraMatrixJson: calibrationProvider.cameraMatrixJson,
    );

    if (success && mounted) {
      setState(() => _selectedImages.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Upload successful! Check your reports.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      // Reset upload state after a delay
      Future.delayed(const Duration(seconds: 2), () {
        potholeProvider.resetUpload();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final potholeProvider = context.watch<PotholeProvider>();
    final calibrationProvider = context.watch<CalibrationProvider>();

    final isUploading = potholeProvider.uploadStatus == UploadStatus.uploading ||
        potholeProvider.uploadStatus == UploadStatus.analyzing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Pothole'),
        automaticallyImplyLeading: false,
      ),
      body: LoadingOverlay(
        isLoading: isUploading,
        message: potholeProvider.uploadMessage,
        progress: potholeProvider.uploadStatus == UploadStatus.uploading
            ? potholeProvider.uploadProgress
            : null,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!calibrationProvider.hasCalibrated) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'For accurate real-world area & depth estimation, please calibrate your camera under Profile > Camera Calibration.',
                          style: TextStyle(color: Colors.orange, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // ── Location Status ─────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        _currentPosition != null
                            ? Icons.location_on
                            : Icons.location_off,
                        color: _currentPosition != null
                            ? Colors.green
                            : Colors.orange,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _currentPosition != null
                                  ? 'Location captured'
                                  : _gettingLocation
                                      ? 'Getting location...'
                                      : 'Location unavailable',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (_currentPosition != null)
                              Text(
                                '${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600),
                              ),
                          ],
                        ),
                      ),
                      if (_gettingLocation)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        IconButton(
                          onPressed: _getCurrentLocation,
                          icon: const Icon(Icons.refresh, size: 20),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Image Selection ─────────────────
              Text(
                'Select Images',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose multiple photos of the pothole',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickFromCamera,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Camera'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickFromGallery,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // ── Image Preview Grid ──────────────
              ImagePreviewGrid(
                images: _selectedImages,
                onRemove: _removeImage,
              ),

              if (_selectedImages.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${_selectedImages.length} image(s) selected',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // ── Upload Button ───────────────────
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed:
                      (_selectedImages.isEmpty || isUploading) ? null : _upload,
                  icon: const Icon(Icons.cloud_upload_rounded),
                  label: const Text('Upload & Analyze'),
                ),
              ),

              // ── Result Card ─────────────────────
              if (potholeProvider.uploadStatus == UploadStatus.success &&
                  potholeProvider.lastResult != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        'Analysis Complete!',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Potholes processed: ${potholeProvider.lastResult!['potholes_processed'] ?? 0}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      if (potholeProvider.lastResult!['severity'] != null)
                        Text(
                          'Severity: ${potholeProvider.lastResult!['severity']}',
                          style: const TextStyle(fontSize: 14),
                        ),
                    ],
                  ),
                ),
              ],

              // ── Error Message ───────────────────
              if (potholeProvider.uploadStatus == UploadStatus.error) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          potholeProvider.uploadMessage,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
