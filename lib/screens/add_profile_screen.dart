import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:country_state_city/country_state_city.dart' as csc;
import 'package:http/http.dart' as http;
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../models/user_session.dart';
import '../models/contact.dart';
import '../services/location_service.dart';
import '../widgets/app_header.dart';
import 'app_shell.dart';
import 'profile_list_screen.dart';

class AddProfileScreen extends StatefulWidget {
  final String email;
  final String? phone;
  final String? initialPhone;
  const AddProfileScreen({super.key, required this.email, this.phone, this.initialPhone});
  @override
  State<AddProfileScreen> createState() => _AddProfileScreenState();
}

class _AddProfileScreenState extends State<AddProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _titleController;
  late final TextEditingController _aboutController;
  late final TextEditingController _wpController;
  late final TextEditingController _landlineController;
  late final TextEditingController _skypeController;
  
  late final TextEditingController _locationController;

  csc.Country? _country;
  csc.State? _state;
  csc.City? _city;

  final _tagController = TextEditingController();
  List<String> _keywords = [];

  final List<TextEditingController> _serviceControllers = [TextEditingController()];
  final List<Map<String, TextEditingController>> _contactControllers = [{'name': TextEditingController(), 'val': TextEditingController()}];

  XFile? _image;
  Uint8List? _imageBytes;
  Uint8List? _existingImageBytes;
  bool _isLoading = false;
  bool _showMobile = true;
  bool _showWhatsapp = true;
  String _whoContact = 'international';
  final _api = ApiClient();
  final _store = SessionStore();
  DirectoryContact? _existingProfile;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController(text: widget.initialPhone ?? widget.phone);
    _titleController = TextEditingController();
    _aboutController = TextEditingController();
    _wpController = TextEditingController(text: widget.initialPhone ?? widget.phone);
    _landlineController = TextEditingController();
    _skypeController = TextEditingController();
    
    _locationController = TextEditingController();
    
    if (widget.phone != null && widget.initialPhone == null) {
      _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final res = await _api.get('check_search_type1', {'email': widget.email});
      if (res is List && res.isNotEmpty) {
        DirectoryContact p;
        if (widget.phone != null) {
          final list = res.map((e) => DirectoryContact.fromJson(e)).toList();
          final target = widget.phone!.replaceAll(RegExp(r'[^0-9]'), '');
          p = list.firstWhere(
            (e) => e.phone.replaceAll(RegExp(r'[^0-9]'), '') == target, 
            orElse: () => list.first
          );
        } else {
          p = DirectoryContact.fromJson(res[0]);
        }
        
        final allCountries = await LocationService.getCountries();
        csc.Country? countryObj;
        csc.State? stateObj;
        csc.City? cityObj;

        // Fallback location parsing
        String? countryName, stateName, cityName;
        if (p.state != null && p.state!.isNotEmpty && p.city != null && p.city!.isNotEmpty) {
           stateName = p.state;
           cityName = p.city;
           if (p.location != null && p.location!.isNotEmpty) {
              final parts = p.location!.split(',').map((e) => e.trim()).toList();
              if (parts.isNotEmpty) countryName = parts.last;
           }
        } else if (p.location != null && p.location!.isNotEmpty) {
          final parts = p.location!.split(',').map((e) => e.trim()).toList();
          if (parts.length >= 3) {
            cityName = parts[0];
            stateName = parts[1];
            countryName = parts[2];
          } else if (parts.isNotEmpty) {
            countryName = parts.last;
          }
        }

        if (countryName != null) {
          for (var c in allCountries) {
            if (c.name == countryName) {
              countryObj = c;
              break;
            }
          }
        }

        if (countryObj != null && stateName != null) {
          final allStates = await LocationService.getStates(countryObj.isoCode);
          for (var s in allStates) {
            if (s.name == stateName) {
              stateObj = s;
              break;
            }
          }
        }

        if (countryObj != null && stateObj != null && cityName != null) {
          final allCities = await LocationService.getCities(countryObj.isoCode, stateObj.isoCode);
          for (var c in allCities) {
            if (c.name == cityName) {
              cityObj = c;
              break;
            }
          }
        }

        setState(() {
          _existingProfile = p;
          _country = countryObj;
          _state = stateObj;
          _city = cityObj;
          
          _locationController.text = p.location ?? '';
          _nameController.text = p.name;
          _phoneController.text = p.phone;
          _titleController.text = p.service;
          _aboutController.text = p.about ?? '';
          _wpController.text = p.whatsapp ?? p.phone;
          _landlineController.text = p.landline ?? '';
          _skypeController.text = p.skype ?? '';
          
          if (p.imageUrl.isNotEmpty) {
            _downloadImage(p.imageUrl);
          }
          
          _showMobile = p.showContact.contains('m');
          _showWhatsapp = p.showContact.contains('w');
          final rawWho = (p.whoContact ?? 'international').toLowerCase();
          if (rawWho == 'country') {
            _whoContact = 'country';
          } else if (rawWho == 'location') {
            _whoContact = 'location';
          } else {
            _whoContact = 'international';
          }

          final rawCombined = <String>[];
          if (p.additionalServices != null && p.additionalServices!.isNotEmpty) {
            for (var s in p.additionalServices!.split(',')) {
              final t = s.trim();
              if (t.isNotEmpty && !rawCombined.contains(t)) rawCombined.add(t);
            }
          }
          if (p.keyword != null && p.keyword!.isNotEmpty) {
            for (var k in p.keyword!.split(',')) {
              final t = k.trim();
              if (t.isNotEmpty && !rawCombined.contains(t)) rawCombined.add(t);
            }
          }

          _keywords = List.from(rawCombined);

          _serviceControllers.clear();
          for (var s in rawCombined) {
            _serviceControllers.add(TextEditingController(text: s));
          }
          if (_serviceControllers.isEmpty) {
            _serviceControllers.add(TextEditingController());
          }

          if (p.additionalPhones != null && p.additionalPhones!.isNotEmpty) {
            _contactControllers.clear();
            for (var pair in p.additionalPhones!.split(', ')) {
              final parts = pair.split(':');
              if (parts.length >= 2) {
                _contactControllers.add({
                  'name': TextEditingController(text: parts[0]),
                  'val': TextEditingController(text: parts[1]),
                });
              }
            }
            if (_contactControllers.isEmpty) _contactControllers.add({'name': TextEditingController(), 'val': TextEditingController()});
          }
        });
      }
    } catch (e) {
      debugPrint("Load profile error: $e");
    }
    setState(() => _isLoading = false);
  }

  Future<void> _downloadImage(String url) async {
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        _existingImageBytes = resp.bodyBytes;
      }
    } catch (e) {
      debugPrint("Download image error: $e");
    }
  }

  void _saveShow() async {
    final phone = _phoneController.text.trim();
    if (phone.isNotEmpty) {
      final showStr = '${_showMobile ? 'm' : ''}${_showWhatsapp ? 'w' : ''}';
      await _api.post('save_show', {'phone': phone, 'show': showStr});
    }
  }

  void _saveWho(String val) async {
    setState(() => _whoContact = val);
    final phone = _phoneController.text.trim();
    if (phone.isNotEmpty) {
      await _api.post('save_access', {'phone': phone, 'who_contact': val});
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 50);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _image = pickedFile;
        _imageBytes = bytes;
      });
    }
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isNotEmpty) {
      // Check if verified (usually 0 for new profiles)
      bool isVerified = _existingProfile?.verified == 1;
      if (!isVerified && _keywords.length >= 5) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only 5 Keywords allowed for Free users')));
        _tagController.clear();
        return;
      }
      setState(() {
        if (!_keywords.any((t) => t.toLowerCase() == tag.toLowerCase())) {
          _keywords.add(tag);
        }
        _tagController.clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() => _keywords.remove(tag));
  }

  Widget _buildChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFCBCBCB),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(color: Color(0xFF232323), fontSize: 14, fontFamily: 'Poppins', fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => _removeTag(text),
            child: const Text('X', style: TextStyle(color: Color(0xFF232323), fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
          ),
        ],
      ),
    );
  }

  Future<void> _getAddress() async {
    setState(() => _isLoading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enable GPS.')));
        setState(() => _isLoading = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location denied.')));
          setState(() => _isLoading = false);
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final placemarks = await Geocoding().placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final street = place.street ?? '';
        final locality = place.locality ?? '';
        final state = place.administrativeArea ?? '';
        final country = place.country ?? '';
        
        String fullAddress = "$street, $locality, $state, $country".replaceAll(RegExp(r', , '), ', ');
        
        final allCountries = await LocationService.getCountries();
        csc.Country? countryObj;
        csc.State? stateObj;
        csc.City? cityObj;

        for (var c in allCountries) {
          if (c.name == country) { countryObj = c; break; }
        }
        if (countryObj != null) {
          final states = await LocationService.getStates(countryObj.isoCode);
          stateObj = states.firstWhere((s) => s.name == state, orElse: () => states.first);
          final cities = await LocationService.getCities(countryObj.isoCode, stateObj.isoCode);
          cityObj = cities.firstWhere((c) => c.name == locality, orElse: () => cities.first);
        }

        setState(() {
          _locationController.text = fullAddress;
          _country = countryObj;
          _state = stateObj;
          _city = cityObj;
        });

        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location fetched from GPS')));
      }
    } catch (e) {
      debugPrint("GPS Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final service = _titleController.text.trim();

    if (name.isEmpty || phone.isEmpty || service.isEmpty || _country == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill Name, Title, and GPS Address')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final country = _country?.name ?? '';
      final state = _state?.name ?? '';
      final city = _city?.name ?? '';
      final location = _locationController.text.trim();
      final location1 = "$city, $state";

      String? imageBase64;
      if (_imageBytes != null) imageBase64 = base64Encode(_imageBytes!);
      else if (_existingImageBytes != null) imageBase64 = base64Encode(_existingImageBytes!);

      final serviceItems = _serviceControllers.map((e) => e.text.trim()).where((e) => e.isNotEmpty).toList();
      final allUnified = <String>[];
      for (final k in _keywords) {
        if (k.isNotEmpty && !allUnified.contains(k)) allUnified.add(k);
      }
      for (final s in serviceItems) {
        if (s.isNotEmpty && !allUnified.contains(s)) allUnified.add(s);
      }
      final unifiedStr = allUnified.join(', ');

      final phones = _contactControllers.map((e) => "${e['name']!.text.trim()}:${e['val']!.text.trim()}")
          .where((e) => e.split(':')[0].isNotEmpty && e.split(':')[1].isNotEmpty)
          .join(', ');

      final Map<String, String?> body = {
        'name': name,
        'phone': phone,
        'phone1': widget.phone ?? phone,
        'phone_no': phone,
        'service': service,
        'state': state,
        'city': city,
        'location': location,
        'location1': location1,
        'keyword': unifiedStr,
        'keywords': unifiedStr,
        'about': _aboutController.text.trim(),
        'landlineno': _landlineController.text.trim(),
        'wpno': _wpController.text.trim(),
        'skypeno': _skypeController.text.trim(),
        'services': unifiedStr,
        'output': phones,
        'phonenos': phones,
        'category': '',
        'email': widget.email,
        'publish': _existingProfile?.publish ?? 'yes',
        'verification': _existingProfile?.verified.toString() ?? '0',
        'owner_email': widget.email,
      };

      if (imageBase64 != null) {
        body['imagebolb'] = imageBase64;
        body['filename'] = "${name}_${phone.replaceAll('+', '')}.jpg";
      }

      final Map<String, String> finalBody = {};
      body.forEach((key, value) { if (value != null) finalBody[key] = value; });

      final endpoint = widget.phone != null ? 'savecontacts' : 'savecontacts1';
      final res = await _api.post(endpoint, finalBody);
      if (res.toString().toLowerCase().contains('success')) {
        final showStr = '${_showMobile ? 'm' : ''}${_showWhatsapp ? 'w' : ''}';
        unawaited(_api.post('save_show', {'phone': phone, 'show': showStr}));
        unawaited(_api.post('save_access', {'phone': phone, 'who_contact': _whoContact}));

        final currentSession = await _store.read();
        final session = UserSession(
          phone: phone,
          email: widget.email,
          place: location,
          place1: location1,
          country: country,
          image: _image != null ? 'updated' : currentSession.image,
          premium: currentSession.premium || (_existingProfile?.verified == 1),
        );
        DirectoryContact.bust(phone);
        await _store.save(session);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.phone != null ? 'Profile updated successfully' : 'Profile created successfully'),
              backgroundColor: Colors.green,
            ),
          );
          final hasAppShell = context.findAncestorWidgetOfExactType<AppShell>() != null;
          if (widget.phone != null && Navigator.canPop(context)) {
            Navigator.pop(context);
          } else if (hasAppShell) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ProfileListScreen(
                  api: _api,
                  session: session,
                  mode: 'profile',
                ),
              ),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const AppShell(showProfileList: true),
              ),
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.toString())));
      }
    } catch (e) {
      debugPrint("Save error: $e");
      if (mounted) {
        String msg = 'Error saving profile: $e';
        if (e.toString().contains('SocketException') || e.toString().contains('Network is unreachable')) {
          msg = 'No internet connection. Please check your network connection.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteProfile() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.delete_forever, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text(
              'Delete Profile',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF212529)),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete this profile permanently? This action cannot be undone.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Color(0xFF495057)),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: Color(0xFF6C757D)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              'Delete',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        final phone = _phoneController.text.trim();
        final rawPhone = widget.phone ?? phone;
        final targetPhone = widget.phone != null && widget.phone!.isNotEmpty ? widget.phone! : phone;
        final existingId = _existingProfile?.id ?? '';

        final Map<String, String> deletePayload = {
          if (existingId.isNotEmpty) 'id': existingId,
          'name': _nameController.text.trim(),
          'phone': targetPhone,
          'phone_no': targetPhone,
          'phone1': rawPhone,
          'service': _titleController.text.trim(),
          'publish': 'no',
          'email': widget.email,
          'owner_email': widget.email,
          'action': 'delete',
          'delete': 'yes',
          'type': 'delete',
        };

        // 1. Update DB publish status to 'no' via save_publish and savecontacts
        try {
          final res = await _api.post('save_publish', {'phone': targetPhone, 'publish': 'no'});
          debugPrint("save_publish res: $res");
        } catch (e) {
          debugPrint("save_publish error: $e");
        }
        try {
          final res = await _api.post('savecontacts', deletePayload);
          debugPrint("savecontacts publish=no res: $res");
        } catch (e) {
          debugPrint("savecontacts error: $e");
        }

        // 2. Post to delete_contact and delete_my_contact to remove permanently from DB table
        try {
          final res = await _api.post('delete_contact', deletePayload);
          debugPrint("delete_contact res: $res");
        } catch (e) {
          debugPrint("delete_contact error: $e");
        }
        try {
          final res = await _api.post('delete_my_contact', deletePayload);
          debugPrint("delete_my_contact res: $res");
        } catch (e) {
          debugPrint("delete_my_contact error: $e");
        }

        DirectoryContact.bust(phone);
        DirectoryContact.bust(rawPhone);
        DirectoryContact.bust(targetPhone);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile deleted permanently.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context, true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting profile: $e')),
        );
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  String _getLabel(String type) {
    switch (type) {
      case 'name': return 'Full name';
      case 'title': return 'Profession';
      case 'about': return 'About';
      case 'skype': return 'Skype ID / Website URL';
      case 'services': return 'Services';
      case 'service_item': return 'Service Item';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.phone != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Fone Book',
              onBack: () => Navigator.pop(context),
              showMenu: true,
              api: _api,
              session: UserSession(email: widget.email, phone: widget.phone),
              store: _store,
            ),
            Expanded(
              child: _isLoading && isEdit && _existingProfile == null 
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 30),
                    Text(isEdit ? 'Edit Profile' : 'Business Profile', 
                         style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF232323), fontFamily: 'Poppins')),
                    const SizedBox(height: 20),
                    
                    GestureDetector(
                      onTap: _pickImage,
                      child: Stack(
                        children: [
                          Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
                              image: _imageBytes != null 
                                ? DecorationImage(image: MemoryImage(_imageBytes!), fit: BoxFit.cover)
                                : (_existingProfile?.imageUrl.isNotEmpty == true 
                                    ? DecorationImage(image: NetworkImage(_existingProfile!.imageUrl), fit: BoxFit.cover)
                                    : null),
                            ),
                            child: (_imageBytes == null && (_existingProfile?.imageUrl.isEmpty ?? true))
                              ? const Icon(Icons.person, size: 60, color: Color(0xFFBDBDBD)) 
                              : null,
                          ),
                          Positioned(
                            bottom: 2,
                            right: 2,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Color(0xFF6C757D),
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                              ),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 22),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 30),
                    
                    _buildTextField(_phoneController, 'Phone number', keyboardType: TextInputType.phone, isReadOnly: true),
                    _buildTextField(_wpController, 'WhatsApp Number', keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                    _buildTextField(_nameController, _getLabel('name')),
                    _buildTextField(_titleController, _getLabel('title')),
                    _buildTextField(_aboutController, _getLabel('about'), maxLines: 5, inputFormatters: [LengthLimitingTextInputFormatter(600)]),
                    _buildTextField(_locationController, 'Business location (GPS Only)', isReadOnly: true, maxLines: 3),
                    
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          InkWell(
                            onTap: _getAddress,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.location_on, color: Color(0xFF495057), size: 17),
                                SizedBox(width: 4),
                                Text('Get Address', 
                                               style: TextStyle(color: Color(0xFF343A40), fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Poppins')),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () => setState(() => _locationController.clear()),
                            child: const Text('Clear ', 
                                           style: TextStyle(color: Color(0xFF495057), fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Poppins', decoration: TextDecoration.none)),
                          ),
                        ],
                      ),
                    ),

                    if (isEdit) ...[
                      const SizedBox(height: 10),
                      const Divider(color: Color(0xFFD7D7D7)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                        child: Align(alignment: Alignment.centerLeft, child: Text(_getLabel('services'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 15, fontFamily: 'Poppins'))),
                      ),
                      ..._serviceControllers.asMap().entries.map((entry) {
                        int idx = entry.key;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            children: [
                              Expanded(child: _buildTextField(_serviceControllers[idx], _getLabel('service_item'))),
                              IconButton(icon: const Icon(Icons.delete, color: Colors.grey), onPressed: () => setState(() => _serviceControllers.removeAt(idx))),
                            ],
                          ),
                        );
                      }),
                      TextButton(onPressed: () => setState(() => _serviceControllers.add(TextEditingController())), child: const Text('+Add More', style: TextStyle(color: Color(0xFF6C757D), fontWeight: FontWeight.bold, fontFamily: 'Poppins'))),
                    ],

                    const SizedBox(height: 10),

                    // Access / Target Section Card
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE9ECEF)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Target',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF212529), fontFamily: 'Poppins'),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Who can contact you',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF495057), fontFamily: 'Poppins'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 160,
                                  child: DropdownButtonFormField<String>(
                                    value: _whoContact,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      filled: true,
                                      fillColor: const Color(0xFFFFF3CD),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: const BorderSide(color: Color(0xFFFFECB3)),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: const BorderSide(color: Color(0xFFFFECB3)),
                                      ),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'international',
                                        child: Text('International', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF856404), fontFamily: 'Poppins')),
                                      ),
                                      DropdownMenuItem(
                                        value: 'country',
                                        child: Text('Country', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF856404), fontFamily: 'Poppins')),
                                      ),
                                      DropdownMenuItem(
                                        value: 'location',
                                        child: Text('Current Location', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF856404), fontFamily: 'Poppins')),
                                      ),
                                    ],
                                    onChanged: (v) => _saveWho(v!),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 25),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: widget.phone != null
                          ? Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 52,
                                    child: OutlinedButton.icon(
                                      onPressed: _isLoading ? null : _deleteProfile,
                                     
                                      label: const Text(
                                        'Delete',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red, fontFamily: 'Poppins'),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: Colors.red, width: 1.5),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: SizedBox(
                                    height: 52,
                                    child: ElevatedButton(
                                      onPressed: _isLoading ? null : _save,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF6C757D),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: _isLoading 
                                          ? const SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                            )
                                          : const Text(
                                              'Update',
                                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Poppins'),
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _save,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6C757D),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: _isLoading 
                                    ? const CircularProgressIndicator(color: Color(0xFF272000)) 
                                    : const Text('Add', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Poppins')),
                              ),
                            ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller, 
    String hint, {
    bool isReadOnly = false, 
    TextInputType? keyboardType, 
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    IconData? prefixIcon,
  }) {
    Widget iconWidget;
    final hLower = hint.toLowerCase();
    
    if (hLower.contains('whatsapp')) {
      iconWidget = Padding(
        padding: const EdgeInsets.all(12),
        child: Image.asset(
          'assets/images/whatsapp.png',
          width: 20,
          height: 20,
          color: const Color(0xFF6C757D),
          fit: BoxFit.contain,
        ),
      );
    } else {
      IconData defaultIcon;
      if (prefixIcon != null) {
        defaultIcon = prefixIcon;
      } else if (hLower.contains('phone')) {
        defaultIcon = Icons.phone_outlined;
      } else if (hLower.contains('name')) {
        defaultIcon = Icons.person_outline;
      } else if (hLower.contains('profession') || hLower.contains('title') || hLower.contains('actor') || hLower.contains('service')) {
        defaultIcon = Icons.work_outline;
      } else if (hLower.contains('about')) {
        defaultIcon = Icons.info_outline;
      } else if (hLower.contains('location') || hLower.contains('gps') || hLower.contains('address')) {
        defaultIcon = Icons.location_on_outlined;
      } else {
        defaultIcon = Icons.edit_note_outlined;
      }
      iconWidget = Icon(defaultIcon, color: const Color(0xFF6C757D), size: 20);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: TextField(
        controller: controller,
        readOnly: isReadOnly,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        maxLines: maxLines,
        style: const TextStyle(color: Color(0xFF212529), fontSize: 15, fontFamily: 'Poppins'),
        decoration: InputDecoration(
          prefixIcon: iconWidget,
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF6C757D), fontFamily: 'Poppins'),
          filled: true,
          fillColor: isReadOnly ? const Color(0xFFE9ECEF) : const Color(0xFFF1F3F4),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        ),
      ),
    );
  }

  Widget _buildPickerField(TextEditingController controller, String hint, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: IgnorePointer(
          child: TextField(
            controller: controller,
            style: const TextStyle(color: Color(0xFF212529), fontSize: 15, fontFamily: 'Poppins'),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFF6C757D), fontFamily: 'Poppins'),
              filled: true,
              fillColor: const Color(0xFFF1F3F4),
              suffixIcon: const Icon(Icons.arrow_drop_down, color: Color(0xFF6C757D)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile(String title, bool value, ValueChanged<bool> onChanged) {
    bool canToggle = true;
    if (title == 'Whatsapp' && _wpController.text.trim().isEmpty) canToggle = false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                color: canToggle ? const Color(0xFF212529) : Colors.grey,
                fontFamily: 'Poppins',
              ),
            ),
          ),
          Switch(
            value: value && canToggle,
            onChanged: (v) {
              if (!canToggle && v) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("You didn't enter the ${title.toLowerCase()}.")));
                return;
              }
              onChanged(v);
            },
            activeColor: const Color(0xFFD7B41A),
          ),
        ],
      ),
    );
  }
}
