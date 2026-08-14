import 'package:country_state_city/country_state_city.dart' as csc;

class LocationService {
  static Future<List<csc.Country>> getCountries() async {
    return await csc.getAllCountries();
  }

  static Future<List<csc.State>> getStates(String countryCode) async {
    return await csc.getStatesOfCountry(countryCode);
  }

  static Future<List<csc.City>> getCities(String countryCode, String stateCode) async {
    return await csc.getStateCities(countryCode, stateCode);
  }
}
