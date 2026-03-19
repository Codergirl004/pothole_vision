import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants.dart';
import '../models/user_model.dart';
import '../models/pothole_model.dart';
import '../models/detection_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ═══════════════════════════════════════════════════
  // USERS
  // ═══════════════════════════════════════════════════

  /// Create a new user profile document
  Future<void> createUserProfile(UserModel user) async {
    await _db
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .set(user.toMap());
  }

  /// Get user profile by UID
  Future<UserModel?> getUserProfile(String uid) async {
    final doc =
        await _db.collection(AppConstants.usersCollection).doc(uid).get();
    if (doc.exists && doc.data() != null) {
      return UserModel.fromMap(doc.data()!, doc.id);
    }
    return null;
  }

  /// Get user role
  Future<String> getUserRole(String uid) async {
    final user = await getUserProfile(uid);
    return user?.role ?? AppConstants.roleUser;
  }

  // ═══════════════════════════════════════════════════
  // USER POTHOLES (potholes collection)
  // ═══════════════════════════════════════════════════

  /// Create a new pothole upload record before sending to backend
  Future<String> createPotholeRecord({
    required String userId,
    required double lat,
    required double lng,
    required int imageCount,
  }) async {
    final docRef =
        await _db.collection(AppConstants.potholesCollection).add({
      'userId': userId,
      'lat': lat,
      'lng': lng,
      'imageCount': imageCount,
      'analysisStatus': 'uploading',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Delete a user's pothole upload record
  Future<void> deletePotholeRecord(String docId) async {
    await _db.collection(AppConstants.potholesCollection).doc(docId).delete();
  }

  /// Update pothole record status
  Future<void> updatePotholeStatus(
      String docId, String status, {Map<String, dynamic>? extra}) async {
    final data = <String, dynamic>{'analysisStatus': status};
    if (extra != null) data.addAll(extra);
    await _db
        .collection(AppConstants.potholesCollection)
        .doc(docId)
        .update(data);
  }

  /// Get user's potholes stream (client-side sorted)
  Stream<QuerySnapshot> getUserPotholes(String userId) {
    return _db
        .collection(AppConstants.potholesCollection)
        .where('userId', isEqualTo: userId)
        .snapshots();
  }

  // ═══════════════════════════════════════════════════
  // AGGREGATED POTHOLES (Admin)
  // ═══════════════════════════════════════════════════

  /// Get all aggregated potholes stream
  Stream<QuerySnapshot> getAggregatedPotholes() {
    return _db
        .collection(AppConstants.aggregatedPotholesCollection)
        .orderBy('last_updated', descending: true)
        .snapshots();
  }

  /// Get all aggregated potholes (one-shot) for map markers
  Future<List<PotholeModel>> getAllPotholes() async {
    final snap = await _db
        .collection(AppConstants.aggregatedPotholesCollection)
        .get();
    return snap.docs
        .map((d) => PotholeModel.fromMap(d.data(), d.id))
        .toList();
  }

  /// Update pothole status (Admin action)
  Future<void> updateAggregatedPotholeStatus(
      String locationId, String status) async {
    await _db
        .collection(AppConstants.aggregatedPotholesCollection)
        .doc(locationId)
        .update({
      'status': status,
      'last_updated': FieldValue.serverTimestamp(),
    });
  }

  /// Delete an aggregated pothole and all ITS detections
  Future<void> deleteAggregatedPothole(String locationId) async {
    // 1. Delete all detections in the sub-collection
    final detections = await _db
        .collection(AppConstants.aggregatedPotholesCollection)
        .doc(locationId)
        .collection(AppConstants.detectionsSubcollection)
        .get();

    final batch = _db.batch();
    for (var doc in detections.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    // 2. Delete the main document
    await _db
        .collection(AppConstants.aggregatedPotholesCollection)
        .doc(locationId)
        .delete();
  }

  // ═══════════════════════════════════════════════════
  // DETECTIONS (Sub-collection of aggregated_potholes)
  // ═══════════════════════════════════════════════════

  /// Get detections for a location, sorted by priority score descending
  Future<List<DetectionModel>> getDetections(String locationId) async {
    final snap = await _db
        .collection(AppConstants.aggregatedPotholesCollection)
        .doc(locationId)
        .collection(AppConstants.detectionsSubcollection)
        .orderBy('priority.score', descending: true)
        .get();
    return snap.docs
        .map((d) => DetectionModel.fromMap(d.data()))
        .toList();
  }

  /// Get detections stream
  Stream<QuerySnapshot> getDetectionsStream(String locationId) {
    return _db
        .collection(AppConstants.aggregatedPotholesCollection)
        .doc(locationId)
        .collection(AppConstants.detectionsSubcollection)
        .orderBy('priority.score', descending: true)
        .snapshots();
  }

  /// Get the latest / highest-priority detection for a pothole
  Future<DetectionModel?> getLatestDetection(String locationId) async {
    final detections = await getDetections(locationId);
    if (detections.isNotEmpty) return detections.first;
    return null;
  }
}
