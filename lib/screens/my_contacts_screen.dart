import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
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
  final String category;

  MyContactItem({
    this.id,
    required this.ownerEmail,
    required this.name,
    required this.title,
    required this.phone,
    this.category = '',
  });

  factory MyContactItem.fromJson(Map<String, dynamic> json, [String? savedCategory]) {
    String cat = json['category']?.toString() ?? '';
    if (cat.isEmpty || cat == 'null' || cat == 'Others') {
      cat = (savedCategory != null && savedCategory.isNotEmpty && savedCategory != 'Others') ? savedCategory : '';
    }
    return MyContactItem(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? ''),
      ownerEmail: json['owner_email']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      category: cat,
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
  List<String> _categories = ['All', 'Family', 'Friends', 'Office'];
  String _selectedCategory = 'All';

  bool _isSelectionMode = false;
  final Set<String> _selectedPhones = {};

  Future<void> _handleAssignCategorySelection() async {
    final availableCategories = List<String>.from(_categories.where((c) => c != 'All'));
    
    final selectedCat = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _selectedCategory == 'All' ? 'Assign Category' : 'Move Category',
          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 16),
        ),
        children: [
          ...availableCategories.map((c) => SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, c),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(c, style: const TextStyle(fontFamily: 'Poppins', fontSize: 14)),
            ),
          )),
          const Divider(),
          SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(ctx, '__ADD_CUSTOM__');
            },
            child: Row(
              children: const [
                Icon(Icons.add, color: Color(0xFF6C757D), size: 20),
                SizedBox(width: 8),
                Text('+ Add Custom Category...', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Color(0xFF6C757D), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );

    if (selectedCat == null) return;

    String finalCategory = selectedCat;
    if (selectedCat == '__ADD_CUSTOM__') {
      final custom = await _showAddCustomCategoryDialog(context);
      if (custom == null || custom.trim().isEmpty) return;
      finalCategory = custom.trim();
      await SessionStore().addCategory(finalCategory);
    }

    final store = SessionStore();
    final count = _selectedPhones.length;
    for (final phone in _selectedPhones) {
      await store.setContactCategory(phone, finalCategory);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Assigned $count contact(s) to $finalCategory'),
        backgroundColor: const Color(0xFF4C5B8F),
      ),
    );

    setState(() {
      _isSelectionMode = false;
      _selectedPhones.clear();
    });
    _load();
  }

  Future<void> _handleDeleteSelection() async {
    final count = _selectedPhones.length;
    final isAllTab = _selectedCategory == 'All';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isAllTab ? 'Delete Contacts' : 'Remove from $_selectedCategory'),
        content: Text(
          isAllTab
              ? 'Are you sure you want to delete $count selected contact(s) from your list?'
              : 'Are you sure you want to remove $count contact(s) from $_selectedCategory? (They will remain in your main contact list)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins', color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAllTab ? 'Delete' : 'Remove', style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (isAllTab) {
      final email = await _getEffectiveEmail();
      final itemsToDelete = _contacts.where((c) => _selectedPhones.contains(c.phone)).toList();
      for (final item in itemsToDelete) {
        try {
          await widget.api.post('delete_my_contact', {
            'id': item.id?.toString() ?? '',
            'email': email,
            'owner_email': email,
          });
        } catch (e) {
          debugPrint("Error deleting selected contact: $e");
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $count contact(s)'), backgroundColor: Colors.red),
      );
    } else {
      final store = SessionStore();
      for (final phone in _selectedPhones) {
        await store.setContactCategory(phone, '');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed $count contact(s) from $_selectedCategory')),
      );
    }

    setState(() {
      _isSelectionMode = false;
      _selectedPhones.clear();
    });
    _load();
  }

  Future<String?> _showAddCustomCategoryDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Custom Category', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'e.g. Gym, College, VIP',
            hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Colors.grey),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontFamily: 'Poppins')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C757D),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final val = ctrl.text.trim();
              if (val.isNotEmpty) {
                Navigator.pop(ctx, val);
              }
            },
            child: const Text('Add', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
          ),
        ],
      ),
    );
  }

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
    var list = _contacts;

    if (_selectedCategory != 'All') {
      list = list.where((c) => c.category.toLowerCase() == _selectedCategory.toLowerCase()).toList();
    }

    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return list;
    final digitsQuery = query.replaceAll(RegExp(r'[^0-9]'), '');

    return list.where((c) {
      final nameMatch = c.name.toLowerCase().contains(query);
      final titleMatch = c.title.toLowerCase().contains(query);
      final phoneMatch = c.phone.toLowerCase().contains(query);
      final categoryMatch = c.category.toLowerCase().contains(query);
      final phoneDigitsMatch = digitsQuery.isNotEmpty &&
          c.phone.replaceAll(RegExp(r'[^0-9]'), '').contains(digitsQuery);
      return nameMatch || titleMatch || phoneMatch || categoryMatch || phoneDigitsMatch;
    }).toList();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final email = await _getEffectiveEmail();
      final catList = await SessionStore().getCategories();
      final catMap = await SessionStore().getAllContactCategories();

      final res = await widget.api.post('get_my_contacts', {'email': email, 'owner_email': email});
      if (!mounted) return;
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
            .map((e) {
              final m = Map<String, dynamic>.from(e);
              final phone = m['phone']?.toString() ?? '';
              final cleanP = phone.replaceAll(RegExp(r'[^0-9]'), '');
              return MyContactItem.fromJson(m, catMap[cleanP]);
            })
            .where((item) => item.category.toLowerCase() != 'app_profile')
            .toList();
        
        // Auto-update saved contacts matching old_phone from number_change notifications
        for (final item in res) {
          if (item is Map && item['category']?.toString().toLowerCase() == 'notification') {
            try {
              final appProfRaw = item['app_profile']?.toString() ?? '';
              if (appProfRaw.isNotEmpty) {
                final payload = jsonDecode(appProfRaw);
                if (payload is Map && payload['type'] == 'number_change') {
                  final oldPhone = payload['old_phone']?.toString() ?? '';
                  final newPhone = payload['new_phone']?.toString() ?? '';
                  final userName = payload['name']?.toString() ?? 'Contact';

                  final oldClean = oldPhone.replaceAll(RegExp(r'[^0-9]'), '');
                  final newClean = newPhone.replaceAll(RegExp(r'[^0-9]'), '');
                  final old10 = oldClean.length >= 10 ? oldClean.substring(oldClean.length - 10) : oldClean;

                  if (old10.isNotEmpty && newPhone.isNotEmpty && oldClean != newClean) {
                    for (final c in parsed) {
                      final cClean = c.phone.replaceAll(RegExp(r'[^0-9]'), '');
                      final c10 = cClean.length >= 10 ? cClean.substring(cClean.length - 10) : cClean;
                      if (c10 == old10 && c.phone != newPhone) {
                        debugPrint('[AUTO UPDATE CONTACT] Updating contact ${c.name} phone from ${c.phone} to $newPhone');
                        
                        // Update saved contact row in database
                        widget.api.post('update_my_contact', {
                          'id': c.id?.toString(),
                          'email': email,
                          'owner_email': email,
                          'name': c.name,
                          'phone': newPhone,
                          'phone_no': newPhone,
                          'title': c.title,
                          'category': c.category,
                        }).catchError((err) {
                          debugPrint('Error auto-updating contact DB: $err');
                        });

                        SessionStore().addNotification(
                          title: 'Contact Phone Updated',
                          message: '$userName changed their mobile number. Saved contact "${c.name}" was automatically updated to $newPhone.',
                        );
                      }
                    }
                  }
                }
              }
            } catch (err) {
              debugPrint('Auto-update parse error: $err');
            }
          }
        }

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
          _categories = ['All', ...catList];
          _loading = false;
        });
      } else {
        setState(() {
          _categories = ['All', ...catList];
          _loading = false;
        });
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
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shadowColor: Colors.black.withValues(alpha: 0.2),
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
    List<String> availableCategories = List.from(_categories.where((c) => c != 'All'));
    String selectedCategory = (_selectedCategory != 'All' && availableCategories.contains(_selectedCategory))
        ? _selectedCategory
        : (availableCategories.isNotEmpty ? availableCategories.first : 'Family');

    showDialog(
      context: context,
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final targetLength = _getCountryPhoneLength(selectedCountry);
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shadowColor: Colors.black.withValues(alpha: 0.2),
              elevation: 10,
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
                      const SizedBox(height: 12),
                      // Category Field
                      DropdownButtonFormField<String>(
                        value: availableCategories.contains(selectedCategory) ? selectedCategory : (availableCategories.isNotEmpty ? availableCategories.first : 'Family'),
                        decoration: InputDecoration(
                          labelText: 'Category',
                          hintText: 'Select category',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        items: [
                          ...availableCategories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontFamily: 'Poppins', fontSize: 14)))),
                          const DropdownMenuItem(
                            value: '__ADD_NEW__',
                            child: Row(
                              children: [
                                Icon(Icons.add, size: 18, color: Color(0xFF6C757D)),
                                SizedBox(width: 6),
                                Text('Add Custom Category...', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF6C757D))),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (val) async {
                          if (val == '__ADD_NEW__') {
                            final newCat = await _showAddCustomCategoryDialog(context);
                            if (newCat != null && newCat.isNotEmpty) {
                              await SessionStore().addCategory(newCat);
                              final updatedList = await SessionStore().getCategories();
                              setDialogState(() {
                                availableCategories = List.from(updatedList);
                                selectedCategory = newCat;
                              });
                              setState(() {
                                _categories = ['All', ...updatedList];
                              });
                            }
                          } else if (val != null) {
                            setDialogState(() {
                              selectedCategory = val;
                            });
                          }
                        },
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
                              await SessionStore().setContactCategory(fullPhone, selectedCategory);
                              await SessionStore().addCategory(selectedCategory);
                              await widget.api.post('save_my_contact', {
                                'email': email,
                                'owner_email': email,
                                'name': nameCtrl.text.trim(),
                                'title': titleCtrl.text.trim(),
                                'phone': fullPhone,
                                'category': selectedCategory,
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
    List<String> availableCategories = List.from(_categories.where((c) => c != 'All'));
    String selectedCategory = (item.category.isNotEmpty && item.category != 'Others') ? item.category : (availableCategories.isNotEmpty ? availableCategories.first : 'Family');

    showDialog(
      context: context,
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final targetLength = _getCountryPhoneLength(selectedCountry);
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shadowColor: Colors.black.withValues(alpha: 0.2),
              elevation: 10,
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
                      const SizedBox(height: 12),
                      // Category Field
                      DropdownButtonFormField<String>(
                        value: availableCategories.contains(selectedCategory) ? selectedCategory : (availableCategories.isNotEmpty ? availableCategories.first : 'Family'),
                        decoration: InputDecoration(
                          labelText: 'Category',
                          hintText: 'Select category',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        items: [
                          ...availableCategories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontFamily: 'Poppins', fontSize: 14)))),
                          const DropdownMenuItem(
                            value: '__ADD_NEW__',
                            child: Row(
                              children: [
                                Icon(Icons.add, size: 18, color: Color(0xFF6C757D)),
                                SizedBox(width: 6),
                                Text('Add Custom Category...', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF6C757D))),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (val) async {
                          if (val == '__ADD_NEW__') {
                            final newCat = await _showAddCustomCategoryDialog(context);
                            if (newCat != null && newCat.isNotEmpty) {
                              await SessionStore().addCategory(newCat);
                              final updatedList = await SessionStore().getCategories();
                              setDialogState(() {
                                availableCategories = List.from(updatedList);
                                selectedCategory = newCat;
                              });
                              setState(() {
                                _categories = ['All', ...updatedList];
                              });
                            }
                          } else if (val != null) {
                            setDialogState(() {
                              selectedCategory = val;
                            });
                          }
                        },
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
                              await SessionStore().setContactCategory(fullPhone, selectedCategory);
                              await SessionStore().addCategory(selectedCategory);
                              await widget.api.post('update_my_contact', {
                                'id': item.id?.toString() ?? '',
                                'email': email,
                                'owner_email': email,
                                'name': nameCtrl.text.trim(),
                                'title': titleCtrl.text.trim(),
                                'phone': fullPhone,
                                'category': selectedCategory,
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
      final fastProperties = ContactProperty.values.where((p) => p.name != 'photo' && p.name != 'thumbnail').toSet();
      List<Contact> deviceContacts = await FlutterContacts.getAll(
        properties: fastProperties,
      );
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
    final email = await _getEffectiveEmail();
    debugPrint('[IMPORT] Logged-in email: $email');
    debugPrint('[IMPORT] Device contacts selected: ${selectedIndices.length}');

    final existingPhones = _contacts.map((c) => c.phone).toList();

    // Prepare raw selected item payload list
    final rawSelectedItems = <Map<String, dynamic>>[];
    for (final idx in selectedIndices) {
      if (idx < 0 || idx >= deviceContacts.length) continue;
      final item = deviceContacts[idx];
      final name = item.displayName ?? '';
      final title = item.organizations.isNotEmpty
          ? (item.organizations.first.jobTitle ?? item.organizations.first.name ?? '')
          : '';
      
      final phoneNumbers = item.phones.map((p) => p.number).where((n) => n.trim().isNotEmpty).toList();
      rawSelectedItems.add({
        'name': name,
        'title': title,
        'phones': phoneNumbers,
      });
    }

    // Process canonical normalization, MySQL-safe sanitization & Level-1 de-duplication in background isolate
    final processingResult = await Isolate.run(() {
      String sanitizeForDb(String input) {
        if (input.isEmpty) return '';
        final buffer = StringBuffer();
        for (final rune in input.runes) {
          if (rune <= 0xFFFF) {
            if ((rune >= 0x2600 && rune <= 0x27BF) ||
                (rune >= 0x2300 && rune <= 0x23FF) ||
                (rune >= 0x2B50 && rune <= 0x2B55) ||
                (rune >= 0xFE00 && rune <= 0xFE0F)) {
              continue;
            }
            buffer.writeCharCode(rune);
          }
        }
        final res = buffer.toString().trim();
        return res.isEmpty ? 'Contact' : res;
      }

      final existingNationalDigits = existingPhones.map((phone) {
        final d = phone.replaceAll(RegExp(r'[^0-9]'), '');
        return d.length >= 10 ? d.substring(d.length - 10) : d;
      }).where((d) => d.isNotEmpty).toSet();

      final seenInImport = <String>{};
      final toImportList = <Map<String, String>>[];
      int localDuplicatesCount = 0;

      for (final raw in rawSelectedItems) {
        final rawName = raw['name']?.toString() ?? '';
        final rawTitle = raw['title']?.toString() ?? '';
        final name = sanitizeForDb(rawName);
        final title = rawTitle.isNotEmpty ? sanitizeForDb(rawTitle) : '';
        final List<String> phones = List<String>.from(raw['phones'] ?? []);

        for (final rawPhone in phones) {
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
              localDuplicatesCount++;
              continue;
            }
            seenInImport.add(national);
          }

          toImportList.add({
            'name': name,
            'title': title,
            'phone': cleanP,
            'category': 'my_contact',
            'type': 'profile',
          });
        }
      }

      return {
        'toImport': toImportList,
        'localDuplicatesCount': localDuplicatesCount,
      };
    });

    final toImport = processingResult['toImport'] as List<Map<String, String>>;
    final initialDuplicates = processingResult['localDuplicatesCount'] as int;

    debugPrint('[IMPORT] Local duplicates removed: $initialDuplicates');
    debugPrint('[IMPORT] Contacts to import: ${toImport.length}');

    if (toImport.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('All selected contacts ($initialDuplicates) already exist in your list.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final int totalToImport = toImport.length;
    final processedNotifier = ValueNotifier<int>(0);
    final insertedNotifier = ValueNotifier<int>(0);
    final duplicatesNotifier = ValueNotifier<int>(initialDuplicates);
    final failedNotifier = ValueNotifier<int>(0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (progressCtx) {
        return AnimatedBuilder(
          animation: Listenable.merge([processedNotifier, insertedNotifier, duplicatesNotifier, failedNotifier]),
          builder: (context, _) {
            final currentProcessed = processedNotifier.value;
            final totalInserted = insertedNotifier.value;
            final totalDupes = duplicatesNotifier.value;
            final totalFailed = failedNotifier.value;
            final progress = totalToImport > 0 ? (currentProcessed / totalToImport) : 0.0;
            final percent = (progress * 100).toInt().clamp(0, 100);

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
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Successfully Added:', style: TextStyle(fontSize: 13, fontFamily: 'Poppins')),
                            Text('$totalInserted', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green, fontFamily: 'Poppins')),
                          ],
                        ),
                        if (totalDupes > 0) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Already Existing:', style: TextStyle(fontSize: 13, fontFamily: 'Poppins')),
                              Text('$totalDupes', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange, fontFamily: 'Poppins')),
                            ],
                          ),
                        ],
                        if (totalFailed > 0) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Failed:', style: TextStyle(fontSize: 13, fontFamily: 'Poppins')),
                              Text('$totalFailed', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red, fontFamily: 'Poppins')),
                            ],
                          ),
                        ],
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

    const int chunkSize = 250;
    final nav = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final random = Random();
    bool anyBatchSucceeded = false;

    for (int i = 0; i < toImport.length; i += chunkSize) {
      final end = (i + chunkSize < toImport.length) ? i + chunkSize : toImport.length;
      final chunk = toImport.sublist(i, end);
      final batchNum = (i / chunkSize).toInt() + 1;
      final totalBatches = (toImport.length / chunkSize).ceil();

      debugPrint('[IMPORT] Batch $batchNum/$totalBatches (Size: ${chunk.length})');

      bool batchSuccess = false;
      int attempts = 0;

      while (!batchSuccess && attempts < 4) {
        attempts++;
        debugPrint('[IMPORT] Batch $batchNum attempt $attempts');

        try {
          final importRes = await widget.api.post(
            'import_my_contacts',
            {
              'email': email,
              'owner_email': email,
              'contacts': jsonEncode(chunk),
            },
            timeout: const Duration(seconds: 45),
          );

          debugPrint('[IMPORT] Batch $batchNum response: $importRes');

          if (importRes is Map) {
            if (importRes['status'] == 'error' || importRes['error'] != null) {
              throw Exception(importRes['error'] ?? importRes['message'] ?? 'Server error during batch import');
            }

            final int inserted = int.tryParse(importRes['inserted']?.toString() ?? '') ?? 0;
            final int skipped = int.tryParse(importRes['skipped']?.toString() ?? '') ??
                int.tryParse(importRes['duplicates']?.toString() ?? '') ??
                0;
            final int failed = int.tryParse(importRes['failed']?.toString() ?? '') ?? 0;

            final int finalInserted = (importRes['inserted'] == null && importRes['skipped'] == null)
                ? chunk.length
                : inserted;

            insertedNotifier.value += finalInserted;
            duplicatesNotifier.value += skipped;
            failedNotifier.value += failed;
            processedNotifier.value += (finalInserted + skipped + failed);
          } else if (importRes is List) {
            insertedNotifier.value += importRes.length;
            processedNotifier.value += importRes.length;
          } else {
            insertedNotifier.value += chunk.length;
            processedNotifier.value += chunk.length;
          }

          batchSuccess = true;
          anyBatchSucceeded = true;
        } catch (e) {
          debugPrint('[IMPORT] Batch $batchNum attempt $attempts failed: $e');
          final isPermanentError = e.toString().contains('400') ||
              e.toString().contains('401') ||
              e.toString().contains('403') ||
              e.toString().contains('Invalid request');

          if (isPermanentError || attempts >= 4) {
            failedNotifier.value += chunk.length;
            processedNotifier.value += chunk.length;
            break;
          }

          // Exponential backoff with random jitter (500ms, 1s, 2s, 4s)
          final baseMs = (500 * pow(2, attempts - 1)).toInt();
          final jitterMs = random.nextInt(250);
          final delayMs = baseMs + jitterMs;
          debugPrint('[IMPORT] Retrying batch $batchNum in ${delayMs}ms...');
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      }

      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (mounted) {
      nav.pop();
      final totalProcessed = processedNotifier.value;
      final totalInserted = insertedNotifier.value;
      final totalDuplicates = duplicatesNotifier.value;
      final totalFailed = failedNotifier.value;

      debugPrint('[IMPORT] Final result: Processed=$totalProcessed, Inserted=$totalInserted, Duplicates=$totalDuplicates, Failed=$totalFailed');

      if (totalFailed == 0 && anyBatchSucceeded) {
        if (totalInserted > 0) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('$totalProcessed contact(s) processed: $totalInserted new added, $totalDuplicates existing.'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(
              content: Text('$totalProcessed contact(s) processed: All contacts already exist in your list ($totalDuplicates existing).'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (totalInserted > 0 || totalDuplicates > 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Import finished: $totalInserted added, $totalDuplicates existing, $totalFailed failed.'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Import failed. Please check network connection and try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }

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
              title: 'Saved',
              showMenu: true,
              api: widget.api,
              session: widget.session,
              store: SessionStore(),
              actions: [
                Text(
                  '${_filteredContacts.length} contacts',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6C757D), fontFamily: 'Poppins', fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 6),
              ],
            ),
            if (_isSelectionMode)
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4C5B8F),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () {
                          setState(() {
                            _isSelectionMode = false;
                            _selectedPhones.clear();
                          });
                        },
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_selectedPhones.length} selected',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Poppins'),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          _selectedPhones.length == _filteredContacts.length ? Icons.select_all : Icons.deselect,
                          color: Colors.white,
                        ),
                        tooltip: 'Select All',
                        onPressed: () {
                          setState(() {
                            if (_selectedPhones.length == _filteredContacts.length) {
                              _selectedPhones.clear();
                              _isSelectionMode = false;
                            } else {
                              _selectedPhones.addAll(_filteredContacts.map((c) => c.phone));
                            }
                          });
                        },
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        onSelected: (v) {
                          if (v == 'category') {
                            _handleAssignCategorySelection();
                          } else if (v == 'delete') {
                            _handleDeleteSelection();
                          }
                        },
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'category',
                            child: Row(
                              children: [
                                const Icon(Icons.category_outlined, color: Color(0xFF495057), size: 20),
                                const SizedBox(width: 10),
                                Text(
                                  _selectedCategory == 'All' ? 'Assign Category' : 'Move Category',
                                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                const SizedBox(width: 10),
                                Text(
                                  _selectedCategory == 'All' ? 'Delete Contacts' : 'Remove from $_selectedCategory',
                                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Expanded(
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
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: _showAddDialog,
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4C5B8F),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4C5B8F).withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Text(
                        '+ Add',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Poppins'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Category Filter Tabs
            if (_categories.isNotEmpty)
              Container(
                height: 38,
                margin: const EdgeInsets.only(top: 4, bottom: 4),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _categories.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final isSelected = _selectedCategory.toLowerCase() == cat.toLowerCase();
                    return ChoiceChip(
                      showCheckmark: false,
                      label: Text(
                        cat,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? Colors.white : const Color(0xFF495057),
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: const Color(0xFF4C5B8F),
                      backgroundColor: Colors.white,
                      side: BorderSide(
                        color: isSelected ? const Color(0xFF4C5B8F) : const Color(0xFFE9ECEF),
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _selectedCategory = cat;
                          });
                        }
                      },
                    );
                  },
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
                                      backgroundColor: const Color(0xFF4C5B8F),
                                      foregroundColor: Colors.white,
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
                                return Dismissible(
                                  key: Key('my_contact_${item.id}_${item.phone}_$i'),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20),
                                    margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.delete_forever, color: Colors.white, size: 24),
                                        SizedBox(width: 6),
                                        Text(
                                          'Delete',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Poppins'),
                                        ),
                                      ],
                                    ),
                                  ),
                                  confirmDismiss: (direction) async {
                                    return await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        title: const Text('Delete Contact', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
                                        content: Text('Are you sure you want to delete ${item.name}?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins', color: Colors.grey)),
                                          ),
                                          ElevatedButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                            child: const Text('Delete', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ),
                                    ) ?? false;
                                  },
                                  onDismissed: (direction) async {
                                    final messenger = ScaffoldMessenger.of(context);
                                    try {
                                      final email = await _getEffectiveEmail();
                                      await widget.api.post('delete_my_contact', {
                                        'id': item.id?.toString() ?? '',
                                        'email': email,
                                        'owner_email': email,
                                      });
                                      if (mounted) {
                                        messenger.showSnackBar(
                                          const SnackBar(content: Text('Contact deleted successfully'), backgroundColor: Colors.green),
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        messenger.showSnackBar(
                                          SnackBar(content: Text('Error deleting contact: $e')),
                                        );
                                      }
                                    }
                                    _load();
                                  },
                                  child: _buildItem(item),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(MyContactItem item) {
    final isSelected = _selectedPhones.contains(item.phone);

    return InkWell(
      onTap: () {
        if (_isSelectionMode) {
          setState(() {
            if (isSelected) {
              _selectedPhones.remove(item.phone);
              if (_selectedPhones.isEmpty) _isSelectionMode = false;
            } else {
              _selectedPhones.add(item.phone);
            }
          });
        } else {
          _showEditDialog(item);
        }
      },
      onLongPress: () {
        setState(() {
          _isSelectionMode = true;
          if (isSelected) {
            _selectedPhones.remove(item.phone);
            if (_selectedPhones.isEmpty) _isSelectionMode = false;
          } else {
            _selectedPhones.add(item.phone);
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF0F4FF) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF4C5B8F) : const Color(0xFFE9ECEF),
            width: isSelected ? 1.5 : 1.0,
          ),
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
            if (_isSelectionMode)
              Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isSelected ? const Color(0xFF4C5B8F) : Colors.grey.shade400,
                  size: 24,
                ),
              )
            else
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
