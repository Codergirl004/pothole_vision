import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/pothole_model.dart';
import '../models/detection_model.dart';
import '../services/firestore_service.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../models/report_model.dart';
enum UploadStatus { idle, uploading, analyzing, success, error }

class PotholeProvider extends ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();

  // ── Upload state ──────────────────────────────────
  UploadStatus _uploadStatus = UploadStatus.idle;
  double _uploadProgress = 0;
  String _uploadMessage = '';
  Map<String, dynamic>? _lastResult;

  UploadStatus get uploadStatus => _uploadStatus;
  double get uploadProgress => _uploadProgress;
  String get uploadMessage => _uploadMessage;
  Map<String, dynamic>? get lastResult => _lastResult;

  // ── Admin potholes ────────────────────────────────
  List<PotholeModel> _adminPotholes = [];
  bool _loadingPotholes = false;

  List<PotholeModel> get adminPotholes => _adminPotholes;
  bool get loadingPotholes => _loadingPotholes;

  // ── Detections ────────────────────────────────────
  List<DetectionModel> _detections = [];
  bool _loadingDetections = false;

  List<DetectionModel> get detections => _detections;
  bool get loadingDetections => _loadingDetections;

  // ── Reports ───────────────────────────────────────
  List<ReportModel> _reports = [];
  bool _loadingReports = false;

  List<ReportModel> get reports => _reports;
  bool get loadingReports => _loadingReports;

  // ═══════════════════════════════════════════════════
  // UPLOAD FLOW
  // ═══════════════════════════════════════════════════

  /// Upload images to the Flask backend for analysis
  Future<bool> uploadImages({
    required List<File> images,
    required double lat,
    required double lng,
    required String userId,
    String? address,
    String? cameraMatrixJson,
    List<Map<String, double>>? locations,
  }) async {
    try {
      _uploadStatus = UploadStatus.uploading;
      _uploadProgress = 0;
      _uploadMessage = 'Creating record...';
      notifyListeners();

      // 1. Create Firestore record first
      final docId = await _firestoreService.createPotholeRecord(
        userId: userId,
        lat: lat,
        lng: lng,
        imageCount: images.length,
        address: address,
      );

      _uploadMessage = 'Uploading images...';
      notifyListeners();

      // 2. Check backend health
      final healthy = await _apiService.healthCheck();
      if (!healthy) {
        _uploadStatus = UploadStatus.error;
        _uploadMessage = 'Server is offline. Please try again later.';
        await _firestoreService.updatePotholeStatus(docId, 'error',
            extra: {'analysisError': 'Server offline'});
        notifyListeners();
        return false;
      }

      _uploadStatus = UploadStatus.analyzing;
      _uploadMessage = 'Analyzing potholes...';
      notifyListeners();

      // 3. Send to backend
      final result = await _apiService.detectBatch(
        images: images,
        lat: lat,
        lng: lng,
        userId: userId,
        firestoreDocId: docId,
        locations: locations,
        cameraMatrixJson: cameraMatrixJson,
        onProgress: (progress) {
          _uploadProgress = progress;
          notifyListeners();
        },
      );

      _lastResult = result;
      _uploadStatus = UploadStatus.success;
      _uploadMessage = 'Analysis complete!';
      notifyListeners();
      return true;
    } catch (e) {
      _uploadStatus = UploadStatus.error;
      _uploadMessage = 'Error: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Reset upload state
  void resetUpload() {
    _uploadStatus = UploadStatus.idle;
    _uploadProgress = 0;
    _uploadMessage = '';
    _lastResult = null;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════
  // USER REPORTS
  // ═══════════════════════════════════════════════════

  /// Stream of user's pothole reports
  Stream<QuerySnapshot> getUserReports(String userId) {
    return _firestoreService.getUserPotholes(userId);
  }

  // ═══════════════════════════════════════════════════
  // ADMIN – ALL POTHOLES
  // ═══════════════════════════════════════════════════

  /// Stream of all aggregated potholes (for admin dashboard)
  Stream<QuerySnapshot> getAggregatedPotholesStream() {
    return _firestoreService.getAggregatedPotholes();
  }

  /// Load all potholes for map (one-shot)
  Future<void> loadAllPotholes() async {
    _loadingPotholes = true;
    notifyListeners();

    _adminPotholes = await _firestoreService.getAllPotholes();
    _loadingPotholes = false;
    notifyListeners();
  }

  /// Update pothole status (admin)
  Future<void> updatePotholeStatus(String locationId, String status) async {
    await _firestoreService.updateAggregatedPotholeStatus(locationId, status);
  }

  /// Delete an aggregated pothole and all associated images from storage
  Future<void> deletePothole(String locationId) async {
    // 1. Get all detections to find image URLs
    final detections = await _firestoreService.getDetections(locationId);

    // 2. Identify all storage URLs to delete
    final urlsToDelete = <String>[];
    for (var d in detections) {
      if (d.imageUrl.isNotEmpty) urlsToDelete.add(d.imageUrl);
      if (d.pdfUrl != null && d.pdfUrl!.isNotEmpty) urlsToDelete.add(d.pdfUrl!);
    }

    // 3. Delete from Firebase Storage
    if (urlsToDelete.isNotEmpty) {
      await _storageService.deleteFilesFromUrls(urlsToDelete);
    }

    // 4. Delete from Firestore
    await _firestoreService.deleteAggregatedPothole(locationId);

    // 5. Update local state
    _adminPotholes.removeWhere((p) => p.locationId == locationId);
    notifyListeners();
  }

  /// Delete a single user report record
  Future<void> deleteUserReport(String docId, {String? imageUrl, String? pdfUrl}) async {
    // 1. Delete associated storage files if provided
    final urls = <String>[];
    if (imageUrl != null && imageUrl.isNotEmpty) urls.add(imageUrl);
    if (pdfUrl != null && pdfUrl.isNotEmpty) urls.add(pdfUrl);

    if (urls.isNotEmpty) {
      await _storageService.deleteFilesFromUrls(urls);
    }

    // 2. Delete from Firestore
    await _firestoreService.deletePotholeRecord(docId);
  }

  // ═══════════════════════════════════════════════════
  // DETECTIONS
  // ═══════════════════════════════════════════════════

  /// Load detections for a specific location
  Future<void> loadDetections(String locationId) async {
    _loadingDetections = true;
    notifyListeners();

    _detections = await _firestoreService.getDetections(locationId);
    _loadingDetections = false;
    notifyListeners();
  }

  /// Get latest detection for map marker info
  Future<DetectionModel?> getLatestDetection(String locationId) async {
    return await _firestoreService.getLatestDetection(locationId);
  }

  /// Load reports for a specific location
  Future<void> loadReports(String locationId) async {
    _loadingReports = true;
    notifyListeners();

    final data = await _firestoreService.getReports(locationId);
    _reports = data.map((m) => ReportModel.fromMap(m, m['id'])).toList();
    
    _loadingReports = false;
    notifyListeners();
  }
}
