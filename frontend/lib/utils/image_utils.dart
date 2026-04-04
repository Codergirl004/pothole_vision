import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:exif/exif.dart';

class ImageUtils {
  /// Extract Lat/Lng from Image EXIF data
  static Future<Map<String, double>?> extractLocation(File file) async {
    try {
      final fileBytes = await file.readAsBytes();
      final data = await readExifFromBytes(fileBytes);

      if (data == null || data.isEmpty) return null;

      final latTag = data['GPS GPSLatitude'];
      final latRef = data['GPS GPSLatitudeRef']?.printable;
      final lngTag = data['GPS GPSLongitude'];
      final lngRef = data['GPS GPSLongitudeRef']?.printable;

      if (latTag == null || latRef == null || lngTag == null || lngRef == null) {
        return null;
      }

      double convertCoord(IfdTag tag, String ref) {
        final values = tag.values.toList();
        // values[0] = degrees, values[1] = minutes, values[2] = seconds
        double d = values[0].toDouble();
        double m = values[1].toDouble();
        double s = values[2].toDouble();

        double res = d + (m / 60.0) + (s / 3600.0);
        if (ref == 'S' || ref == 'W') res = -res;
        return res;
      }

      return {
        'lat': convertCoord(latTag, latRef),
        'lng': convertCoord(lngTag, lngRef),
      };
    } catch (e) {
      return null;
    }
  }

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
