import 'package:country_state_city/country_state_city.dart' as csc;
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../models/contact.dart';

class GeoPoint {
  final double latitude;
  final double longitude;

  const GeoPoint(this.latitude, this.longitude);

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}

class LocationService {
  static final Map<String, GeoPoint?> _geoCache = {};

  static Future<List<csc.Country>> getCountries() async {
    return await csc.getAllCountries();
  }

  static Future<List<csc.State>> getStates(String countryCode) async {
    return await csc.getStatesOfCountry(countryCode);
  }

  static Future<List<csc.City>> getCities(String countryCode, String stateCode) async {
    return await csc.getStateCities(countryCode, stateCode);
  }

  /// Calculates geographical distance in meters between two coordinates.
  static double calculateDistanceInMeters(double startLat, double startLng, double endLat, double endLng) {
    try {
      return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
    } catch (_) {
      return double.infinity;
    }
  }

  /// Resolves coordinates for a given address string, using memory cache.
  static Future<GeoPoint?> getCoordinatesForAddress(String rawAddress) async {
    final clean = rawAddress.trim().toLowerCase();
    if (clean.isEmpty) return null;
    if (_geoCache.containsKey(clean)) {
      return _geoCache[clean];
    }

    try {
      final locations = await Geocoding().locationFromAddress(rawAddress);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        final point = GeoPoint(loc.latitude, loc.longitude);
        _geoCache[clean] = point;
        return point;
      }
    } catch (e) {
      debugPrint("Geocoding lookup error for '$rawAddress': $e");
    }

    _geoCache[clean] = null;
    return null;
  }

  /// Resolves the best GeoPoint for a contact (either stored or via address geocoding).
  static Future<GeoPoint?> resolveContactCoordinates(DirectoryContact contact) async {
    if (contact.latitude != null && contact.longitude != null) {
      return GeoPoint(contact.latitude!, contact.longitude!);
    }

    // Try full location
    final loc = contact.location?.trim() ?? '';
    final loc1 = contact.location1?.trim() ?? '';
    final city = contact.city?.trim() ?? '';
    final state = contact.state?.trim() ?? '';

    // Search hierarchical address strings
    final candidates = <String>[];
    if (loc.isNotEmpty) candidates.add(loc);
    if (loc1.isNotEmpty) {
      if (state.isNotEmpty && !loc1.toLowerCase().contains(state.toLowerCase())) {
        candidates.add('$loc1, $state');
      } else {
        candidates.add(loc1);
      }
    }
    if (city.isNotEmpty) {
      if (state.isNotEmpty) {
        candidates.add('$city, $state');
      } else {
        candidates.add(city);
      }
    }

    for (final cand in candidates) {
      final point = await getCoordinatesForAddress(cand);
      if (point != null) return point;
    }

    return null;
  }

  /// Resolves coordinates for multiple contacts with timeout
  static Future<Map<String, GeoPoint>> resolveMultipleCoordinates(List<DirectoryContact> contacts) async {
    final Map<String, GeoPoint> resolved = {};
    final futures = <Future<void>>[];

    for (final c in contacts) {
      final key = c.id ?? c.phone;
      if (c.latitude != null && c.longitude != null) {
        resolved[key] = GeoPoint(c.latitude!, c.longitude!);
      } else {
        futures.add(() async {
          final p = await resolveContactCoordinates(c);
          if (p != null) {
            resolved[key] = p;
          }
        }());
      }
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures).timeout(const Duration(milliseconds: 1500), onTimeout: () => []);
    }

    return resolved;
  }
}
