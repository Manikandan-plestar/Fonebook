import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../models/user_session.dart';
import '../models/contact.dart';
import '../widgets/app_header.dart';

class VisibilityScreen extends StatefulWidget {
  final ApiClient api;
  final String phone;
  final String initial;
  final DirectoryContact contact;
  const VisibilityScreen({super.key, required this.api, required this.phone, required this.initial, required this.contact});
  @override
  State<VisibilityScreen> createState() => _VisibilityScreenState();
}

class _VisibilityScreenState extends State<VisibilityScreen> {
  late bool m, w, e, l, s, f, pub;
  String _whoContact = 'all';

  @override
  void initState() {
    super.initState();
    m = widget.initial.contains('m');
    w = widget.initial.contains('w');
    e = widget.initial.contains('e');
    l = widget.initial.contains('l');
    s = widget.initial.contains('s');
    f = widget.initial.contains('f');
    pub = widget.contact.publish == 'yes';

    final rawWho = (widget.contact.whoContact ?? 'international').toLowerCase();
    if (rawWho == 'country') {
      _whoContact = 'country';
    } else if (rawWho == 'location') {
      _whoContact = 'location';
    } else {
      _whoContact = 'international';
    }
  }

  void _saveShow() async {
    await widget.api.post('save_show', {
      'phone': widget.phone,
      'show': '${m ? 'm' : ''}${w ? 'w' : ''}${e ? 'e' : ''}${l ? 'l' : ''}${s ? 's' : ''}${f ? 'f' : ''}'
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully'), backgroundColor: Colors.green, duration: Duration(seconds: 1)));
    }
  }

  void _saveWho(String val) async {
    setState(() => _whoContact = val);
    await widget.api.post('save_access', {
      'phone': widget.phone,
      'who_contact': val,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully'), backgroundColor: Colors.green, duration: Duration(seconds: 1)));
    }
  }

  void _savePub(bool v) async {
    if (v && widget.contact.verified != 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only verified contacts can publish profile in directory.')),
      );
      setState(() => pub = false);
      return;
    }
    await widget.api.post('save_publish', {'phone': widget.phone, 'publish': v ? 'yes' : 'no'});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully'), backgroundColor: Colors.green, duration: Duration(seconds: 1)));
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
              title: 'Fone Book',
              onBack: () => Navigator.pop(context),
              showMenu: true,
              api: widget.api,
              session: UserSession(phone: widget.phone),
              store: SessionStore(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        'Profile Settings',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF212529), fontFamily: 'Poppins'),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Show Contacts Card
                    Container(
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
                            'Show Contacts',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF212529), fontFamily: 'Poppins'),
                          ),
                          const SizedBox(height: 12),
                          _buildNativeSwitchTile('Mobile no', m, (v) { setState(() => m = v); _saveShow(); }),
                          _buildNativeSwitchTile('Whatsapp', w, (v) { setState(() => w = v); _saveShow(); }),
                          // _buildNativeSwitchTile('Email', e, (v) { setState(() => e = v); _saveShow(); }),
                          // _buildNativeSwitchTile('Landline', l, (v) { setState(() => l = v); _saveShow(); }),
                          // _buildNativeSwitchTile('Skype', s, (v) { setState(() => s = v); _saveShow(); }),
                          // _buildNativeSwitchTile('Full Address', f, (v) { setState(() => f = v); _saveShow(); }),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Access Card
                    Container(
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
                            'Access',
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

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNativeSwitchTile(String title, bool value, ValueChanged<bool> onChanged) {
    bool canToggle = true;
    if (title == 'Whatsapp' && (widget.contact.whatsapp == null || widget.contact.whatsapp!.isEmpty)) canToggle = false;
    // if (title == 'Email' && (widget.contact.email == null || widget.contact.email!.isEmpty)) canToggle = false;
    // if (title == 'Landline' && (widget.contact.landline == null || widget.contact.landline!.isEmpty)) canToggle = false;
    // if (title == 'Skype' && (widget.contact.skype == null || widget.contact.skype!.isEmpty)) canToggle = false;

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
                fontFamily: 'Poppins'
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
