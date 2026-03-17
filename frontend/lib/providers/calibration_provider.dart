import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class CalibrationProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  
  Map<String, dynamic>? _cameraMatrix;
  bool _isLoading = false;
  String _errorMessage = '';

  Map<String, dynamic>? get cameraMatrix => _cameraMatrix;
  bool get hasCalibrated => _cameraMatrix != null;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;

  CalibrationProvider() {
    _loadMatrixFromPrefs();
  }

  Future<void> _loadMatrixFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('camera_matrix');
    if (jsonStr != null) {
      try {
        _cameraMatrix = jsonDecode(jsonStr);
      } catch (e) {
        _cameraMatrix = null;
      }
    }
    notifyListeners();
  }

  Future<bool> calibrateCamera(List<File> images, {void Function(double progress)? onProgress}) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final response = await _apiService.uploadCalibrationImages(
        images: images,
        onProgress: onProgress,
      );

      if (response['success'] == true && response['camera_matrix'] != null) {
        _cameraMatrix = response['camera_matrix'];
        
        // Save locally
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('camera_matrix', jsonEncode(_cameraMatrix));
        
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = response['message'] ?? 'Calibration validation failed';
      }
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    }
    
    _isLoading = false;
    notifyListeners();
    return false;
  }
  
  String? get cameraMatrixJson {
    if (_cameraMatrix == null) return null;
    return jsonEncode(_cameraMatrix);
  }
}
