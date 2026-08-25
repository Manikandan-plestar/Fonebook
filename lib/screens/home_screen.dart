import 'dart:async';
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
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 4),
        );

        if (!kIsWeb) {
          List<Placemark> placemarks = await Geocoding().placemarkFromCoordinates(position.latitude, position.longitude);
          if (placemarks.isNotEmpty) {
            Placemark p = placemarks.first;
            final subLocality = p.subLocality?.trim();
            final locality = p.locality?.trim();

            String cityArea = "Current Location";
            if (subLocality != null && subLocality.isNotEmpty && locality != null && locality.isNotEmpty) {
              cityArea = "$subLocality, $locality";
            } else if (locality != null && locality.isNotEmpty) {
              cityArea = locality;
            }

            if (mounted && !_userHasCustomScope) {
              setState(() {
                _scopeLabel = "Location($cityArea)";
                _selectedLocation = cityArea;
              });
              if (_search.text.isNotEmpty) _doSearch(_search.text);
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
        list.addAll(res.map((e) => MyContactItem.fromJson(Map<String, dynamic>.from(e))));
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

  Future<void> _doSearch(String q) async {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _isSearching = true;
      _hasSearched = true;
    });

    try {
      unawaited(widget.api.post('savesearch', {
        'tag': q.trim(),
        'country': widget.session.country ?? '',
        'location': widget.session.place1 ?? '',
      }));

      await _loadLocalContacts();

      final cleanQ = query.replaceAll(RegExp(r'[\s\-\+\(\)]'), '');

      final localMatches = _localContacts.where((c) {
        final cleanP = c.phone.replaceAll(RegExp(r'[\s\-\+\(\)]'), '');
        final nameMatch = c.name.toLowerCase().contains(query);
        final titleMatch = c.title.toLowerCase().contains(query);
        final phoneMatch = cleanQ.isNotEmpty && cleanP.contains(cleanQ);
        return nameMatch || titleMatch || phoneMatch;
      }).map((c) => DirectoryContact(
        name: c.name,
        service: c.title,
        phone: c.phone,
        priority: '1',
        priorityBalance: '0',
        category: 'my_contact',
        showContact: 'mwelsf',
      )).toList();

      List<DirectoryContact> apiResults = [];

      String apiLocation = '';
      if (_scopeLabel.startsWith('Location(') || _scopeLabel.startsWith('Country(')) {
        apiLocation = _selectedLocation ?? '';
      }

      final data = await widget.api.get('check-contact', {
        'type': 'search',
        'query': q.trim(),
        'location': apiLocation,
      });

      if (data is List) {
        apiResults = data
            .where((e) => e != null && e is Map && e['name'] != null && e['name'].toString().trim().isNotEmpty)
            .map((e) => DirectoryContact.fromJson(e))
            .where((e) {
              final cleanPhone = e.phone.replaceAll(RegExp(r'[\s\-\+\(\)]'), '');
              final serviceMatch = e.service.toLowerCase().contains(query);
              final keywordMatch = (e.keyword?.toLowerCase().contains(query) ?? false) ||
                                   (e.tags?.toLowerCase().contains(query) ?? false) ||
                                   (e.additionalServices?.toLowerCase().contains(query) ?? false);
              final nameMatch = e.name.toLowerCase().contains(query);
              final phoneMatch = cleanQ.isNotEmpty && cleanPhone.contains(cleanQ);

              // Allow match by profession (service), keywords, name, or phone number
              final textMatch = serviceMatch || keywordMatch || nameMatch || phoneMatch;
              if (!textMatch) return false;

              final who = (e.whoContact ?? 'international').toLowerCase();
              if (who == 'international' || who == 'all' || who.isEmpty) {
                return true;
              }

              final isLocationSearch = _scopeLabel.startsWith('Location(');
              final isCountrySearch = _scopeLabel.startsWith('Country(');
              final isInternationalSearch = _scopeLabel == 'International';

              if (who == 'country') {
                return isCountrySearch || isInternationalSearch;
              }

              if (who == 'location') {
                return isLocationSearch;
              }

              return true;
            })
            .where((e) => !localMatches.any((l) {
              final lClean = l.phone.replaceAll(RegExp(r'[\s\-\+\(\)]'), '');
              final eClean = e.phone.replaceAll(RegExp(r'[\s\-\+\(\)]'), '');
              return lClean.isNotEmpty && eClean.isNotEmpty && (lClean == eClean || lClean.endsWith(eClean) || eClean.endsWith(lClean));
            }))
            .toList();
      }

      final sponsoredMatches = <DirectoryContact>[];
      final normalApiMatches = <DirectoryContact>[];

      for (final item in apiResults) {
        final bal = double.tryParse(item.priorityBalance) ?? 0.0;
        final isPromoted = bal > 0;
        if (isPromoted) {
          sponsoredMatches.add(item);
        } else {
          normalApiMatches.add(item);
        }
      }

      // Prioritize primary Service matches first, followed by Keyword matches
      normalApiMatches.sort((a, b) {
        final aService = a.service.toLowerCase().contains(query);
        final bService = b.service.toLowerCase().contains(query);
        if (aService && !bService) return -1;
        if (!aService && bService) return 1;
        return 0;
      });

      final combined = [...localMatches, ...sponsoredMatches, ...normalApiMatches];

      setState(() {
        _results = combined;
        _localMatchCount = localMatches.length;
        _sponsoredCount = sponsoredMatches.length;
      });

      if (sponsoredMatches.isNotEmpty) {
        _processSponsoredDeductions(sponsoredMatches, query);
      }
    } catch (e) {
      debugPrint("Search error: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _processSponsoredDeductions(List<DirectoryContact> sponsoredList, String query) async {
    const double impressionCost = 1.0; // ₹1.00 per search display
    final String loggedInPhone = widget.session.phone ?? '';
    final String loggedInEmail = widget.session.email ?? '';

    for (final item in sponsoredList) {
      // Skip deduction if the logged-in user (profile owner) searches their own profile!
      if ((loggedInPhone.isNotEmpty && item.phone == loggedInPhone) ||
          (loggedInEmail.isNotEmpty && item.email == loggedInEmail)) {
        debugPrint("Skipping impression deduction for profile owner: ${item.phone}");
        continue;
      }

      final String dedKey = "${query}_${item.phone}";
      if (_deductedPhonesThisSession.contains(dedKey)) {
        continue; // Skip duplicate deduction for same query and profile
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

  Future<void> _fetchCurrentLocation() async {
    setState(() => _loading = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        
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
        if (_search.text.isNotEmpty) _doSearch(_search.text);
      }
    } catch (e) {
      debugPrint("Location error: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showScopeMenuAt(BuildContext btnContext) {
    final RenderBox button = btnContext.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(btnContext).overlay!.context.findRenderObject() as RenderBox;

    final Offset topBelow = button.localToGlobal(Offset(0, button.size.height + 8), ancestor: overlay);
    final Offset bottomRight = button.localToGlobal(button.size.bottomRight(Offset(0, 8)), ancestor: overlay);

    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(topBelow, bottomRight),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: btnContext,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 6,
      color: const Color(0xFFFFF9E6),
      items: const [
        PopupMenuItem(value: 'International', child: Text('International', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600))),
        PopupMenuItem(value: 'Country', child: Text('Country', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600))),
        PopupMenuItem(value: 'Location', child: Text('Choose Area', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600))),
      ],
    ).then((value) async {
      if (value == 'International') {
        setState(() {
          _userHasCustomScope = true;
          _scopeLabel = 'International';
          _selectedLocation = null;
        });
        if (_search.text.isNotEmpty) _doSearch(_search.text);
      } else if (value == 'Country') {
        final res = await showDialog<String>(
          context: context,
          builder: (c) => const CountryPickerDialog(title: 'Select Country', items: countriesList),
        );
        if (res != null) {
          final name = res.substring(res.indexOf(' ') + 1).trim();
          setState(() {
            _userHasCustomScope = true;
            _scopeLabel = 'Country($name)';
            _selectedLocation = name;
          });
          if (_search.text.isNotEmpty) _doSearch(_search.text);
        }
      } else if (value == 'Location') {
        _showChooseAreaPicker();
      }
    });
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
        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        
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

    // Fetch registered areas from API for this city
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
                        title: const Text('Auto-detect GPS Location', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text(currentCity, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.grey)),
                        onTap: () {
                          Navigator.pop(bContext);
                          _userHasCustomScope = true;
                          _fetchCurrentLocation();
                        },
                      ),
                      
                      const Divider(height: 24),
                      
                      Text(
                        'GPS DETECTED & REGISTERED AREAS',
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
          Builder(
            builder: (btnContext) {
              return InkWell(
                onTap: () => _showScopeMenuAt(btnContext),
                child: const Text(
                  'Change',
                  style: TextStyle(color: Color(0xFF1A73E8), fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Poppins'),
                ),
              );
            },
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
            // Top Right Header Menu
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

            // Center Logo & Title when NOT searching
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
                      Image.asset('assets/images/Small-icon.png', width: 85, height: 85, fit: BoxFit.contain),
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

            // Search Results List (positioned below top search bar & scope pill)
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

            // Persistent Single Search Bar & Scope Pill (Animates position smoothly)
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
    return _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C757D)))
        : _hasSearched && _results.isEmpty && _search.text.isNotEmpty
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
                  final isMyContact = i < _localMatchCount || 
                                      contact.category == 'my_contact' ||
                                      _localContacts.any((l) {
                                        final lPhone = l.phone.replaceAll(RegExp(r'[\s\-\+\(\)]'), '');
                                        final cPhone = contact.phone.replaceAll(RegExp(r'[\s\-\+\(\)]'), '');
                                        return lPhone.isNotEmpty && cPhone.isNotEmpty && lPhone == cPhone;
                                      });
                  final isSponsored = !isMyContact && 
                                      i >= _localMatchCount && 
                                      i < (_localMatchCount + _sponsoredCount);

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
                    onChanged: (v) {
                      if (v.trim().isEmpty) {
                        setState(() {
                          _isSearching = false;
                          _results.clear();
                          _hasSearched = false;
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
                    },
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
