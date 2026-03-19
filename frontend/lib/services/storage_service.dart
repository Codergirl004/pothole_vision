import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Deletes a file from Firebase Storage given its public URL.
  Future<void> deleteFileFromUrl(String url) async {
    if (url.isEmpty) return;
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
    } catch (e) {
      // If the file is already gone, or it's not a storage URL, ignore
      print('Error deleting storage file: $e');
    }
  }

  /// Deletes multiple files from Firebase Storage given their public URLs.
  Future<void> deleteFilesFromUrls(List<String> urls) async {
    await Future.wait(urls.map((url) => deleteFileFromUrl(url)));
  }
}
