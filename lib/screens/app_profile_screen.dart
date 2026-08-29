import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../services/dial_codes.dart';
import '../models/user_session.dart';
import '../widgets/app_header.dart';
import 'app_shell.dart';
import 'login_screen.dart';

class AppProfileScreen extends StatefulWidget {
  final ApiClient api;
  final UserSession session;
  final bool isMandatoryOnboarding;

  const AppProfileScreen({
    super.key,
    required this.api,
    required this.session,
    this.isMandatoryOnboarding = false,
  });

  @override
  State<AppProfileScreen> createState() => _AppProfileScreenState();
}

class _AppProfileScreenState extends State<AppProfileScreen> {
  bool _isEditing = false;
  bool _isLoading = true;
  bool _isSaving = false;

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();

  Map<String, String> _selectedCountry = dialCodes.firstWhere((e) => e['dial_code'] == '+91', orElse: () => dialCodes.first);
  String _originalPhone = '';
  String? _phoneError;
  String _userEmail = '';
  int _savedContactsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _stateCtrl.dispose();
    _countryCtrl.dispose();
    _pincodeCtrl.dispose();
    super.dispose();
  }

  void _clearControllers() {
    _nameCtrl.clear();
    _addressCtrl.clear();
    _stateCtrl.clear();
    _countryCtrl.clear();
    _pincodeCtrl.clear();
    _phoneCtrl.clear();
    _originalPhone = '';
    _savedContactsCount = 0;
  }

  Future<String> _getEffectiveEmail() async {
    final currentSession = await SessionStore().read();
    if (currentSession.email != null && currentSession.email!.trim().isNotEmpty) {
      return currentSession.email!.trim();
    }
    if (widget.session.email != null && widget.session.email!.trim().isNotEmpty) {
      return widget.session.email!.trim();
    }
    return '';
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final email = await _getEffectiveEmail();
      _userEmail = email;
      debugPrint('[APP PROFILE] Logged-in email: $email');

      if (email.isEmpty) {
        _clearControllers();
        _isEditing = true;
        return;
      }

      // 1. Fetch fresh DB row for owner_email directly from my_contacts database table
      final res = await widget.api.post('get_my_contacts', {'email': email, 'owner_email': email});
      debugPrint('[APP PROFILE] Load response: $res');

      if (res is List) {
        _savedContactsCount = res.where((e) {
          if (e is! Map) return false;
          final cat = e['category']?.toString().toLowerCase() ?? '';
          if (cat == 'app_profile') return false;
          final title = e['title']?.toString() ?? '';
          if (title.contains('"pincode"') || title.contains('"address"') || title.contains('"owner_email"')) return false;
          final appProf = e['app_profile']?.toString() ?? '';
          if (appProf.isNotEmpty && appProf != 'null') return false;
          return true;
        }).length;
      } else {
        _savedContactsCount = 0;
      }

      final profileData = _extractProfileFromResponse(res);
      debugPrint('[APP PROFILE] Loaded app_profile: $profileData');

      if (profileData != null && profileData.isNotEmpty) {
        _nameCtrl.text = profileData['name']?.toString() ?? profileData['full_name']?.toString() ?? '';
        _addressCtrl.text = profileData['address']?.toString() ?? profileData['location']?.toString() ?? '';
        _stateCtrl.text = profileData['state']?.toString() ?? '';
        _countryCtrl.text = profileData['country']?.toString() ?? '';
        _pincodeCtrl.text = profileData['pincode']?.toString() ?? profileData['zip']?.toString() ?? '';

        final phone = profileData['phone']?.toString() ?? profileData['phone_no']?.toString() ?? '';
        _parsePhone(phone);
        _isEditing = widget.isMandatoryOnboarding || (_nameCtrl.text.isEmpty && _phoneCtrl.text.isEmpty);
      } else {
        _clearControllers();
        _isEditing = true;
      }
    } catch (e) {
      debugPrint('[APP PROFILE] Error loading profile from DB: $e');
      _clearControllers();
      _isEditing = true;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic>? _extractProfileFromResponse(dynamic res) {
    if (res == null) return null;

    dynamic items = res;
    if (res is Map) {
      if (res['app_profile'] != null) {
        final parsed = _parseProfileObject(res['app_profile']);
        if (parsed != null && parsed.isNotEmpty) return parsed;
      }
      if (res['data'] != null) {
        items = res['data'];
      } else if (res['result'] != null) {
        items = res['result'];
      } else if (res['contacts'] != null) {
        items = res['contacts'];
      } else if (res['rows'] != null) {
        items = res['rows'];
      }
    }

    if (items is Map) {
      final parsed = _parseProfileObject(items['app_profile']) ?? _parseProfileObject(items['profile']) ?? _parseProfileObject(items['title']);
      if (parsed != null && parsed.isNotEmpty) return parsed;
      if (items['category']?.toString().toLowerCase() == 'app_profile' || items['name'] != null) {
        return Map<String, dynamic>.from(items);
      }
      return null;
    }

    if (items is List && items.isNotEmpty) {
      // 1. Look for explicit app_profile or profile JSON row
      for (final item in items) {
        if (item is Map) {
          final isAppProfileCat = item['category']?.toString().toLowerCase() == 'app_profile';
          final titleStr = item['title']?.toString() ?? '';
          
          if (item['app_profile'] != null && item['app_profile'].toString().trim().isNotEmpty) {
            final parsed = _parseProfileObject(item['app_profile']);
            if (parsed != null && parsed.isNotEmpty) return parsed;
          }
          if (titleStr.trim().startsWith('{') && (titleStr.contains('"address"') || titleStr.contains('"owner_email"'))) {
            final parsed = _parseProfileObject(titleStr);
            if (parsed != null && parsed.isNotEmpty) return parsed;
          }
          if (isAppProfileCat) {
            return Map<String, dynamic>.from(item);
          }
        }
      }
      // 2. Fallback check any item in list that has valid JSON in title or app_profile
      for (final item in items) {
        if (item is Map) {
          final parsed = _parseProfileObject(item['app_profile']) ?? _parseProfileObject(item['profile']) ?? _parseProfileObject(item['title']);
          if (parsed != null && parsed.isNotEmpty) return parsed;
        }
      }
    }
    return null;
  }

  Map<String, dynamic>? _parseProfileObject(dynamic val) {
    if (val == null) return null;
    if (val is Map) return Map<String, dynamic>.from(val);
    if (val is String && val.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(val);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  void _parsePhone(String phone) {
    _originalPhone = phone.trim();
    String digits = phone.replaceAll(RegExp(r'[^0-9]'), '');

    for (final country in dialCodes) {
      final code = country['dial_code']!;
      final codeDigits = code.replaceAll('+', '');
      if (phone.startsWith(code)) {
        _selectedCountry = country;
        _phoneCtrl.text = phone.substring(code.length).trim().replaceAll(RegExp(r'[^0-9]'), '');
        return;
      } else if (phone.startsWith('+$codeDigits')) {
        _selectedCountry = country;
        _phoneCtrl.text = phone.substring(codeDigits.length + 1).trim().replaceAll(RegExp(r'[^0-9]'), '');
        return;
      }
    }

    _selectedCountry = dialCodes.firstWhere((e) => e['dial_code'] == '+91', orElse: () => dialCodes.first);
    _phoneCtrl.text = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
  }

  int _getCountryPhoneLength(Map<String, String> country) {
    final code = country['code'] ?? '';
    switch (code) {
      case 'IN': case 'US': case 'CA': case 'GB': case 'PK': case 'BD': case 'PH': case 'MX': case 'JP': case 'KR': case 'ES': case 'IT': case 'DE': case 'RU':
        return 10;
      case 'AU': case 'AE': case 'SA': case 'FR': case 'NZ': case 'TH': case 'KW': case 'QA': case 'OM': case 'LK': case 'NP': case 'EG': case 'ZA':
        return 9;
      case 'SG': case 'HK': case 'IL': case 'DK': case 'NO': case 'SE': case 'FI': case 'BH':
        return 8;
      case 'CN':
        return 11;
      default:
        return 10;
    }
  }

  void _showCountryPickerDialog() {
    final searchCtrl = TextEditingController();
    List<Map<String, String>> filtered = List.from(dialCodes);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setPickerState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 10,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Select Country Code', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 16)),
              content: SizedBox(
                width: double.maxFinite,
                height: 380,
                child: Column(
                  children: [
                    TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search country or code...',
                        prefixIcon: const Icon(Icons.search),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onChanged: (q) {
                        final query = q.toLowerCase().trim();
                        setPickerState(() {
                          filtered = dialCodes.where((c) {
                            final nameMatch = (c['name'] ?? '').toLowerCase().contains(query);
                            final codeMatch = (c['dial_code'] ?? '').contains(query);
                            return nameMatch || codeMatch;
                          }).toList();
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('No country found'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (c, i) {
                                final item = filtered[i];
                                return ListTile(
                                  dense: true,
                                  leading: Text(item['flag'] ?? '', style: const TextStyle(fontSize: 22)),
                                  title: Text(item['name'] ?? '', style: const TextStyle(fontFamily: 'Poppins', fontSize: 14)),
                                  trailing: Text(item['dial_code'] ?? '', style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 14)),
                                  onTap: () {
                                    setState(() {
                                      _selectedCountry = item;
                                      _phoneError = null;
                                    });
                                    Navigator.pop(ctx);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _checkMobileUniqueness(String fullPhone, String currentEmail) async {
    final cleanTarget = fullPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanTarget.isEmpty) return true;
    final nationalTarget = cleanTarget.length >= 10 ? cleanTarget.substring(cleanTarget.length - 10) : cleanTarget;
    final normalizedCurrentEmail = currentEmail.trim().toLowerCase();

    try {
      final res = await widget.api.get('check-contact', {
        'type': 'check_phone',
        'phone': fullPhone,
      });

      if (res is List && res.isNotEmpty) {
        for (final item in res) {
          if (item is Map) {
            String itemEmail = (item['email'] ?? item['owner_email'] ?? '').toString().trim().toLowerCase();
            if (itemEmail.isEmpty) {
              final appProf = item['app_profile']?.toString() ?? item['title']?.toString() ?? '';
              if (appProf.isNotEmpty) {
                try {
                  final decoded = jsonDecode(appProf);
                  if (decoded is Map) {
                    itemEmail = (decoded['email'] ?? decoded['owner_email'] ?? '').toString().trim().toLowerCase();
                  }
                } catch (_) {}
              }
            }

            final itemPhone = (item['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
            final itemNational = itemPhone.length >= 10 ? itemPhone.substring(itemPhone.length - 10) : itemPhone;

            if (itemNational == nationalTarget && itemEmail.isNotEmpty && itemEmail != normalizedCurrentEmail) {
              return false;
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Uniqueness check error: $e");
    }

    return true;
  }

  Future<void> _saveProfile() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() {
      _isSaving = true;
      _phoneError = null;
    });

    try {
      final email = await _getEffectiveEmail();
      debugPrint('[APP PROFILE] Logged-in email: $email');

      if (email.isEmpty) {
        throw Exception("Invalid logged-in email. Please log in again.");
      }

      final name = _nameCtrl.text.trim();
      final phoneDigits = _phoneCtrl.text.trim();
      final fullPhone = '${_selectedCountry['dial_code']} $phoneDigits';

      final isUnique = await _checkMobileUniqueness(fullPhone, email);
      if (!isUnique) {
        setState(() {
          _phoneError = 'This mobile number is already registered by another user';
          _isSaving = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This mobile number is already registered by another user'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final profileMap = {
        'email': email,
        'owner_email': email,
        'name': name,
        'full_name': name,
        'phone': fullPhone,
      };

      final profileJsonStr = jsonEncode(profileMap);

      // Build profile payload containing email, name, and mobile number
      final Map<String, String?> profilePayload = {
        'email': email,
        'owner_email': email,
        'name': name,
        'full_name': name,
        'phone': fullPhone,
        'category': 'app_profile',
        'type': 'profile',
        'target_field': 'app_profile',
        'action': 'save_my_profile',
        'app_profile': profileJsonStr,
        'title': profileJsonStr,
        'profile': profileJsonStr,
      };

      debugPrint('[APP PROFILE] Save payload: $profilePayload');

      // Lookup existing app_profile row ID in my_contacts table for owner_email
      final existingRes = await widget.api.post('get_my_contacts', {'email': email, 'owner_email': email});
      String? existingId;
      if (existingRes is List && existingRes.isNotEmpty) {
        for (final item in existingRes) {
          if (item is Map && item['id'] != null) {
            final isAppProfile = item['category']?.toString().toLowerCase() == 'app_profile' ||
                (item['app_profile'] != null && item['app_profile'].toString().trim().isNotEmpty) ||
                (item['title']?.toString().contains('"address"') == true);
            if (isAppProfile) {
              existingId = item['id']?.toString();
              break;
            }
          }
        }
      }

      debugPrint("Database row ID: $existingId");

      dynamic saveRes;
      if (existingId != null && existingId.isNotEmpty) {
        final updatePayload = Map<String, String?>.from(profilePayload);
        updatePayload['id'] = existingId;
        saveRes = await widget.api.post('update_my_contact', updatePayload);
      } else {
        saveRes = await widget.api.post('save_my_contact', profilePayload);
      }

      debugPrint('[APP PROFILE] Save response: $saveRes');

      // Verify response status
      if (saveRes != null) {
        final str = saveRes.toString().toLowerCase();
        if (str.contains('error') || str.contains('fail')) {
          throw Exception("API returned error: $saveRes");
        }
      }

      /*
      // NOTIFICATION PROCESS (Commented out for later work)
      final cleanOrig = _originalPhone.replaceAll(RegExp(r'[^0-9]'), '');
      final cleanNew = fullPhone.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanOrig.isNotEmpty && cleanOrig != cleanNew) {
        final changeMessage = '$name changed their mobile number from $_originalPhone to $fullPhone.';
        await SessionStore().addNotification(
          title: 'Phone Number Changed',
          message: changeMessage,
        );
      }
      */

      _originalPhone = fullPhone;

      // Re-fetch profile from database to ensure fresh state
      await _loadProfile();

      if (mounted) {
        if (widget.isMandatoryOnboarding) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Application Profile created successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AppShell()),
          );
        } else {
          setState(() {
            _isSaving = false;
            _isEditing = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Application Profile saved successfully.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error saving profile to DB: $e");
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving profile: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'My Account',
              showMenu: true,
              api: widget.api,
              session: widget.session,
              store: SessionStore(),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFD7B41A)))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: _isEditing ? _buildEditForm() : _buildProfileView(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'U';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (trimmed.length >= 2) {
      return trimmed.substring(0, 2).toUpperCase();
    } else {
      return trimmed.toUpperCase();
    }
  }

  Widget _buildProfileView() {
    final name = _nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'My Name';
    final phone = _originalPhone.isNotEmpty ? _originalPhone : '${_selectedCountry['dial_code']} ${_phoneCtrl.text}';
    final address = _addressCtrl.text;
    final state = _stateCtrl.text;
    final countryName = _countryCtrl.text;
    final pincode = _pincodeCtrl.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 10),
        // Profile Card Container
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: const Color(0xFFE9ECEF)),
          ),
          child: Column(
            children: [
              // Initials Badge Left Corner, Spacing, Name Followed
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF4C5B8F),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _getInitials(name),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF212529), fontFamily: 'Poppins'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFFE9ECEF)),

              // Info Items
              const SizedBox(height: 10),
              if (_userEmail.isNotEmpty) _buildViewInfoRow(Icons.email_outlined, 'Email Address', _userEmail),
              _buildViewInfoRow(Icons.contacts_outlined, 'Total Saved Contacts', '$_savedContactsCount Contacts'),
              if (phone.trim().isNotEmpty && phone.trim() != '+91') _buildViewInfoRow(Icons.phone_outlined, 'Mobile Number', phone),
            ],
          ),
        ),

        const SizedBox(height: 30),

        // Edit Profile Button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4C5B8F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
            onPressed: () => setState(() => _isEditing = true),
            icon: const Icon(Icons.edit, size: 20),
            label: const Text(
              'Edit Profile',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Poppins'),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Delete Account Button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade300, width: 1.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _showDeleteAccountConfirmationDialog,
            icon: const Icon(Icons.delete_forever, size: 20, color: Colors.red),
            label: const Text(
              'Delete Account',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Poppins', color: Colors.red),
            ),
          ),
        ),
      ],
    );
  }

  void _showDeleteAccountConfirmationDialog() {
    final confirmationCtrl = TextEditingController();
    bool isMatch = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Delete Account',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Warning: All Data Will Be Lost!',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.red,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Deleting your account will permanently delete your account profile, all saved contacts, business profile, and all account data. This action is irreversible and data cannot be retrieved.',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12.5,
                              color: Color(0xFF495057),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'To confirm, please type "delete my account" below:',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFF212529),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: confirmationCtrl,
                      autofocus: true,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'delete my account',
                        hintStyle: TextStyle(fontFamily: 'Poppins', color: Colors.grey.shade400, fontSize: 13),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.red, width: 1.5),
                        ),
                      ),
                      onChanged: (val) {
                        final trimmed = val.trim().toLowerCase();
                        setDialogState(() {
                          isMatch = (trimmed == 'delete my account');
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins', color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.red.shade200,
                    disabledForegroundColor: Colors.white70,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: isMatch
                      ? () {
                          Navigator.pop(ctx);
                          _performAccountDeletion();
                        }
                      : null,
                  child: const Text(
                    'Delete Permanently',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _performAccountDeletion() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: const Padding(
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.red),
              ),
              SizedBox(width: 18),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Deleting Account...',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Please wait while your account is permanently deleted.',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final stopwatch = Stopwatch()..start();
    try {
      await widget.api.post('delete_account', {
        'email': _userEmail,
        'owner_email': _userEmail,
        'phone': _originalPhone,
      });

      final elapsed = stopwatch.elapsedMilliseconds;
      if (elapsed < 2000) {
        await Future.delayed(Duration(milliseconds: 2000 - elapsed));
      }

      await SessionStore().clear();

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your account and all associated data have been permanently deleted.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      final elapsed = stopwatch.elapsedMilliseconds;
      if (elapsed < 2000) {
        await Future.delayed(Duration(milliseconds: 2000 - elapsed));
      }

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting account: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildViewInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF4C5B8F)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6C757D), fontFamily: 'Poppins', fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF212529), fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditForm() {
    final targetLength = _getCountryPhoneLength(_selectedCountry);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                (_originalPhone.isNotEmpty && !widget.isMandatoryOnboarding) ? 'Edit Profile' : 'Create Profile',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Color(0xFF212529), fontFamily: 'Poppins'),
              ),
              if (_originalPhone.isNotEmpty && !widget.isMandatoryOnboarding)
                TextButton(
                  onPressed: () => setState(() => _isEditing = false),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontFamily: 'Poppins')),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // 0. Email Field (Automatically fetched logged-in email)
          if (_userEmail.isNotEmpty) ...[
            TextFormField(
              initialValue: _userEmail,
              readOnly: true,
              style: const TextStyle(color: Color(0xFF212529), fontSize: 15, fontFamily: 'Poppins'),
              decoration: InputDecoration(
                labelText: 'Email Address',
                labelStyle: const TextStyle(color: Color(0xFF343A40), fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 16.5),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF6C757D), size: 20),
                filled: true,
                fillColor: const Color(0xFFE9ECEF),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // 1. Full Name Field
          TextFormField(
            controller: _nameCtrl,
            style: const TextStyle(color: Color(0xFF212529), fontSize: 15, fontFamily: 'Poppins'),
            decoration: InputDecoration(
              labelText: 'Full Name',
              labelStyle: const TextStyle(color: Color(0xFF343A40), fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 16.5),
              floatingLabelBehavior: FloatingLabelBehavior.always,
              hintText: 'Enter your full name',
              hintStyle: const TextStyle(color: Color(0xFF6C757D), fontFamily: 'Poppins'),
              prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF6C757D), size: 20),
              filled: true,
              fillColor: const Color(0xFFF1F3F4),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Full name is required' : null,
          ),
          const SizedBox(height: 14),

          // 2. Phone Number Field (Country Code selector + Length based on Country Code)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: _showCountryPickerDialog,
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F3F4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Text(_selectedCountry['flag'] ?? '🇮🇳', style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 4),
                      Text(_selectedCountry['dial_code'] ?? '+91', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF6C757D)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  maxLength: targetLength,
                  style: const TextStyle(color: Color(0xFF212529), fontSize: 15, fontFamily: 'Poppins'),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(targetLength),
                  ],
                  onChanged: (v) {
                    if (_phoneError != null) {
                      setState(() => _phoneError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Mobile Number',
                    labelStyle: const TextStyle(color: Color(0xFF343A40), fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 16.5),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    hintText: '$targetLength digit number',
                    hintStyle: const TextStyle(color: Color(0xFF6C757D), fontFamily: 'Poppins'),
                    counterText: '',
                    errorText: _phoneError,
                    prefixIcon: const Icon(Icons.phone_outlined, color: Color(0xFF6C757D), size: 20),
                    filled: true,
                    fillColor: const Color(0xFFF1F3F4),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter mobile number';
                    if (v.trim().length != targetLength) return 'Enter $targetLength digits for ${_selectedCountry['name']}';
                    if (_phoneError != null) return _phoneError;
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),

          // Save / Update Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4C5B8F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              onPressed: _isSaving ? null : _saveProfile,
              child: _isSaving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                  : Text(
                      _originalPhone.isNotEmpty ? 'Save Changes' : 'Create Profile',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Poppins'),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
