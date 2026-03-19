import 'dart:io';
import 'package:dio/dio.dart';
import '../core/constants.dart';

class ApiService {
  late final Dio _dio;

  ApiService() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
      sendTimeout: const Duration(seconds: 120),
    ));
  }

  /// Health check – returns true if the backend is reachable
  Future<bool> healthCheck() async {
    try {
      final response = await _dio.get('health');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Upload images to the backend for pothole detection.
  ///
  /// [images] – list of image files
  /// [lat], [lng] – GPS coordinates
  /// [userId] – current user UID
  /// [firestoreDocId] – Firestore document ID for status tracking
  /// [onProgress] – optional upload progress callback (0.0 – 1.0)
  Future<Map<String, dynamic>> detectBatch({
    required List<File> images,
    required double lat,
    required double lng,
    required String userId,
    required String firestoreDocId,
    String? cameraMatrixJson,
    void Function(double progress)? onProgress,
  }) async {
    final formData = FormData();

    for (final image in images) {
      formData.files.add(MapEntry(
        'files',
        await MultipartFile.fromFile(image.path,
            filename: image.path.split(Platform.pathSeparator).last),
      ));
    }

    formData.fields.addAll([
      MapEntry('lat', lat.toString()),
      MapEntry('lng', lng.toString()),
      MapEntry('user_id', userId),
      MapEntry('firestore_doc_id', firestoreDocId),
      if (cameraMatrixJson != null) MapEntry('camera_matrix', cameraMatrixJson),
    ]);

    final response = await _dio.post(
      'detect_batch',
      data: formData,
      options: Options(validateStatus: (status) => status != null && status < 500),
      onSendProgress: (sent, total) {
        if (onProgress != null && total > 0) {
          onProgress(sent / total);
        }
      },
    );

    if (response.statusCode == 200) {
      return response.data as Map<String, dynamic>;
    } else {
      throw Exception(response.data?['message'] ?? 'Detection failed');
    }
  }

  /// Upload calibration images to compute intrinsic camera matrix
  Future<Map<String, dynamic>> uploadCalibrationImages({
    required List<File> images,
    void Function(double progress)? onProgress,
  }) async {
    final formData = FormData();

    for (final image in images) {
      formData.files.add(MapEntry(
        'files',
        await MultipartFile.fromFile(image.path,
            filename: image.path.split(Platform.pathSeparator).last),
      ));
    }

    final response = await _dio.post(
      'calibrate',
      data: formData,
      options: Options(validateStatus: (status) => status != null && status < 500),
      onSendProgress: (sent, total) {
        if (onProgress != null && total > 0) {
          onProgress(sent / total);
        }
      },
    );

    if (response.statusCode == 200) {
      return response.data as Map<String, dynamic>;
    } else {
      throw Exception(response.data?['message'] ?? 'Calibration failed');
    }
  }

  /// Update the base URL at runtime (e.g., user settings)
  void updateBaseUrl(String newBaseUrl) {
    _dio.options.baseUrl = newBaseUrl;
  }
}
