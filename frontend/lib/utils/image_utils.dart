import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

class ImageUtils {
  /// Compress an image file and return a new compressed file.
  /// Default quality: 70, max dimension: 1920px.
  static Future<File> compressImage(
    File file, {
    int quality = 70,
    int minWidth = 1920,
    int minHeight = 1080,
  }) async {
    final dir = await getTemporaryDirectory();
    final targetPath =
        '${dir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final XFile? result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: quality,
      minWidth: minWidth,
      minHeight: minHeight,
    );

    if (result != null) {
      return File(result.path);
    }
    // Return original if compression fails
    return file;
  }

  /// Compress a list of images
  static Future<List<File>> compressImages(List<File> files) async {
    final compressed = <File>[];
    for (final file in files) {
      compressed.add(await compressImage(file));
    }
    return compressed;
  }
}
