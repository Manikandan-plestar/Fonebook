import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../models/user_session.dart';
import '../widgets/app_header.dart';
import '../services/dial_codes.dart';

class MyContactItem {
  final int? id;
  final String ownerEmail;
  final String name;
  final String title;
  final String phone;

  MyContactItem({
    this.id,
    required this.ownerEmail,
    required this.name,
    required this.title,
    required this.phone,
  });

  factory MyContactItem.fromJson(Map<String, dynamic> json) {
    return MyContactItem(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? ''),
      ownerEmail: json['owner_email']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
    );
  }
}

class MyContactsScreen extends StatefulWidget {
  final ApiClient api;
  final UserSession session;

  const MyContactsScreen({
    super.key,
    required this.api,
    required this.session,
  });

  @override
  State<MyContactsScreen> createState() => _MyContactsScreenState();
}

class _MyContactsScreenState extends State<MyContactsScreen> {
  List<MyContactItem> _contacts = [];
  bool _loading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  Future<String> _getEffectiveEmail() async {
    final currentSession = await SessionStore().read();
    if (currentSession.email != null && currentSession.email!.trim().isNotEmpty) {
      return currentSession.email!.trim();
    }
    if (currentSession.phone != null && currentSession.phone!.trim().isNotEmpty) {
      return currentSession.phone!.trim();
    }
    if (widget.session.email != null && widget.session.email!.trim().isNotEmpty) {
      return widget.session.email!.trim();
    }
    if (widget.session.phone != null && widget.session.phone!.trim().isNotEmpty) {
      return widget.session.phone!.trim();
    }
    return 'guest@fonebook.com';
  }

