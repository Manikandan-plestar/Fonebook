import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
          
          if (p.additionalServices != null && p.additionalServices!.isNotEmpty) {
            _serviceControllers.clear();
            for (var s in p.additionalServices!.split(',')) {
              if (s.trim().isNotEmpty) _serviceControllers.add(TextEditingController(text: s.trim()));
            }
            if (_serviceControllers.isEmpty) _serviceControllers.add(TextEditingController());
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
      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
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

      final services = _serviceControllers.map((e) => e.text.trim()).where((e) => e.isNotEmpty).join(', ');
      final phones = _contactControllers.map((e) => "${e['name']!.text.trim()}:${e['val']!.text.trim()}")
          .where((e) => e.split(':')[0].isNotEmpty && e.split(':')[1].isNotEmpty)
          .join(', ');

      String keywords = widget.phone == null ? _keywords.join(', ') : (_existingProfile?.keyword ?? '');

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
        'keyword': keywords,
        'keywords': keywords,
        'about': _aboutController.text.trim(),
        'landlineno': _landlineController.text.trim(),
        'wpno': _wpController.text.trim(),
        'skypeno': _skypeController.text.trim(),
        'services': services,
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
          if (widget.phone != null) Navigator.pop(context);
          else Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AppShell()));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.toString())));
      }
    } catch (e) {
      debugPrint("Save error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _getLabel(String type) {
    switch (type) {
      case 'name': return 'Full name';
      case 'title': return 'Profession';
      case 'about': return 'About / Bio / Business Description';
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
                    Text(isEdit ? 'Edit Profile' : 'Add Profile', 
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
                    
                    if (isEdit) _buildTextField(_phoneController, 'Phone number', keyboardType: TextInputType.phone, isReadOnly: true),
                    _buildTextField(_nameController, _getLabel('name')),
                    _buildTextField(_titleController, _getLabel('title')),
                    _buildTextField(_aboutController, _getLabel('about'), maxLines: 5),
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
                                Icon(Icons.location_on, color: Colors.blue, size: 17),
                                SizedBox(width: 4),
                                Text('Get Address from GPS', 
                                               style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Poppins')),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () => setState(() => _locationController.clear()),
                            child: const Text('Clear Address', 
                                           style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Poppins', decoration: TextDecoration.none)),
                          ),
                        ],
                      ),
                    ),

                    if (!isEdit) ...[
                      const SizedBox(height: 10),
                      const Divider(color: Color(0xFFD7D7D7)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 30, vertical: 10),
                        child: Align(alignment: Alignment.centerLeft, child: Text('Keywords', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12, fontFamily: 'Poppins'))),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 30),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _tagController,
                                onSubmitted: (_) => _addTag(),
                                decoration: const InputDecoration(hintText: 'Add Keyword...', border: UnderlineInputBorder()),
                              ),
                            ),
                            TextButton(onPressed: _addTag, child: const Text('Add')),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 30),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _keywords.map((k) => _buildChip(k)).toList(),
                        ),
                      ),
                    ],

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

                    const SizedBox(height: 25),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6C757D),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                          ),
                          child: _isLoading ? const CircularProgressIndicator(color: Color(0xFF272000)) 
                                           : Text(isEdit ? 'Update' : 'Add', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Poppins')),
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

  Widget _buildTextField(TextEditingController controller, String hint, {bool isReadOnly = false, TextInputType? keyboardType, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: TextField(
        controller: controller,
        readOnly: isReadOnly,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: const TextStyle(color: Color(0xFF212529), fontSize: 15, fontFamily: 'Poppins'),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF6C757D), fontFamily: 'Poppins'),
          filled: true,
          fillColor: isReadOnly ? const Color(0xFFE9ECEF) : const Color(0xFFF1F3F4),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
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
}
