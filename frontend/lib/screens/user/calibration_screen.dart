import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../../providers/calibration_provider.dart';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  final List<File> _capturedImages = [];
  bool _isInitializing = true;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _controller = CameraController(
          _cameras![0], // Back camera
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _controller!.initialize();
        if (!mounted) return;
        setState(() {
          _isInitializing = false;
        });
      } else {
        setState(() {
          _errorMessage = "No cameras found.";
          _isInitializing = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Camera permissions denied or failed to initialize.";
        _isInitializing = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _captureImage() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_capturedImages.length >= 20 || _isUploading) return;

    try {
      final XFile file = await _controller!.takePicture();
      setState(() {
        _capturedImages.add(File(file.path));
      });

      if (_capturedImages.length == 20) {
        _submitCalibration();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _submitCalibration() async {
    setState(() {
      _isUploading = true;
    });

    final provider = context.read<CalibrationProvider>();
    final success = await provider.calibrateCamera(
      _capturedImages,
      onProgress: (progress) {
        setState(() {
          _uploadProgress = progress;
        });
      },
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Calibration successful!'), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    } else {
      setState(() {
        _isUploading = false;
      });
      showDialog(context: context, builder: (c) => AlertDialog(
        title: const Text("Calibration Failed"),
        content: Text(provider.errorMessage),
        actions: [
          TextButton(onPressed: () {
             Navigator.pop(c);
             setState(() => _capturedImages.clear());
          }, child: const Text("Try Again", style: TextStyle(color: Colors.blue)))
        ],
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Camera Calibration')),
        body: Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red))),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Camera Calibration')),
      body: Column(
        children: [
          Container(
             padding: const EdgeInsets.all(16),
             color: Colors.blue.shade50,
             child: const Row(
               children: [
                 Icon(Icons.pattern, color: Colors.blue),
                 SizedBox(width: 12),
                 Expanded(
                   child: Text('Capture 20 images of a printed 9x6 chessboard from different angles and distances. Ensure the entire pattern is visible.'),
                 )
               ]
             )
          ),
          Expanded(
            child: _isUploading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text('Uploading... ${(_uploadProgress * 100).toInt()}%', style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 8),
                        const Text('Calculating intrinsic parameters... please wait.', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        color: Colors.black,
                        width: double.infinity,
                        height: double.infinity,
                        child: CameraPreview(_controller!),
                      ),
                      Positioned(
                        bottom: 24,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(30)),
                          child: Text(
                            '${_capturedImages.length} / 20 Captured',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      )
                    ],
                  ),
          ),
          if (!_isUploading)
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              padding: const EdgeInsets.all(24.0),
              child: FloatingActionButton.large(
                 onPressed: _captureImage,
                 backgroundColor: Colors.blue,
                 child: const Icon(Icons.camera, color: Colors.white, size: 36),
              ),
            )
        ],
      ),
    );
  }
}
