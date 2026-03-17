import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Upload a file to Firebase Storage and return the download URL
  Future<String> uploadFile(String storagePath, File file) async {
    final ref = _storage.ref().child(storagePath);
    final uploadTask = ref.putFile(file);
    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  /// Get download URL for an existing storage path
  Future<String> getDownloadUrl(String storagePath) async {
    return await _storage.ref().child(storagePath).getDownloadURL();
  }

  /// Delete a file from Firebase Storage
  Future<void> deleteFile(String storagePath) async {
    try {
      await _storage.ref().child(storagePath).delete();
    } catch (_) {
      // File may not exist, ignore
    }
  }
}
