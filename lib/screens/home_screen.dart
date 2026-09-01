import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../models/user_session.dart';
import '../models/contact.dart';
import '../widgets/contact_card.dart';
import '../widgets/app_header.dart';
import '../widgets/header_menu.dart';
import 'details_screen.dart';
import 'my_contacts_screen.dart';

import '../services/countries.dart';
import '../widgets/country_picker_dialog.dart';
import '../services/location_service.dart';

class _NearbyCache {
  static List<DirectoryContact>? profiles;
  static GeoPoint? cachedGeo;
  static String? cachedScopeKey;
  static DateTime? cachedTime;
  static bool isFetching = false;

  static bool isValid(String? currentScope, GeoPoint? currentGeo) {
    if (profiles == null || profiles!.isEmpty || cachedTime == null) return false;
    if (DateTime.now().difference(cachedTime!).inMinutes > 20) return false;
    if (cachedScopeKey != currentScope) return false;
    if (currentGeo != null && cachedGeo != null) {
      final dist = LocationService.calculateDistanceInMeters(
        currentGeo.latitude, currentGeo.longitude, cachedGeo!.latitude, cachedGeo!.longitude
      );
      if (dist > 5000) return false;
    }
    return true;
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, required this.store, required this.session, required this.onSearchModeChanged});
  final ApiClient api;
  final SessionStore store;
  final UserSession session;
  final Function(bool) onSearchModeChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  bool _isSearching = false;
  bool _loading = false;
  bool _hasSearched = false;
  List<DirectoryContact> _results = [];
  int _localMatchCount = 0;
  int _sponsoredCount = 0;
  final Set<String> _deductedPhonesThisSession = {};
  List<MyContactItem> _localContacts = [];
  List<DirectoryContact> _favs = [];
  String _scopeLabel = 'Location(Current Location)';
  String? _selectedLocation; // For filtering
  bool _userHasCustomScope = false;
  List<Map<String, dynamic>> _cachedDirectoryList = [];
  GeoPoint? _currentUserGeo;
  List<DirectoryContact> _nearbyProfiles = [];
  bool _loadingNearby = false;

  String _normalizePhone(String? p) {
    if (p == null) return '';
    final d = p.replaceAll(RegExp(r'[^0-9]'), '');
    return d.length >= 10 ? d.substring(d.length - 10) : d;
  }

  bool _isMyContactMatch(DirectoryContact c) {
    if (c.category == 'my_contact') return true;
    final phonesToCheck = <String>{};
    final p1 = _normalizePhone(c.phone);
    if (p1.isNotEmpty) phonesToCheck.add(p1);
    final p2 = _normalizePhone(c.whatsapp);
    if (p2.isNotEmpty) phonesToCheck.add(p2);
    final p3 = _normalizePhone(c.landline);
    if (p3.isNotEmpty) phonesToCheck.add(p3);
    if (c.additionalPhones != null && c.additionalPhones!.isNotEmpty) {
      for (final ap in c.additionalPhones!.split(',')) {
        final np = _normalizePhone(ap);
        if (np.isNotEmpty) phonesToCheck.add(np);
      }
    }

    if (phonesToCheck.isNotEmpty) {
      for (final l in _localContacts) {
        final lPhone = _normalizePhone(l.phone);
        if (lPhone.isNotEmpty && phonesToCheck.contains(lPhone)) return true;
      }
    }
    return false;
  }

  Future<GeoPoint?> _getUserCurrentGeo() async {
    if (_currentUserGeo != null) return _currentUserGeo;

    try {
      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 3),
        ),
      );
      if (position != null) {
        _currentUserGeo = GeoPoint(position.latitude, position.longitude);
        return _currentUserGeo;
      }
    } catch (_) {}

    final place = widget.session.place1 ?? widget.session.place;
    if (place != null && place.isNotEmpty && place != "Current Location") {
      final geo = await LocationService.getCoordinatesForAddress(place);
      if (geo != null) {
        _currentUserGeo = geo;
        return geo;
      }
    }

    final country = widget.session.country;
    if (country != null && country.isNotEmpty && country != "All") {
      final geo = await LocationService.getCoordinatesForAddress(country);
      if (geo != null) {
        _currentUserGeo = geo;
        return geo;
      }
    }

    return null;
  }

  void _onSearchChanged(String v) {
    if (v.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _results.clear();
        _hasSearched = false;
        _loading = false;
        widget.onSearchModeChanged(false);
      });
    } else {
      if (!_isSearching) {
        setState(() {
          _isSearching = true;
          widget.onSearchModeChanged(true);
        });
      }
    }
  }

  String _mapCountryCodeToName(String code) {
    final upper = code.toUpperCase();
    const map = {
      'IN': 'India',
      'US': 'United States',
      'GB': 'United Kingdom',
      'CA': 'Canada',
      'AU': 'Australia',
      'NG': 'Nigeria',
      'AE': 'United Arab Emirates',
      'SG': 'Singapore',
      'MY': 'Malaysia',
      'PK': 'Pakistan',
      'BD': 'Bangladesh',
      'LK': 'Sri Lanka',
      'ZA': 'South Africa',
      'DE': 'Germany',
      'FR': 'France',
      'IT': 'Italy',
      'ES': 'Spain',
      'BR': 'Brazil',
      'MX': 'Mexico',
      'NZ': 'New Zealand',
    };
    return map[upper] ?? 'India';
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _loadLocalContacts();
        if (_NearbyCache.profiles != null && _NearbyCache.profiles!.isNotEmpty) {
          _nearbyProfiles = _NearbyCache.profiles!;
        } else {
          _triggerBackgroundNearbyFetch();
        }
        if (!_isSearching) {
          setState(() {
            _isSearching = true;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _loadData() async {
    final favs = await widget.store.getFavourites();
    final currentSession = await widget.store.read();

    if (mounted) setState(() => _favs = favs);

    if (!_userHasCustomScope) {
      String defaultCity = (currentSession.place1 != null && currentSession.place1!.isNotEmpty)
          ? currentSession.place1!
          : ((widget.session.place1 != null && widget.session.place1!.isNotEmpty)
              ? widget.session.place1!
              : "Current Location");

      if (mounted) {
        setState(() {
          _scopeLabel = "Location($defaultCity)";
          _selectedLocation = defaultCity == "Current Location" ? null : defaultCity;
        });
      }

      _autoFetchLocation();
    }

    _loadLocalContacts();
    _preloadDirectoryData();
  }

  Future<void> _preloadDirectoryData() async {
    try {
      final dirData = await widget.api.get('check-contact', {
        'type': 'all',
        'location': '',
      });
      if (dirData is List) {
        final list = <Map<String, dynamic>>[];
        for (final item in dirData) {
          if (item is Map && item['name'] != null && item['name'].toString().trim().isNotEmpty) {
            list.add(Map<String, dynamic>.from(item));
          }
        }
        if (mounted) {
          setState(() {
            _cachedDirectoryList = list;
          });
          _triggerBackgroundNearbyFetch();
        }
      }
    } catch (e) {
      debugPrint("Preload directory error: $e");
    }
  }

  Future<void> _autoFetchLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position? position = await Geolocator.getLastKnownPosition();
        position ??= await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 4),
          ),
        );

        if (!kIsWeb && position != null) {
          _currentUserGeo = GeoPoint(position.latitude, position.longitude);
          List<Placemark> placemarks = await Geocoding().placemarkFromCoordinates(position.latitude, position.longitude);
          if (placemarks.isNotEmpty) {
            Placemark p = placemarks.first;
            final subLocality = p.subLocality?.trim();
            final locality = p.locality?.trim();
            final subAdmin = p.subAdministrativeArea?.trim();
            final admin = p.administrativeArea?.trim();

            String cityArea = '';
            if (subLocality != null && subLocality.isNotEmpty && locality != null && locality.isNotEmpty && subLocality.toLowerCase() != locality.toLowerCase()) {
              cityArea = "$subLocality,$locality";
            } else if (locality != null && locality.isNotEmpty) {
              cityArea = locality;
            } else if (subLocality != null && subLocality.isNotEmpty) {
              cityArea = subLocality;
            } else if (subAdmin != null && subAdmin.isNotEmpty) {
              cityArea = subAdmin;
            } else if (admin != null && admin.isNotEmpty) {
              cityArea = admin;
            }

            if (cityArea.isNotEmpty && mounted && !_userHasCustomScope) {
              setState(() {
                _scopeLabel = "Location($cityArea)";
                _selectedLocation = cityArea;
              });
              _triggerBackgroundNearbyFetch(forceRefresh: true);
              if (_search.text.isNotEmpty) {
                _doSearch(_search.text);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Auto location detection error: $e");
    }
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _preloadDirectoryData();
    if (oldWidget.session.email != widget.session.email || oldWidget.session.phone != widget.session.phone) {
      _loadLocalContacts();
    }
  }

  Future<void> _loadLocalContacts() async {
    final List<MyContactItem> list = [];
    try {
      final currentSession = await widget.store.read();
      final email = (currentSession.email != null && currentSession.email!.isNotEmpty)
          ? currentSession.email!
          : ((currentSession.phone != null && currentSession.phone!.isNotEmpty)
              ? currentSession.phone!
              : ((widget.session.email != null && widget.session.email!.isNotEmpty)
                  ? widget.session.email!
                  : (widget.session.phone ?? 'guest@fonebook.com')));

      final res = await widget.api.post('get_my_contacts', {'email': email, 'owner_email': email});
      if (res is List) {
        final parsed = res
            .where((e) {
              if (e is! Map) return false;
              final cat = e['category']?.toString().toLowerCase() ?? '';
              if (cat == 'app_profile') return false;
              final title = e['title']?.toString() ?? '';
              if (title.contains('"pincode"') || title.contains('"address"') || title.contains('"owner_email"')) return false;
              final appProf = e['app_profile']?.toString() ?? '';
              if (appProf.isNotEmpty && appProf != 'null') return false;
              return true;
            })
            .map((e) => MyContactItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        list.addAll(parsed);
      }

      if (mounted) {
        setState(() {
          _localContacts = list;
        });
      }
    } catch (e) {
      debugPrint("Error loading local contacts: $e");
    }
  }

  void _loadFavs() async {
    final favs = await widget.store.getFavourites();
    setState(() => _favs = favs);
  }

  bool _matchesSelectedLocation(DirectoryContact c, String targetLoc) {
    if (targetLoc.trim().isEmpty) return true;
    if (_scopeLabel == 'International') return true;

    final target = targetLoc.trim().toLowerCase();
    if (target.isEmpty || target == 'international' || target == 'all' || target == 'current location') return true;

    final parts = target
        .split(',')
        .map((p) => p.trim().toLowerCase())
        .where((p) => p.isNotEmpty)
        .toList();

    final cLoc = (c.location ?? '').toLowerCase();
    final cLoc1 = (c.location1 ?? '').toLowerCase();
    final cCity = (c.city ?? '').toLowerCase();
    final cState = (c.state ?? '').toLowerCase();

    final fullText = '$cLoc $cLoc1 $cCity $cState'.trim();

    if (fullText.isEmpty) {
      return true;
    }

    for (final p in parts) {
      if (p == 'current location' || p.isEmpty) continue;
      if (fullText.contains(p)) return true;
      if (cCity.isNotEmpty && (p.contains(cCity) || cCity.contains(p))) return true;
      if (cState.isNotEmpty && (p.contains(cState) || cState.contains(p))) return true;
    }

    return false;
  }

  Future<void> _doSearch(String q) async {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _isSearching = true;
      _hasSearched = true;
    });

    unawaited(widget.api.post('savesearch', {
      'tag': q.trim(),
      'country': widget.session.country ?? '',
      'location': widget.session.place1 ?? '',
    }));
    unawaited(_loadLocalContacts());

    String apiLocation = '';
    if (_scopeLabel.startsWith('Location(') || _scopeLabel.startsWith('Country(')) {
      apiLocation = _selectedLocation ?? '';
    }

    try {
      final searchRes = await widget.api.get('check-contact', {
        'type': 'search',
        'query': q.trim(),
        'location': apiLocation,
      });

      final searchData = searchRes is List ? searchRes as List : [];

      List<dynamic> dirData = _cachedDirectoryList;
      if (dirData.isEmpty) {
        final allRes = await widget.api.get('check-contact', {
          'type': 'all',
          'location': '',
        });
        if (allRes is List) {
          dirData = allRes;
          _cachedDirectoryList = dirData
              .where((item) => item is Map && item['name'] != null && item['name'].toString().trim().isNotEmpty)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        }
      }

      await _processAndRenderSearchResults(searchData, dirData, query);
    } catch (e) {
      debugPrint("Search error: $e");
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _processAndRenderSearchResults(List<dynamic> searchData, List<dynamic> dirData, String query) async {
    final cleanQ = query.replaceAll(RegExp(r'[\s\-\+\(\)]'), '');
    String apiLocation = '';
    if (_scopeLabel.startsWith('Location(') || _scopeLabel.startsWith('Country(')) {
      apiLocation = _selectedLocation ?? '';
    }

    final List<Map<String, dynamic>> combinedRaw = [];
    final Set<String> seenKeys = {};

    for (final item in searchData) {
      if (item is Map && item['name'] != null && item['name'].toString().trim().isNotEmpty) {
        final mapItem = Map<String, dynamic>.from(item);
        combinedRaw.add(mapItem);

        final id = mapItem['id']?.toString() ?? '';
        if (id.isNotEmpty) {
          seenKeys.add("id_$id");
        }
        final phone = (mapItem['phone_no'] ?? mapItem['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
        final name = (mapItem['name'] ?? '').toString().trim().toLowerCase();
        final service = (mapItem['service'] ?? '').toString().trim().toLowerCase();
        if (phone.isNotEmpty) {
          seenKeys.add("pns_${phone}_${name}_${service}");
        }
      }
    }

    for (final item in dirData) {
      if (item is Map && item['name'] != null && item['name'].toString().trim().isNotEmpty) {
        final id = item['id']?.toString() ?? '';
        final phone = (item['phone_no'] ?? item['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
        final name = (item['name'] ?? '').toString().trim().toLowerCase();
        final service = (item['service'] ?? '').toString().trim().toLowerCase();

        final isIdSeen = id.isNotEmpty && seenKeys.contains("id_$id");
        final isPnsSeen = phone.isNotEmpty && seenKeys.contains("pns_${phone}_${name}_${service}");

        if (!isIdSeen && !isPnsSeen) {
          combinedRaw.add(Map<String, dynamic>.from(item));
        }
      }
    }

    final rawApiList = combinedRaw
        .map((e) => DirectoryContact.fromJson(e))
        .toList();

    final Map<String, DirectoryContact> candidateMap = {};

    for (final e in rawApiList) {
      if (e.subscriptionStatus == 'expired') {
        continue;
      }
      if (e.subscriptionEnd != null && e.subscriptionEnd!.isNotEmpty) {
        final endDate = DateTime.tryParse(e.subscriptionEnd!);
        if (endDate != null && DateTime.now().isAfter(endDate)) {
          continue;
        }
      }

      if (apiLocation.isNotEmpty && !_matchesSelectedLocation(e, apiLocation)) {
        continue;
      }

      final cleanPhone = e.phone.replaceAll(RegExp(r'[\s\-\+\(\)]'), '');
      final queryWords = query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

      final serviceMatch = e.service.toLowerCase().contains(query) ||
          queryWords.any((w) => w.length > 1 && e.service.toLowerCase().contains(w));

      final keywordMatch = (e.keyword?.toLowerCase().contains(query) ?? false) ||
          (e.tags?.toLowerCase().contains(query) ?? false) ||
          (e.additionalServices?.toLowerCase().contains(query) ?? false) ||
          queryWords.any((w) =>
              w.length > 1 &&
              ((e.keyword?.toLowerCase().contains(w) ?? false) ||
               (e.tags?.toLowerCase().contains(w) ?? false) ||
               (e.additionalServices?.toLowerCase().contains(w) ?? false)));

      final nameMatch = e.name.toLowerCase().contains(query);
      final phoneMatch = cleanQ.isNotEmpty && cleanPhone.contains(cleanQ);

      if (nameMatch && !serviceMatch && !keywordMatch && !phoneMatch) {
        continue;
      }

      final textMatch = serviceMatch || keywordMatch || phoneMatch;
      if (!textMatch) continue;

      final who = (e.whoContact ?? 'international').toLowerCase();
      if (who != 'international' && who != 'all' && who.isNotEmpty) {
        final isLocationSearch = _scopeLabel.startsWith('Location(');
        final isCountrySearch = _scopeLabel.startsWith('Country(');
        final isInternationalSearch = _scopeLabel == 'International';

        if (who == 'country' && !(isLocationSearch || isCountrySearch || isInternationalSearch)) {
          continue;
        }
        if (who == 'location' && !isLocationSearch) {
          continue;
        }
      }

      final String profileKey = (e.id != null && e.id!.isNotEmpty)
          ? "api_id_${e.id}"
          : "api_custom_${e.name.toLowerCase().trim()}_${_normalizePhone(e.phone)}_${e.service.toLowerCase().trim()}";

      if (candidateMap.containsKey(profileKey)) {
        continue;
      }

      final isMyContact = _isMyContactMatch(e);
      if (isMyContact) {
        candidateMap[profileKey] = DirectoryContact(
          id: e.id,
          name: e.name,
          service: e.service,
          phone: e.phone,
          location: e.location,
          location1: e.location1,
          city: e.city,
          state: e.state,
          image: e.image,
          keyword: e.keyword,
          tags: e.tags,
          verified: e.verified,
          priority: e.priority,
          priorityBalance: e.priorityBalance,
          category: 'my_contact',
          showContact: e.showContact,
          additionalPhones: e.additionalPhones,
          additionalServices: e.additionalServices,
          latitude: e.latitude,
          longitude: e.longitude,
        );
      } else {
        candidateMap[profileKey] = e;
      }
    }

    for (final c in _localContacts) {
      final cleanP = c.phone.replaceAll(RegExp(r'[\s\-\+\(\)]'), '');
      final nameMatch = c.name.toLowerCase().contains(query);
      final titleMatch = c.title.toLowerCase().contains(query);
      final phoneMatch = cleanQ.isNotEmpty && cleanP.contains(cleanQ);

      if (nameMatch || titleMatch || phoneMatch) {
        final cCleanPhone = _normalizePhone(c.phone);

        DirectoryContact? existingItem;
        String? existingKey;
        for (final entry in candidateMap.entries) {
          final itemPhone = _normalizePhone(entry.value.phone);
          if (cCleanPhone.isNotEmpty && itemPhone.isNotEmpty && cCleanPhone == itemPhone) {
            existingItem = entry.value;
            existingKey = entry.key;
            break;
          }
        }

        if (existingItem != null && existingKey != null) {
          candidateMap[existingKey] = DirectoryContact(
            id: existingItem.id,
            name: existingItem.name,
            service: existingItem.service,
            phone: existingItem.phone,
            location: existingItem.location,
            location1: existingItem.location1,
            city: existingItem.city,
            state: existingItem.state,
            image: existingItem.image,
            keyword: existingItem.keyword,
            tags: existingItem.tags,
            verified: existingItem.verified,
            priority: existingItem.priority,
            priorityBalance: existingItem.priorityBalance,
            category: 'my_contact',
            showContact: existingItem.showContact,
            additionalPhones: existingItem.additionalPhones,
            additionalServices: existingItem.additionalServices,
            latitude: existingItem.latitude,
            longitude: existingItem.longitude,
          );
        } else {
          final localKey = "local_${c.id ?? cCleanPhone}_${c.name.toLowerCase().trim()}";
          candidateMap[localKey] = DirectoryContact(
            id: c.id?.toString(),
            name: c.name,
            service: c.title.isNotEmpty && c.title != 'My Contact' ? c.title : '',
            phone: c.phone,
            priority: '1',
            priorityBalance: '0',
            category: 'my_contact',
            showContact: 'mwelsf',
          );
        }
      }
    }

    final allCandidates = candidateMap.values.toList();
    final userGeo = await _getUserCurrentGeo();
    final Map<String, GeoPoint> resolvedGeoMap = await LocationService.resolveMultipleCoordinates(allCandidates);

    final userArea = widget.session.place1 ?? widget.session.place ?? '';
    final userAreaLower = (userArea.isEmpty || userArea.toLowerCase() == 'current location') ? '' : userArea.toLowerCase();
    final userAreaParts = userAreaLower.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty && p != 'current location').toList();
    final queryWords = query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    int calcSearchScore(DirectoryContact c) {
      final serviceLower = c.service.toLowerCase().trim();
      final keywordText = '${c.keyword ?? ''} ${c.tags ?? ''} ${c.additionalServices ?? ''}'.toLowerCase().trim();
      final nameLower = c.name.toLowerCase().trim();

      if (serviceLower == query) return 1;
      if (serviceLower.startsWith(query)) return 2;
      if (serviceLower.contains(query)) return 3;

      final serviceWords = serviceLower.split(RegExp(r'[\s,\/\-]+')).where((w) => w.isNotEmpty).toList();
      final matchesServiceWord = queryWords.any((qw) => serviceWords.any((sw) => sw == qw || (sw.length > 2 && sw.contains(qw)) || (qw.length > 2 && qw.contains(sw))));
      if (matchesServiceWord) return 4;

      if (keywordText.contains(query)) return 5;
      final keywordWords = keywordText.split(RegExp(r'[\s,\/\-]+')).where((w) => w.isNotEmpty).toList();
      final matchesKeywordWord = queryWords.any((qw) => keywordWords.any((kw) => kw == qw || (kw.length > 2 && kw.contains(qw))));
      if (matchesKeywordWord) return 6;

      if (nameLower.contains(query)) return 7;

      return 8;
    }

    int calcPriorityTier(DirectoryContact c) {
      if (c.category == 'my_contact' || _isMyContactMatch(c)) return 1;
      final bal = double.tryParse(c.priorityBalance) ?? 0.0;
      if (bal > 0 || c.priority == '0') return 2;
      return 3;
    }

    int calcLocationHierarchyTier(DirectoryContact c) {
      if (userAreaLower.isEmpty) return 5;
      final fullText = '${c.location ?? ''} ${c.location1 ?? ''} ${c.city ?? ''} ${c.state ?? ''}'.toLowerCase().trim();
      if (fullText.isEmpty) return 6;
      for (final p in userAreaParts) {
        if (fullText.contains(p)) return 1;
      }
      if (c.city != null && c.city!.isNotEmpty && userAreaLower.contains(c.city!.toLowerCase())) return 2;
      if (c.state != null && c.state!.isNotEmpty && userAreaLower.contains(c.state!.toLowerCase())) return 3;
      return 4;
    }

    double calcDistanceMeters(DirectoryContact c) {
      if (userGeo == null) return double.infinity;
      final key = c.id ?? c.phone;
      final g = resolvedGeoMap[key] ?? (c.latitude != null && c.longitude != null ? GeoPoint(c.latitude!, c.longitude!) : null);
      if (g != null) {
        return LocationService.calculateDistanceInMeters(userGeo.latitude, userGeo.longitude, g.latitude, g.longitude);
      }
      return double.infinity;
    }

    final List<_CandidateWrapper> wrappers = allCandidates.map((c) {
      return _CandidateWrapper(
        contact: c,
        priorityTier: calcPriorityTier(c),
        searchScore: calcSearchScore(c),
        priorityBalance: double.tryParse(c.priorityBalance) ?? 0.0,
        distanceMeters: calcDistanceMeters(c),
        locationHierarchyTier: calcLocationHierarchyTier(c),
        nameLower: c.name.toLowerCase(),
      );
    }).toList();

    wrappers.sort((a, b) {
      if (a.priorityTier != b.priorityTier) return a.priorityTier.compareTo(b.priorityTier);
      if (a.priorityTier == 1) {
        if (a.distanceMeters != b.distanceMeters) return a.distanceMeters.compareTo(b.distanceMeters);
        if (a.locationHierarchyTier != b.locationHierarchyTier) return a.locationHierarchyTier.compareTo(b.locationHierarchyTier);
        if (a.searchScore != b.searchScore) return a.searchScore.compareTo(b.searchScore);
        return a.nameLower.compareTo(b.nameLower);
      }
      if (a.priorityTier == 2) {
        if (a.distanceMeters != b.distanceMeters) return a.distanceMeters.compareTo(b.distanceMeters);
        if (a.locationHierarchyTier != b.locationHierarchyTier) return a.locationHierarchyTier.compareTo(b.locationHierarchyTier);
        if (a.priorityBalance != b.priorityBalance) return b.priorityBalance.compareTo(a.priorityBalance);
        if (a.searchScore != b.searchScore) return a.searchScore.compareTo(b.searchScore);
        return a.nameLower.compareTo(b.nameLower);
      }
      if (a.distanceMeters != b.distanceMeters) return a.distanceMeters.compareTo(b.distanceMeters);
      if (a.locationHierarchyTier != b.locationHierarchyTier) return a.locationHierarchyTier.compareTo(b.locationHierarchyTier);
      if (a.searchScore != b.searchScore) return a.searchScore.compareTo(b.searchScore);
      if (a.contact.verified != b.contact.verified) return b.contact.verified.compareTo(a.contact.verified);
      return a.nameLower.compareTo(b.nameLower);
    });

    final sortedCandidates = wrappers.map((w) => w.contact).toList();
    final sponsoredList = sortedCandidates.where((c) => calcPriorityTier(c) == 2).toList();

    if (mounted) {
      setState(() {
        _results = sortedCandidates;
        _localMatchCount = sortedCandidates.where((c) => calcPriorityTier(c) == 1).length;
        _sponsoredCount = sponsoredList.length;
        _loading = false;
      });
    }

    if (sponsoredList.isNotEmpty) {
      _processSponsoredDeductions(sponsoredList, query);
    }
  }

  Future<void> _processSponsoredDeductions(List<DirectoryContact> sponsoredList, String query) async {
    const double impressionCost = 1.0; 
    final String loggedInPhone = widget.session.phone ?? '';
    final String loggedInEmail = widget.session.email ?? '';

    for (final item in sponsoredList) {
      if ((loggedInPhone.isNotEmpty && item.phone == loggedInPhone) ||
          (loggedInEmail.isNotEmpty && item.email == loggedInEmail)) {
        continue;
      }

      final String dedKey = "${query}_${item.phone}";
      if (_deductedPhonesThisSession.contains(dedKey)) {
        continue;
      }
      _deductedPhonesThisSession.add(dedKey);

      final currentBal = double.tryParse(item.priorityBalance) ?? 0.0;
      if (currentBal <= 0) continue;

      final newBal = (currentBal - impressionCost).clamp(0.0, double.infinity);
      final newBalStr = newBal.toStringAsFixed(2);
      final isStillPromoted = newBal > 0;

      try {
        await widget.api.post('savepriority', {
          'phone': item.phone,
          'priority_amount': newBalStr,
          'priority': isStillPromoted ? '0' : '1',
        });
      } catch (e) {
        debugPrint('Error deducting impression cost for ${item.phone}: $e');
      }
    }
  }

  Future<void> _triggerBackgroundNearbyFetch({bool forceRefresh = false}) async {
    final currentScope = _scopeLabel;
    final currentGeo = _currentUserGeo;

    if (!forceRefresh && _NearbyCache.isValid(currentScope, currentGeo)) {
      if (mounted && _nearbyProfiles.isEmpty) {
        setState(() {
          _nearbyProfiles = _NearbyCache.profiles!;
          _loadingNearby = false;
        });
      }
      return;
    }

    if (_NearbyCache.isFetching) return;
    _NearbyCache.isFetching = true;

    if (_nearbyProfiles.isEmpty && _NearbyCache.profiles == null && mounted) {
      setState(() => _loadingNearby = true);
    }

    Future.microtask(() async {
      try {
        List<Map<String, dynamic>> rawList = _cachedDirectoryList;
        if (rawList.isEmpty) {
          final dirData = await widget.api.get('check-contact', {
            'type': 'all',
            'location': '',
          });
          if (dirData is List) {
            rawList = dirData
                .whereType<Map>()
                .where((item) => item['name'] != null && item['name'].toString().trim().isNotEmpty)
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
            _cachedDirectoryList = rawList;
          }
        }

        final contacts = rawList.map((e) => DirectoryContact.fromJson(e)).toList();

        final eligible = contacts.where((c) {
          if (c.subscriptionStatus == 'expired') return false;
          if (c.subscriptionEnd != null && c.subscriptionEnd!.isNotEmpty) {
            final endDate = DateTime.tryParse(c.subscriptionEnd!);
            if (endDate != null && DateTime.now().isAfter(endDate)) return false;
          }
          return true;
        }).toList();

        final userGeo = await _getUserCurrentGeo();
        final Map<String, GeoPoint> resolvedGeoMap = await LocationService.resolveMultipleCoordinates(eligible);

        final userArea = widget.session.place1 ?? widget.session.place ?? '';
        final userAreaLower = (userArea.isEmpty || userArea.toLowerCase() == 'current location') ? '' : userArea.toLowerCase();
        final userAreaParts = userAreaLower.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty && p != 'current location').toList();

        double calcDistance(DirectoryContact c) {
          if (userGeo == null) return double.infinity;
          final key = c.id ?? c.phone;
          final g = resolvedGeoMap[key] ?? (c.latitude != null && c.longitude != null ? GeoPoint(c.latitude!, c.longitude!) : null);
          if (g != null) {
            return LocationService.calculateDistanceInMeters(userGeo.latitude, userGeo.longitude, g.latitude, g.longitude);
          }
          return double.infinity;
        }

        int calcLocTier(DirectoryContact c) {
          if (userAreaLower.isEmpty) return 5;
          final fullText = '${c.location ?? ''} ${c.location1 ?? ''} ${c.city ?? ''} ${c.state ?? ''}'.toLowerCase().trim();
          if (fullText.isEmpty) return 6;
          for (final p in userAreaParts) {
            if (fullText.contains(p)) return 1;
          }
          if (c.city != null && c.city!.isNotEmpty && userAreaLower.contains(c.city!.toLowerCase())) return 2;
          if (c.state != null && c.state!.isNotEmpty && userAreaLower.contains(c.state!.toLowerCase())) return 3;
          return 4;
        }

        final wrappers = eligible.map((c) {
          final isMyContact = _isMyContactMatch(c);
          final bal = double.tryParse(c.priorityBalance) ?? 0.0;
          final isSponsored = !isMyContact && (bal > 0 || c.priority == '0');
          return _CandidateWrapper(
            contact: c,
            priorityTier: isMyContact ? 1 : (isSponsored ? 2 : 3),
            searchScore: 0,
            priorityBalance: bal,
            distanceMeters: calcDistance(c),
            locationHierarchyTier: calcLocTier(c),
            nameLower: c.name.toLowerCase(),
          );
        }).toList();

        wrappers.sort((a, b) {
          if (a.distanceMeters != b.distanceMeters) {
            return a.distanceMeters.compareTo(b.distanceMeters);
          }
          if (a.locationHierarchyTier != b.locationHierarchyTier) {
            return a.locationHierarchyTier.compareTo(b.locationHierarchyTier);
          }
          if (a.priorityTier != b.priorityTier) {
            return a.priorityTier.compareTo(b.priorityTier);
          }
          return a.nameLower.compareTo(b.nameLower);
        });

        final sortedNearby = wrappers.map((w) => w.contact).take(15).toList();

        _NearbyCache.profiles = sortedNearby;
        _NearbyCache.cachedGeo = userGeo;
        _NearbyCache.cachedScopeKey = currentScope;
        _NearbyCache.cachedTime = DateTime.now();

        if (mounted) {
          setState(() {
            _nearbyProfiles = sortedNearby;
            _loadingNearby = false;
          });
        }
      } catch (e) {
        debugPrint("Error loading nearby profiles: $e");
        if (mounted) setState(() => _loadingNearby = false);
      } finally {
        _NearbyCache.isFetching = false;
      }
    });
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _loading = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        _currentUserGeo = GeoPoint(position.latitude, position.longitude);
        
        String cityArea = "Current Location";
        
        if (!kIsWeb) {
          List<Placemark> placemarks = await Geocoding().placemarkFromCoordinates(position.latitude, position.longitude);
          if (placemarks.isNotEmpty) {
            Placemark p = placemarks[0];
            cityArea = p.subLocality != null ? "${p.subLocality}, ${p.locality}" : (p.locality ?? '');
          }
        }

        setState(() {
          _scopeLabel = "Location($cityArea)";
          _selectedLocation = cityArea;
        });
        _triggerBackgroundNearbyFetch(forceRefresh: true);
        if (_search.text.isNotEmpty) _doSearch(_search.text);
      }
    } catch (e) {
      debugPrint("Location error: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<List<String>> _fetchCityAreas(String city) async {
    final areas = <String>{};
    try {
      final data = await widget.api.get('check-contact', {
        'type': 'search',
        'query': '',
        'location': city,
      });

      if (data is List) {
        for (var item in data) {
          if (item is Map && item['location1'] != null) {
            final loc = item['location1'].toString().trim();
            if (loc.isNotEmpty) {
              final areaName = loc.split(',').first.trim();
              if (areaName.isNotEmpty && areaName.toLowerCase() != city.toLowerCase()) {
                areas.add(areaName);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching city areas: $e");
    }
    return areas.toList();
  }

  Future<Map<String, dynamic>> _fetchGpsAndDatabaseAreas() async {
    final areas = <String>{};
    String currentCity = "Current Location";
    String currentArea = "";

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        
        if (!kIsWeb) {
          List<Placemark> placemarks = await Geocoding().placemarkFromCoordinates(position.latitude, position.longitude);
          for (var p in placemarks) {
            if (p.subLocality != null && p.subLocality!.trim().isNotEmpty) {
              areas.add(p.subLocality!.trim());
              currentArea = p.subLocality!.trim();
            }
            if (p.thoroughfare != null && p.thoroughfare!.trim().isNotEmpty) {
              areas.add(p.thoroughfare!.trim());
            }
            if (p.locality != null && p.locality!.trim().isNotEmpty) {
              currentCity = p.locality!.trim();
            }
          }
        }
      }
    } catch (e) {
      debugPrint("GPS Geocoding error: $e");
    }

    if ((currentCity == "Current Location" || currentCity.isEmpty) && _formattedScopeLabel.isNotEmpty) {
      currentCity = _formattedScopeLabel;
    }

    final dbAreas = await _fetchCityAreas(currentCity);
    areas.addAll(dbAreas);

    final contactAreas = _results
        .map((c) => c.location1?.split(',').first.trim())
        .whereType<String>()
        .where((a) => a.isNotEmpty)
        .toList();
    areas.addAll(contactAreas);

    return {
      'city': currentCity,
      'currentArea': currentArea,
      'areas': areas.where((a) => a.trim().isNotEmpty && a.toLowerCase() != currentCity.toLowerCase()).toList(),
    };
  }

  Future<Map<String, String>?> _validateGooglePlace(String query) async {
    final q = query.trim();
    if (q.length < 2) return null;
    try {
      final geocoding = Geocoding();
      List<Location> locations = await geocoding.locationFromAddress(q);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        List<Placemark> placemarks = await geocoding.placemarkFromCoordinates(loc.latitude, loc.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final subLoc = p.subLocality?.trim();
          final thoroughfare = p.thoroughfare?.trim();
          final name = p.name?.trim();
          final locality = p.locality?.trim();
          final adminArea = p.administrativeArea?.trim();
          final country = p.country?.trim();

          final formattedQuery = q.split(' ').map((w) => w.isNotEmpty ? "${w[0].toUpperCase()}${w.substring(1)}" : "").join(' ');
          final qLower = q.toLowerCase();

          String selectedName = formattedQuery;
          String subtitle = [locality, adminArea, country].where((s) => s != null && s.isNotEmpty && s.toLowerCase() != qLower).join(', ');

          if (subLoc != null && subLoc.isNotEmpty && subLoc.toLowerCase().contains(qLower)) {
            selectedName = subLoc;
            subtitle = [locality, adminArea, country].where((s) => s != null && s.isNotEmpty && s.toLowerCase() != subLoc.toLowerCase()).join(', ');
          } else if (thoroughfare != null && thoroughfare.isNotEmpty && thoroughfare.toLowerCase().contains(qLower)) {
            selectedName = thoroughfare;
            subtitle = [subLoc, locality, adminArea, country].where((s) => s != null && s.isNotEmpty && s.toLowerCase() != thoroughfare.toLowerCase()).join(', ');
          } else if (name != null && name.isNotEmpty && name.toLowerCase().contains(qLower)) {
            selectedName = name;
            subtitle = [subLoc, locality, adminArea, country].where((s) => s != null && s.isNotEmpty && s.toLowerCase() != name.toLowerCase()).join(', ');
          } else if (locality != null && locality.isNotEmpty && locality.toLowerCase().contains(qLower)) {
            selectedName = locality;
            subtitle = [adminArea, country].where((s) => s != null && s.isNotEmpty).join(', ');
          } else if (adminArea != null && adminArea.isNotEmpty && adminArea.toLowerCase().contains(qLower)) {
            selectedName = adminArea;
            subtitle = (country != null && country.isNotEmpty) ? "State / Region in $country" : "State / Region";
          } else if (country != null && country.isNotEmpty && country.toLowerCase().contains(qLower)) {
            selectedName = country;
            subtitle = "Country";
          } else {
            selectedName = formattedQuery;
            subtitle = [subLoc, locality, adminArea, country]
                .where((s) => s != null && s.isNotEmpty && s.toLowerCase() != qLower)
                .join(', ');
          }

          if (subtitle.isEmpty) {
            subtitle = 'Google Maps Verified Location';
          }

          return {
            'name': selectedName,
            'subtitle': subtitle,
          };
        }
        final formattedQuery = q.split(' ').map((w) => w.isNotEmpty ? "${w[0].toUpperCase()}${w.substring(1)}" : "").join(' ');
        return {
          'name': formattedQuery,
          'subtitle': 'Google Maps Verified Location',
        };
      }
    } catch (e) {
      debugPrint("Worldwide geocoding error: $e");
    }
    return null;
  }

  void _showChooseAreaPicker() {
    final initialCity = _formattedScopeLabel.isNotEmpty ? _formattedScopeLabel : (widget.session.place1 ?? 'Current Location');
    final areaFuture = _fetchGpsAndDatabaseAreas();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bContext) {
        String filter = '';
        return StatefulBuilder(
          builder: (stContext, setSt) {
            return FutureBuilder<Map<String, dynamic>>(
              future: areaFuture,
              builder: (fContext, snapshot) {
                final isLoading = snapshot.connectionState == ConnectionState.waiting;
                final locationData = snapshot.data ?? {};
                final currentCity = (locationData['city'] as String?) ?? initialCity;
                final allAreas = (locationData['areas'] as List<String>?) ?? <String>[];

                final filteredAreas = allAreas
                    .where((a) => a.toLowerCase().contains(filter.toLowerCase()))
                    .toList();

                return Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom: MediaQuery.of(stContext).viewInsets.bottom + 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.location_on, color: Color(0xFF6C757D)),
                          const SizedBox(width: 8),
                          Text(
                            'Choose Area',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, fontFamily: 'Poppins', color: Color(0xFF212529)),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.grey),
                            onPressed: () => Navigator.pop(bContext),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        onChanged: (v) => setSt(() => filter = v),
                        decoration: InputDecoration(
                          hintText: 'Search area name...',
                          prefixIcon: const Icon(Icons.search, color: Color(0xFF6C757D)),
                          filled: true,
                          fillColor: const Color(0xFFF8F9FA),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE9ECEF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.my_location, color: Color(0xFF6C757D), size: 20),
                        ),
                        title: const Text('Current  Location', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text(currentCity, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.grey)),
                        onTap: () {
                          Navigator.pop(bContext);
                          _userHasCustomScope = true;
                          _fetchCurrentLocation();
                        },
                      ),
                      
                      const Divider(height: 24),
                      
                      Text(
                        'Nearby Areas',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF6C757D), fontFamily: 'Poppins', letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 8),
                      
                      SizedBox(
                        height: 220,
                        child: isLoading
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(color: Color(0xFF6C757D), strokeWidth: 2.5),
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'Detecting GPS & Registered Areas...',
                                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Color(0xFF6C757D)),
                                    ),
                                  ],
                                ),
                              )
                            : filter.isNotEmpty
                                ? FutureBuilder<Map<String, String>?>(
                                    future: _validateGooglePlace(filter),
                                    builder: (vContext, vSnapshot) {
                                      if (vSnapshot.connectionState == ConnectionState.waiting) {
                                        return Center(
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: const [
                                              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Color(0xFF6C757D), strokeWidth: 2)),
                                              SizedBox(width: 10),
                                              Text('Searching location worldwide...', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Color(0xFF6C757D))),
                                            ],
                                          ),
                                        );
                                      }

                                      final placeMap = vSnapshot.data;
                                      final validArea = placeMap?['name'];
                                      final subtitle = placeMap?['subtitle'] ?? 'Google Maps Verified Location';

                                      if (validArea != null && validArea.isNotEmpty) {
                                        return ListView(
                                          children: [
                                            if (filteredAreas.isNotEmpty) ...[
                                              for (final area in filteredAreas)
                                                ListTile(
                                                  dense: true,
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                                  leading: const Icon(Icons.place, color: Color(0xFF6C757D), size: 20),
                                                  title: Text(area, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, color: Color(0xFF212529))),
                                                  onTap: () {
                                                    Navigator.pop(bContext);
                                                    setState(() {
                                                      _userHasCustomScope = true;
                                                      _scopeLabel = 'Location($area)';
                                                      _selectedLocation = area;
                                                    });
                                                    _triggerBackgroundNearbyFetch(forceRefresh: true);
                                                    if (_search.text.isNotEmpty) _doSearch(_search.text);
                                                  },
                                                ),
                                              const Divider(),
                                            ],
                                            ListTile(
                                              leading: const Icon(Icons.location_on, color: Color(0xFF6C757D)),
                                              title: Text(validArea, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, color: Color(0xFF212529))),
                                              subtitle: Text(subtitle, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Color(0xFF6C757D))),
                                              trailing: const Icon(Icons.check_circle, color: Color(0xFF6C757D), size: 20),
                                              onTap: () {
                                                Navigator.pop(bContext);
                                                final cleanSub = subtitle.replaceAll('Google Maps Verified Location', '').trim();
                                                final locText = cleanSub.isNotEmpty ? '$validArea, $cleanSub' : validArea;
                                                setState(() {
                                                  _userHasCustomScope = true;
                                                  _scopeLabel = 'Location($locText)';
                                                  _selectedLocation = validArea;
                                                });
                                                _triggerBackgroundNearbyFetch(forceRefresh: true);
                                                if (_search.text.isNotEmpty) _doSearch(_search.text);
                                              },
                                            ),
                                          ],
                                        );
                                      }

                                      return ListTile(
                                        leading: const Icon(Icons.location_off_outlined, color: Colors.redAccent),
                                        title: const Text('Place not found', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, color: Colors.redAccent)),
                                        subtitle: Text('"$filter" is not a recognized location on Google Maps', style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.grey)),
                                        onTap: null,
                                      );
                                    },
                                  )
                                : filteredAreas.isEmpty
                                    ? const Center(child: Text('No registered areas found', style: TextStyle(fontFamily: 'Poppins', color: Colors.grey)))
                                    : ListView.builder(
                                        itemCount: filteredAreas.length,
                                        itemBuilder: (c, i) {
                                          final area = filteredAreas[i];
                                          final isSelected = _formattedScopeLabel.toLowerCase() == area.toLowerCase();

                                          return ListTile(
                                            dense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                            leading: Icon(
                                              Icons.place,
                                              color: isSelected ? const Color(0xFF6C757D) : Colors.grey.shade400,
                                              size: 20,
                                            ),
                                            title: Text(
                                              area,
                                              style: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                color: isSelected ? const Color(0xFF212529) : const Color(0xFF495057),
                                              ),
                                            ),
                                            trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF6C757D), size: 18) : null,
                                            onTap: () {
                                              Navigator.pop(bContext);
                                              setState(() {
                                                _userHasCustomScope = true;
                                                _scopeLabel = 'Location($area)';
                                                _selectedLocation = area;
                                              });
                                              _triggerBackgroundNearbyFetch(forceRefresh: true);
                                              if (_search.text.isNotEmpty) _doSearch(_search.text);
                                            },
                                          );
                                        },
                                      ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String get _formattedScopeLabel {
    String label = _scopeLabel;
    if (label.startsWith('Location(') && label.endsWith(')')) {
      label = label.substring(9, label.length - 1);
    } else if (label.startsWith('Country(') && label.endsWith(')')) {
      label = label.substring(8, label.length - 1);
    }
    return label.trim();
  }

  IconData get _scopeIcon {
    if (_scopeLabel.startsWith('Country(') || _scopeLabel == 'International') {
      return Icons.public;
    }
    return Icons.location_on;
  }

  Widget _buildScopePill() {
    return Padding(
      padding: const EdgeInsets.only(left: 52, right: 32, top: 1, bottom: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(_scopeIcon, size: 16, color: const Color(0xFF6C757D)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              _formattedScopeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6C757D), fontSize: 13, fontFamily: 'Poppins'),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _showChooseAreaPicker,
            child: const Text(
              'Choose Area',
              style: TextStyle(color: Color(0xFF1A73E8), fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Poppins'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              top: 15,
              right: 15,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isSearching ? 0.0 : 1.0,
                child: IgnorePointer(
                  ignoring: _isSearching,
                  child: HeaderMenu(api: widget.api, store: widget.store, session: widget.session, onUpdate: _loadFavs),
                ),
              ),
            ),

            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              top: _isSearching ? 0 : (screenHeight * 0.21),
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isSearching ? 0.0 : 1.0,
                child: IgnorePointer(
                  ignoring: _isSearching,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/images/phone_book_logo_round.png', width: 85, height: 85, fit: BoxFit.contain),
                      const SizedBox(height: 9),
                      const Text(
                        'Fone Book',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Color(0xFF202124), fontFamily: 'Poppins'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Positioned.fill(
              top: 100,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isSearching ? 1.0 : 0.0,
                child: IgnorePointer(
                  ignoring: !_isSearching,
                  child: _buildSearchResultsList(),
                ),
              ),
            ),

            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              top: _isSearching ? 12 : (screenHeight * 0.38),
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSearchCard(),
                  const SizedBox(height: 6),
                  _buildScopePill(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultsList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF6C757D)));
    }

    if (_search.text.trim().isEmpty) {
      final nearbyList = _nearbyProfiles.isNotEmpty ? _nearbyProfiles : (_NearbyCache.profiles ?? []);
      if (_loadingNearby && nearbyList.isEmpty) {
        return const Center(child: CircularProgressIndicator(color: Color(0xFF6C757D)));
      }
      if (nearbyList.isEmpty) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 10, bottom: 6),
            child: Row(
              children: const [
                Icon(Icons.near_me, size: 18, color: Color(0xFF1A73E8)),
                SizedBox(width: 6),
                Text(
                  'Nearby Business Profiles',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF202124),
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 2, bottom: 20),
              itemCount: nearbyList.length,
              itemBuilder: (c, i) {
                final contact = nearbyList[i];
                final isFav = _favs.any((e) => e.phone == contact.phone);
                final isMyContact = _isMyContactMatch(contact);
                final isSponsored = !isMyContact &&
                    ((double.tryParse(contact.priorityBalance) ?? 0.0) > 0 || contact.priority == '0');

                return ContactCard(
                  contact: contact,
                  isFavourite: isFav,
                  showFavouriteIcon: false,
                  isMyContact: isMyContact,
                  isSponsored: isSponsored,
                  isFirstThree: i < 3,
                  onCall: isMyContact ? null : () => widget.store.addToHistory(contact),
                  onFavouriteToggle: () async {
                    await widget.store.toggleFavourite(contact);
                    _loadFavs();
                  },
                  onTap: () {
                    widget.onSearchModeChanged(false);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen(contact: contact))).then((_) {
                      _loadFavs();
                      if (_isSearching) widget.onSearchModeChanged(true);
                    });
                  },
                );
              },
            ),
          ),
        ],
      );
    }
    return _hasSearched && _results.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Column(
                  children: [
                    Icon(Icons.search_off, size: 52, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    const Text(
                      'No contacts found', 
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF202124), fontFamily: 'Poppins')),
                    const SizedBox(height: 4),
                    Text(
                      'Try searching for another name, title, or phone number',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontFamily: 'Poppins')),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(top: 6, bottom: 20),
                itemCount: _results.length,
                itemBuilder: (c, i) {
                  final contact = _results[i];
                  final isFav = _favs.any((e) => e.phone == contact.phone);
                  final isMyContact = _isMyContactMatch(contact);
                  final isSponsored = !isMyContact && 
                                      ((double.tryParse(contact.priorityBalance) ?? 0.0) > 0 || contact.priority == '0');

                  return ContactCard(
                    contact: contact,
                    isFavourite: isFav,
                    showFavouriteIcon: false,
                    isMyContact: isMyContact,
                    isSponsored: isSponsored,
                    isFirstThree: i < 3,
                    onCall: isMyContact ? null : () => widget.store.addToHistory(contact),
                    onFavouriteToggle: () async {
                      await widget.store.toggleFavourite(contact);
                      _loadFavs();
                    },
                    onTap: () {
                      widget.onSearchModeChanged(false);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen(contact: contact))).then((_) {
                        _loadFavs();
                        if (_isSearching) widget.onSearchModeChanged(true);
                      });
                    },
                  );
                },
              );
  }

  Widget _buildSearchCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: InkWell(
        onTap: () {
          if (!_isSearching) {
            setState(() {
              _isSearching = true;
              widget.onSearchModeChanged(true);
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _focus.requestFocus();
            });
          }
        },
        child: Card(
          elevation: 3,
          shadowColor: Colors.black.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                if (_isSearching)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF5F6368)),
                    onPressed: () {
                      setState(() {
                        _isSearching = false;
                        _search.clear();
                        _results.clear();
                        _hasSearched = false;
                        _focus.unfocus();
                        widget.onSearchModeChanged(false);
                      });
                    },
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.search, color: Color(0xFF5F6368)),
                  ),
                Expanded(
                  child: TextField(
                    controller: _search,
                    focusNode: _focus,
                    onTap: () {
                      if (!_isSearching) {
                        setState(() {
                          _isSearching = true;
                          widget.onSearchModeChanged(true);
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _focus.requestFocus();
                        });
                      }
                    },
                    textInputAction: TextInputAction.search,
                    onSubmitted: (val) => _doSearch(val),
                    onChanged: _onSearchChanged,
                    decoration: const InputDecoration(
                      hintText: 'Search name or Keyword...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintStyle: TextStyle(color: Color(0xFF5F6368), fontFamily: 'Poppins'),
                    ),
                    style: const TextStyle(fontSize: 16, fontFamily: 'Poppins', color: Color(0xFF202124)),
                  ),
                ),
              if (_search.text.isNotEmpty) ...[
                IconButton(
                  icon: const Icon(Icons.search, color: Color(0xFF5F6368)),
                  onPressed: () => _doSearch(_search.text),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF5F6368)),
                  onPressed: () {
                    setState(() {
                      _search.clear();
                      _isSearching = false;
                      _results.clear();
                      _hasSearched = false;
                      _focus.unfocus();
                      widget.onSearchModeChanged(false);
                    });
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
}

class _CandidateWrapper {
  final DirectoryContact contact;
  final int priorityTier;
  final int searchScore;
  final double priorityBalance;
  final double distanceMeters;
  final int locationHierarchyTier;
  final String nameLower;

  _CandidateWrapper({
    required this.contact,
    required this.priorityTier,
    required this.searchScore,
    required this.priorityBalance,
    required this.distanceMeters,
    required this.locationHierarchyTier,
    required this.nameLower,
  });
}
