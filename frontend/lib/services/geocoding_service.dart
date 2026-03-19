import 'package:geocoding/geocoding.dart';

class GeocodingService {
  static final Map<String, String> _cache = {};

  static Future<String> getAddressFromCoordinates(double lat, double lng) async {
    final key = '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
    
    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        // Construct a readable address
        String address = [
          place.street,
          place.subLocality,
          place.locality,
          place.administrativeArea,
          place.postalCode
        ].where((e) => e != null && e.isNotEmpty).join(', ');
        
        _cache[key] = address;
        return address;
      }
    } catch (e) {
      print('Geocoding error: $e');
    }

    return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
  }
}
