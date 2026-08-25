import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_client.dart';
import '../services/dial_codes.dart';
import '../widgets/app_header.dart';
import '../services/session_store.dart';
import 'add_profile_screen.dart';

class PhoneEntryScreen extends StatefulWidget {
  final String email;
  const PhoneEntryScreen({super.key, required this.email});

  @override
  State<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends State<PhoneEntryScreen> {
  Map<String, String> _selectedCountry = dialCodes.firstWhere((e) => e['dial_code'] == '+91', orElse: () => dialCodes.first);
  final _phoneController = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(() => setState(() {}));
  }

  void _onNext() async {
    final number = _phoneController.text.trim();
    if (number.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid 10-digit number')));
      return;
    }

    final fullPhone = "${_selectedCountry['dial_code']}$number";
    setState(() => _loading = true);

    try {
      final targetEmail = widget.email.trim().toLowerCase();
      final clean10 = number.length >= 10 ? number.substring(number.length - 10) : number;

      final resList = <dynamic>[];
      try {
        final r1 = await ApiClient().get('check-contact', {
          'type': 'search',
          'query': clean10,
        });
        if (r1 is List) resList.addAll(r1);
      } catch (e) {
        debugPrint("Phone entry check-contact error: $e");
      }

      try {
        final r2 = await ApiClient().get('check_search_type', {'phone': fullPhone});
        if (r2 is List) resList.addAll(r2);
      } catch (e) {
        debugPrint("Phone entry check_search_type error: $e");
      }

      String? registeredOtherEmail;
      for (final item in resList) {
        if (item is Map && item['error'] == null) {
          final itemPhoneRaw = (item['phone'] ?? item['phone_no'] ?? '').toString();
          final itemPhoneClean = itemPhoneRaw.replaceAll(RegExp(r'[^0-9]'), '');
          final itemEmail = (item['email'] ?? item['owner_email'] ?? '').toString().trim().toLowerCase();

          if (itemPhoneClean.isNotEmpty && itemEmail.isNotEmpty) {
            final item10 = itemPhoneClean.length >= 10 ? itemPhoneClean.substring(itemPhoneClean.length - 10) : itemPhoneClean;
            if (item10 == clean10 && itemEmail != targetEmail) {
              registeredOtherEmail = itemEmail;
              break;
            }
          }
        }
      }

      if (registeredOtherEmail != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This mobile number is already registered to another account.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => AddProfileScreen(email: widget.email, phone: fullPhone)),
        );
      }
    } catch (e) {
      if (mounted) {
        String msg = 'Error: $e';
        if (e.toString().contains('SocketException') || e.toString().contains('Network is unreachable')) {
          msg = 'No internet connection. Please check your Wi-Fi or cellular data on your device/emulator.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showDialCodePicker() {
    showDialog(
      context: context,
      builder: (context) => _DialCodePickerDialog(
        onSelected: (code) => setState(() => _selectedCountry = code),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Fone Book',
              onBack: () => Navigator.pop(context),
              showMenu: false,
              api: ApiClient(),
              session: null,
              store: SessionStore(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(
                  children: [
                    const SizedBox(height: 50),
                    const Text(
                      'Business Contact',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF232323), fontFamily: 'Poppins'),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      'Enter the phone number you want to list in the directory.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey, fontFamily: 'Poppins'),
                    ),
                    const SizedBox(height: 40),
                    
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Country Code Selector
                        InkWell(
                          onTap: _showDialCodePicker,
                          child: Container(
                            width: 100,
                            height: 55,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6E6E6),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("${_selectedCountry['flag']} ${_selectedCountry['dial_code']}", 
                                       style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
                                const Icon(Icons.arrow_drop_down, size: 20),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),
                        // Phone Number Input
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              TextField(
                                controller: _phoneController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                maxLength: 10,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'Poppins'),
                                decoration: InputDecoration(
                                  hintText: 'Phone Number',
                                  counterText: '',
                                  filled: true,
                                  fillColor: const Color(0xFFE6E6E6),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 4, right: 4),
                                child: Text("${_phoneController.text.length}/10", 
                                       style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 50),
                    
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _onNext,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD7B41A),
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _loading 
                          ? const CircularProgressIndicator(color: Colors.black)
                          : const Text('Next', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontSize: 16, fontFamily: 'Poppins')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialCodePickerDialog extends StatefulWidget {
  final Function(Map<String, String>) onSelected;
  const _DialCodePickerDialog({required this.onSelected});

  @override
  State<_DialCodePickerDialog> createState() => _DialCodePickerDialogState();
}

class _DialCodePickerDialogState extends State<_DialCodePickerDialog> {
  final _search = TextEditingController();
  List<Map<String, String>> _filtered = [];

  @override
  void initState() {
    super.initState();
    // Sort alphabetically by name
    final List<Map<String, String>> sorted = List.from(dialCodes);
    sorted.sort((a, b) => a['name']!.compareTo(b['name']!));
    _filtered = sorted;

    _search.addListener(() {
      setState(() {
        _filtered = sorted.where((e) {
          final query = _search.text.toLowerCase();
          return e['name']!.toLowerCase().contains(query) || e['dial_code']!.contains(query);
        }).toList();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select Country', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
            const SizedBox(height: 20),
            TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search country or code...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _filtered[index];
                    return ListTile(
                      leading: Text(item['flag']!, style: const TextStyle(fontSize: 24)),
                      title: Text(item['name']!, style: const TextStyle(fontFamily: 'Poppins')),
                      trailing: Text(item['dial_code']!, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
                      onTap: () {
                        widget.onSelected(item);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