  @override
  void initState() {
    super.initState();
    SessionStore().addListener(_onStoreChanged);
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.trim().toLowerCase();
        });
      }
    });
    _load();
  }

  void _onStoreChanged() {
    if (mounted) {
      _load();
    }
  }

  @override
  void dispose() {
    SessionStore().removeListener(_onStoreChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MyContactsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.email != widget.session.email || oldWidget.session.phone != widget.session.phone) {
      _load();
    }
  }

  List<MyContactItem> get _filteredContacts {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _contacts;
    final digitsQuery = query.replaceAll(RegExp(r'[^0-9]'), '');

    return _contacts.where((c) {
      final nameMatch = c.name.toLowerCase().contains(query);
      final titleMatch = c.title.toLowerCase().contains(query);
      final phoneMatch = c.phone.toLowerCase().contains(query);
      final phoneDigitsMatch = digitsQuery.isNotEmpty &&
          c.phone.replaceAll(RegExp(r'[^0-9]'), '').contains(digitsQuery);
      return nameMatch || titleMatch || phoneMatch || phoneDigitsMatch;
    }).toList();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final email = await _getEffectiveEmail();
      final res = await widget.api.post('get_my_contacts', {'email': email, 'owner_email': email});
      if (!mounted) return;
      if (res is List) {
        final parsed = res.map((e) => MyContactItem.fromJson(Map<String, dynamic>.from(e))).toList();
        
        // Sorting A-Z
        parsed.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        final seen = <String>{};
        final unique = <MyContactItem>[];
        
        final sortedCodes = List<String>.from(dialCodes.map((e) => e['dial_code']!))
          ..sort((a, b) => b.length.compareTo(a.length));

        for (final item in parsed) {
          final digits = item.phone.replaceAll(RegExp(r'[^0-9]'), '');
          final national = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
          String dialCode = '+91';
          if (item.phone.contains('+')) {
            for (final dc in sortedCodes) {
              if (item.phone.startsWith(dc) || item.phone.contains(dc)) {
                dialCode = dc;
                break;
              }
            }
          }
          final key = '$dialCode-$national';
          if (national.isNotEmpty && !seen.contains(key)) {
            seen.add(key);
            unique.add(item);
          } else if (national.isEmpty) {
            unique.add(item);
          }
        }
        setState(() {
          _contacts = unique;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint("Error loading my_contacts: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showCountryPickerDialog(BuildContext context, ValueChanged<Map<String, String>> onSelect) {
    final searchCtrl = TextEditingController();
    List<Map<String, String>> filtered = List.from(dialCodes);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setPickerState) {
            return AlertDialog(
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
                                    onSelect(item);
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

  int _getCountryPhoneLength(Map<String, String> country) {
    final code = country['code'] ?? '';
    final dial = country['dial_code'] ?? '';

    switch (code) {
      case 'IN': 
      case 'US': 
      case 'CA': 
      case 'GB': 
      case 'PK': 
      case 'BD': 
      case 'PH': 
      case 'MX': 
      case 'JP': 
      case 'KR': 
      case 'MY': 
      case 'ES': 
      case 'IT': 
      case 'DE': 
      case 'RU': 
        return 10;
      case 'AU': 
      case 'AE': 
      case 'SA': 
      case 'FR': 
      case 'NZ': 
      case 'TH': 
      case 'KW': 
      case 'QA': 
      case 'OM': 
      case 'LK': 
      case 'NP': 
      case 'EG': 
      case 'ZA': 
      case 'NG': 
      case 'KE': 
      case 'GH': 
        return 9;
      case 'SG': 
      case 'HK': 
      case 'IL': 
      case 'DK': 
      case 'NO': 
      case 'SE': 
      case 'FI': 
      case 'BH': 
        return 8;
      case 'CN': 
        return 11;
      default:
        if (dial == '+91' || dial == '+1' || dial == '+44') return 10;
        return 10;
    }
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    Map<String, String> selectedCountry = dialCodes.firstWhere((e) => e['dial_code'] == '+91', orElse: () => dialCodes.first);
    String? phoneError;

    showDialog(
      context: context,
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final targetLength = _getCountryPhoneLength(selectedCountry);
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Add Contact', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _importDeviceContacts();
                    },
                    icon: const Icon(Icons.download, size: 18, color: Color(0xFF149508)),
                    label: const Text('Import', style: TextStyle(color: Color(
                        0xFF149508), fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Name',
                          hintText: 'Enter contact name',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: titleCtrl,
                        decoration: InputDecoration(
                          labelText: 'Title / Designation',
                          hintText: 'e.g. Doctor, Manager, Engineer',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () {
                              _showCountryPickerDialog(context, (selected) {
                                setDialogState(() {
                                  selectedCountry = selected;
                                  phoneError = null;
                                  final newLen = _getCountryPhoneLength(selected);
                                  if (phoneCtrl.text.length > newLen) {
                                    phoneCtrl.text = phoneCtrl.text.substring(0, newLen);
                                  }
                                });
                              });
                            },
                            child: Container(
                              height: 58,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade400),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Text(selectedCountry['flag'] ?? '🇮🇳', style: const TextStyle(fontSize: 18)),
                                  const SizedBox(width: 4),
                                  Text(selectedCountry['dial_code'] ?? '+91', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                  const Icon(Icons.arrow_drop_down, size: 18),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: phoneCtrl,
                              keyboardType: TextInputType.phone,
                              maxLength: targetLength,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(targetLength),
                              ],
                              onChanged: (v) {
                                setDialogState(() {
                                  final digits = v.trim();
                                  if (digits.length == targetLength) {
                                    final exists = _contacts.any((c) {
                                      final cDigits = c.phone.replaceAll(RegExp(r'[^0-9]'), '');
                                      final cNational = cDigits.length >= 10 ? cDigits.substring(cDigits.length - 10) : cDigits;
                                      return cNational == digits && c.phone.contains(selectedCountry['dial_code']!);
                                    });
                                    if (exists) {
                                      phoneError = 'Number is already in contacts';
                                    } else {
                                      phoneError = null;
                                    }
                                  } else {
                                    phoneError = null;
                                  }
                                });
                              },
                              decoration: InputDecoration(
                                labelText: 'Phone Number',
                                hintText: '$targetLength digit number',
                                counterText: '',
                                errorText: phoneError,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Enter phone number';
                                if (v.trim().length != targetLength) return 'Enter $targetLength digits for ${selectedCountry['name']}';
                                if (phoneError != null) return phoneError;
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD7B41A),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: saving
                      ? null
                      : () async {
                          if (formKey.currentState?.validate() == true && phoneError == null) {
                            setDialogState(() => saving = true);
                            try {
                              final email = await _getEffectiveEmail();
                              final fullPhone = '${selectedCountry['dial_code']} ${phoneCtrl.text.trim()}';
                              final nav = Navigator.of(ctx);
                              final messenger = ScaffoldMessenger.of(context);
                              await widget.api.post('save_my_contact', {
                                'email': email,
                                'owner_email': email,
                                'name': nameCtrl.text.trim(),
                                'title': titleCtrl.text.trim(),
                                'phone': fullPhone,
                              });
                              if (mounted) {
                                nav.pop();
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('Contact added successfully'), backgroundColor: Colors.green),
                                );
                                _load();
                              }
                            } catch (e) {
                              setDialogState(() {
                                saving = false;
                                String errorMsg = e.toString().replaceAll(RegExp(r'^Exception:\s*'), '');
                                if (errorMsg.contains('already in contacts') || errorMsg.contains('already registered') || errorMsg.contains('already exist')) {
                                  phoneError = 'Number is already in contacts';
                                } else {
                                  phoneError = errorMsg;
                                }
                              });
                              formKey.currentState?.validate();
                            }
                          }
                        },
                  child: saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Text('Add', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditDialog(MyContactItem item) {
    Map<String, String> selectedCountry = dialCodes.firstWhere((e) => e['dial_code'] == '+91', orElse: () => dialCodes.first);
    String rawPhone = item.phone.trim();
    String numberPart = rawPhone;

    bool foundCountry = false;
    for (final country in dialCodes) {
      final code = country['dial_code']!;
      final codeDigits = code.replaceAll('+', '');
      if (rawPhone.startsWith(code)) {
        selectedCountry = country;
        numberPart = rawPhone.substring(code.length).trim();
        foundCountry = true;
        break;
      } else if (rawPhone.startsWith('+$codeDigits')) {
        selectedCountry = country;
        numberPart = rawPhone.substring(codeDigits.length + 1).trim();
        foundCountry = true;
        break;
      }
    }

    if (!foundCountry) {
      selectedCountry = dialCodes.firstWhere((e) => e['dial_code'] == '+91', orElse: () => dialCodes.first);
      numberPart = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    } else {
      numberPart = numberPart.replaceAll(RegExp(r'[^0-9]'), '');
    }

    final nameCtrl = TextEditingController(text: item.name);
    final titleCtrl = TextEditingController(text: item.title);
    final phoneCtrl = TextEditingController(text: numberPart);
    final formKey = GlobalKey<FormState>();
    String? phoneError;

    showDialog(
      context: context,
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final targetLength = _getCountryPhoneLength(selectedCountry);
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Edit Contact', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deleteContact(item);
                    },
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    label: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Name',
                          hintText: 'Enter contact name',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: titleCtrl,
                        decoration: InputDecoration(
                          labelText: 'Title / Designation',
                          hintText: 'e.g. Doctor, Manager, Engineer',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () {
                              _showCountryPickerDialog(context, (selected) {
                                setDialogState(() {
                                  selectedCountry = selected;
                                  phoneError = null;
                                  final newLen = _getCountryPhoneLength(selected);
                                  if (phoneCtrl.text.length > newLen) {
                                    phoneCtrl.text = phoneCtrl.text.substring(0, newLen);
                                  }
                                });
                              });
                            },
                            child: Container(
                              height: 58,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade400),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Text(selectedCountry['flag'] ?? '🇮🇳', style: const TextStyle(fontSize: 18)),
                                  const SizedBox(width: 4),
                                  Text(selectedCountry['dial_code'] ?? '+91', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                  const Icon(Icons.arrow_drop_down, size: 18),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: phoneCtrl,
                              keyboardType: TextInputType.phone,
                              maxLength: targetLength,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(targetLength),
                              ],
                              onChanged: (v) {
                                setDialogState(() {
                                  final digits = v.trim();
                                  if (digits.length == targetLength) {
                                    final exists = _contacts.any((c) {
                                      if (c.id == item.id) return false;
                                      final cDigits = c.phone.replaceAll(RegExp(r'[^0-9]'), '');
                                      final cNational = cDigits.length >= 10 ? cDigits.substring(cDigits.length - 10) : cDigits;
                                      return cNational == digits && c.phone.contains(selectedCountry['dial_code']!);
                                    });
                                    if (exists) {
                                      phoneError = 'Number is already in contacts';
                                    } else {
                                      phoneError = null;
                                    }
                                  } else {
                                    phoneError = null;
                                  }
                                });
                              },
                              decoration: InputDecoration(
                                labelText: 'Phone Number',
                                hintText: '$targetLength digit number',
                                counterText: '',
                                errorText: phoneError,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Enter phone number';
                                if (v.trim().length != targetLength) return 'Enter $targetLength digits for ${selectedCountry['name']}';
                                if (phoneError != null) return phoneError;
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD7B41A),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: saving
                      ? null
                      : () async {
                          if (formKey.currentState?.validate() == true && phoneError == null) {
                            setDialogState(() => saving = true);
                            try {
                              final email = await _getEffectiveEmail();
                              final fullPhone = '${selectedCountry['dial_code']} ${phoneCtrl.text.trim()}';
                              final nav = Navigator.of(ctx);
                              final messenger = ScaffoldMessenger.of(context);
                              await widget.api.post('update_my_contact', {
                                'id': item.id?.toString() ?? '',
                                'email': email,
                                'owner_email': email,
                                'name': nameCtrl.text.trim(),
                                'title': titleCtrl.text.trim(),
                                'phone': fullPhone,
                              });
                              if (mounted) {
                                nav.pop();
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('Contact updated successfully'), backgroundColor: Colors.green),
                                );
                                _load();
                              }
                            } catch (e) {
                              setDialogState(() {
                                saving = false;
                                String errorMsg = e.toString().replaceAll(RegExp(r'^Exception:\s*'), '');
                                if (errorMsg.contains('already in contacts') || errorMsg.contains('already registered') || errorMsg.contains('already exist')) {
                                  phoneError = 'Number is already in contacts';
                                } else {
                                  phoneError = errorMsg;
                                }
                              });
                              formKey.currentState?.validate();
                            }
                          }
                        },
                  child: saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Text('Update', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _importDeviceContacts() async {
    try {
      final granted = await FlutterContacts.permissions.request(PermissionType.read) == PermissionStatus.granted;
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permission to access device contacts was denied.')),
          );
        }
        return;
      }

      setState(() => _loading = true);
      List<Contact> deviceContacts = await FlutterContacts.getAll(properties: ContactProperty.values.toSet());
      setState(() => _loading = false);

      if (deviceContacts.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No contacts found on device.')),
          );
        }
        return;
      }

      if (!mounted) return;

      _showDeviceContactsPicker(deviceContacts);
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reading device contacts: $e')),
        );
      }
    }
  }

  void _showDeviceContactsPicker(List<Contact> deviceContacts) {
    final sortedCodes = List<String>.from(dialCodes.map((e) => e['dial_code']!))
      ..sort((a, b) => b.length.compareTo(a.length));

    final List<MapEntry<int, Contact>> indexedContacts = List.generate(
      deviceContacts.length,
      (i) => MapEntry(i, deviceContacts[i]),
    );
    List<MapEntry<int, Contact>> filtered = List.from(indexedContacts);

    final selectedIndices = <int>{};
    for (int i = 0; i < deviceContacts.length; i++) {
      selectedIndices.add(i);
    }

    final searchCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void filter(String query) {
              final q = query.toLowerCase().trim();
              setModalState(() {
                if (q.isEmpty) {
                  filtered = List.from(indexedContacts);
                } else {
                  filtered = indexedContacts.where((entry) {
                    final c = entry.value;
                    final nameMatch = (c.displayName ?? '').toLowerCase().contains(q);
                    final phoneMatch = c.phones.any((p) => p.number.contains(q));
                    return nameMatch || phoneMatch;
                  }).toList();
                }
              });
            }

            return SafeArea(
              child: Container(
                height: MediaQuery.of(context).size.height * 0.85,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Import Device Contacts',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Poppins'),
                        ),
                        Text(
                          '${selectedIndices.length} selected',
                          style: const TextStyle(color: Colors.grey, fontSize: 13, fontFamily: 'Poppins'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: searchCtrl,
                      onChanged: filter,
                      decoration: InputDecoration(
                        hintText: 'Search contacts...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.grey.shade200,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              selectedIndices.clear();
                              for (int i = 0; i < deviceContacts.length; i++) {
                                selectedIndices.add(i);
                              }
                            });
                          },
                          child: const Text('Select All'),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              selectedIndices.clear();
                            });
                          },
                          child: const Text('Deselect All'),
                        ),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('No contacts match your search'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (c, i) {
                                final entry = filtered[i];
                                final originalIndex = entry.key;
                                final item = entry.value;
                                final isSelected = selectedIndices.contains(originalIndex);
                                final phone = item.phones.isNotEmpty ? item.phones.first.number : 'No Phone';
                                final job = item.organizations.isNotEmpty ? (item.organizations.first.jobTitle ?? item.organizations.first.name ?? '') : '';

                                return CheckboxListTile(
                                  value: isSelected,
                                  title: Text(item.displayName ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text(job.isNotEmpty ? '${_formatPhoneDisplay(phone)} • $job' : _formatPhoneDisplay(phone)),
                                  onChanged: (val) {
                                    setModalState(() {
                                      if (val == true) {
                                        selectedIndices.add(originalIndex);
                                      } else {
                                        selectedIndices.remove(originalIndex);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD7B41A),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: selectedIndices.isEmpty
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _startBatchImport(deviceContacts, selectedIndices, sortedCodes);
                              },
                        child: Text(
                          'Import ${selectedIndices.length} Contacts',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Poppins'),
                        ),
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

  Future<void> _startBatchImport(
    List<Contact> deviceContacts,
    Set<int> selectedIndices,
    List<String> sortedCodes,
  ) async {
    final existingPhones = _contacts.map((c) => c.phone).toList();
    final selectedItems = selectedIndices.map((idx) {
      final item = deviceContacts[idx];
      return {
        'rawPhone': item.phones.isNotEmpty ? item.phones.first.number : '',
        'title': item.organizations.isNotEmpty ? (item.organizations.first.jobTitle ?? item.organizations.first.name ?? '') : '',
        'name': item.displayName ?? '',
      };
    }).toList();

    final result = await Isolate.run(() {
      final existingNationalDigits = existingPhones.map((phone) {
        final d = phone.replaceAll(RegExp(r'[^0-9]'), '');
        return d.length >= 10 ? d.substring(d.length - 10) : d;
      }).where((d) => d.isNotEmpty).toSet();

      final seenInImport = <String>{};
      final toImport = <Map<String, String>>[];
      int alreadyExistsCount = 0;

      for (final raw in selectedItems) {
        final rawPhone = raw['rawPhone'] ?? '';
        final title = raw['title'] ?? '';
        final name = raw['name'] ?? '';

        String cleanP = rawPhone.replaceAll(RegExp(r'[\(\)\-\s\.]'), '').trim();
        if (cleanP.isEmpty) continue;

        if (!cleanP.startsWith('+')) {
          if (cleanP.length > 10 && cleanP.startsWith('0')) {
            cleanP = cleanP.substring(1);
          }
          cleanP = '+91 $cleanP';
        } else {
          String code = '+91';
          String rest = cleanP.substring(1);
          for (final dc in sortedCodes) {
            if (cleanP.startsWith(dc)) {
              code = dc;
              rest = cleanP.substring(dc.length);
              break;
            }
          }
          cleanP = '$code $rest';
        }

        final digits = cleanP.replaceAll(RegExp(r'[^0-9]'), '');
        final national = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;

        if (national.isNotEmpty) {
          if (existingNationalDigits.contains(national) || seenInImport.contains(national)) {
            alreadyExistsCount++;
            continue;
          }
          seenInImport.add(national);
        }

        toImport.add({
          'name': name,
          'title': title,
          'phone': cleanP,
        });
      }

      return {
        'toImport': toImport,
        'alreadyExistsCount': alreadyExistsCount,
      };
    });

    final toImport = result['toImport'] as List<Map<String, String>>;
    final alreadyExistsCount = result['alreadyExistsCount'] as int;

    if (toImport.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('All selected contacts ($alreadyExistsCount) are already in your contacts list.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final int totalToImport = toImport.length;
    final processedNotifier = ValueNotifier<int>(0);
    final insertedNotifier = ValueNotifier<int>(0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (progressCtx) {
        return AnimatedBuilder(
          animation: Listenable.merge([processedNotifier, insertedNotifier]),
          builder: (context, _) {
            final currentProcessed = processedNotifier.value;
            final totalInserted = insertedNotifier.value;
            final progress = totalToImport > 0 ? (currentProcessed / totalToImport) : 0.0;
            final percent = (progress * 100).toInt();

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFFD7B41A)),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Importing Contacts...',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey.shade200,
                      color: const Color(0xFFD7B41A),
                      minHeight: 10,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$currentProcessed / $totalToImport contacts',
                        style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Text(
                        '$percent%',
                        style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, color: Color(0xFF149508), fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('New Contacts Added:', style: TextStyle(fontSize: 13, fontFamily: 'Poppins')),
                        Text('$totalInserted', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green, fontFamily: 'Poppins')),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    const int chunkSize = 40;
    final email = await _getEffectiveEmail();

    final nav = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);

    for (int i = 0; i < toImport.length; i += chunkSize) {
      final end = (i + chunkSize < toImport.length) ? i + chunkSize : toImport.length;
      final chunk = toImport.sublist(i, end);

      bool success = false;
      int attempts = 0;
      while (!success && attempts < 3) {
        attempts++;
        try {
          final importRes = await widget.api.post('import_my_contacts', {
            'email': email,
            'owner_email': email,
            'contacts': jsonEncode(chunk),
          });

          if (importRes is Map) {
            insertedNotifier.value += (importRes['inserted'] as int? ?? chunk.length);
          } else {
            insertedNotifier.value += chunk.length;
          }
          success = true;
        } catch (e) {
          debugPrint('Batch import chunk error (attempt $attempts): $e');
          if (attempts < 3) {
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }
      }

      processedNotifier.value = end;
      await Future.delayed(const Duration(milliseconds: 1));
    }

    if (mounted) {
      nav.pop();
      final totalInserted = insertedNotifier.value;

      String msg = '';
      if (totalInserted > 0) {
        msg = '$totalInserted contact(s) imported successfully';
      } else {
        msg = 'Import completed';
      }

      messenger.showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green),
      );
      _load();
    }
  }

  Future<void> _deleteContact(MyContactItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Contact'),
        content: Text('Are you sure you want to delete ${item.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final email = await _getEffectiveEmail();
        await widget.api.post('delete_my_contact', {
          'id': item.id?.toString() ?? '',
          'email': email,
          'owner_email': email,
        });
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(content: Text('Contact deleted successfully'), backgroundColor: Colors.green));
        _load();
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text('Error deleting contact: $e')));
      }
    }
  }

  void _callPhone(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleanPhone.isEmpty) return;
    final Uri url = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  String _formatPhoneDisplay(String phone) {
    if (phone.isEmpty) return '';
    String cleaned = phone.replaceAll(RegExp(r'[\(\)\-\s\.]'), '').trim();

    for (final country in dialCodes) {
      final code = country['dial_code']!;
      final codeDigits = code.replaceAll('+', '');
      if (cleaned.startsWith(code)) {
        final rest = cleaned.substring(code.length).replaceAll(RegExp(r'[^0-9]'), '');
        return '$code $rest';
      } else if (cleaned.startsWith('+$codeDigits')) {
        final rest = cleaned.substring(codeDigits.length + 1).replaceAll(RegExp(r'[^0-9]'), '');
        return '$code $rest';
      }
    }

    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isNotEmpty) {
      return '+91 $digits';
    }
    return cleaned;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Fone Book',
              showMenu: true,
              api: widget.api,
              session: widget.session,
              store: SessionStore(),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'My Contacts',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF212529), fontFamily: 'Poppins'),
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _showAddDialog,
                        borderRadius: BorderRadius.circular(20),
                        child: const Text(
                          '+ Add',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF6C757D), fontFamily: 'Poppins'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search by name, phone, title...',
                    hintStyle: TextStyle(fontSize: 14, fontFamily: 'Poppins', color: Colors.grey.shade500),
                    prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey.shade600),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, size: 18, color: Colors.grey.shade600),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFD7B41A)))
                  : _contacts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'No contacts added yet',
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Add or import contacts to manage your list',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Colors.grey),
                              ),
                              const SizedBox(height: 25),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _showAddDialog,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add Contact'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFD7B41A),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      : _filteredContacts.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
                                  const SizedBox(height: 10),
                                  Text(
                                    'No contacts match "$_searchQuery"',
                                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, color: Colors.grey),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: _filteredContacts.length,
                              itemBuilder: (c, i) {
                                final item = _filteredContacts[i];
                                return _buildItem(item);
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(MyContactItem item) {
    return InkWell(
      onTap: () => _showEditDialog(item),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF4C5B8F),
              ),
              child: ClipOval(
                child: Image.asset('assets/images/user.png', fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.name.isNotEmpty ? item.name : 'No Name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF212529), fontFamily: 'Poppins'),
                  ),
                  if (item.title.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF6C757D), fontFamily: 'Poppins'),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.phone, size: 12, color: Color(0xFF6C757D)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _formatPhoneDisplay(item.phone),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF495057), fontFamily: 'Poppins'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: () => _callPhone(item.phone),
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.phone, color: Colors.black, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
