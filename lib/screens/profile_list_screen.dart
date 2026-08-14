import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../models/contact.dart';
import '../models/user_session.dart';
import '../widgets/app_header.dart';
import 'add_profile_screen.dart';
import 'keyword_screen.dart';
import 'verification_screen.dart';
import 'promote_screen.dart';
import 'reports_screen.dart';
import 'visibility_screen.dart';
import 'phone_entry_screen.dart';

class ProfileListScreen extends StatefulWidget {
  final ApiClient api;
  final UserSession session;
  final String mode; // 'profile', 'keywords', 'verification', 'promote', 'traffic', 'settings'
  final String? trafficType; // 'organic', 'paid'

  const ProfileListScreen({
    super.key,
    required this.api,
    required this.session,
    required this.mode,
    this.trafficType,
  });

  @override
  State<ProfileListScreen> createState() => _ProfileListScreenState();
}

class _ProfileListScreenState extends State<ProfileListScreen> {
  List<DirectoryContact> _profiles = [];
  bool _loading = true;
  late UserSession _currentSession;

  @override
  void initState() {
    super.initState();
    _currentSession = widget.session;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.api.get('check_search_type1', {'email': _currentSession.email});
      if (res is List) {
        // Filter out "ghost" profiles that don't have a valid name or phone
        final profiles = res
            .map((e) => DirectoryContact.fromJson(e))
            .where((p) => p.name.isNotEmpty && p.phone.isNotEmpty)
            .toList();
        
        final isPremium = profiles.any((p) => p.verified == 1);
        
        if (isPremium != _currentSession.premium) {
          _currentSession = UserSession(
            phone: _currentSession.phone,
            email: _currentSession.email,
            place: _currentSession.place,
            place1: _currentSession.place1,
            country: _currentSession.country,
            image: _currentSession.image,
            premium: isPremium,
          );
          await SessionStore().save(_currentSession);
        }

        setState(() {
          _profiles = profiles;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  String get _title {
    switch (widget.mode) {
      case 'profile': return 'Profiles';
      case 'keywords': return 'Keywords';
      case 'verification': return 'Verification';
      case 'promote': return 'Promote';
      case 'traffic': 
        return widget.trafficType == 'organic' ? 'Organic Traffic Reports' : 'Paid Traffic Reports';
      case 'settings': return 'Settings';
      default: return 'Fone Book';
    }
  }

  void _addContact() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PhoneEntryScreen(email: widget.session.email!)),
    ).then((_) => _load());
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
              session: widget.session,
              store: SessionStore(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF212529), fontFamily: 'Poppins'),
                  ),
                  if (widget.mode == 'profile')
                    InkWell(
                      onTap: _addContact,
                      borderRadius: BorderRadius.circular(12),
                      child: const Text(
                        '+ Add Profile', 
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF6C757D), fontFamily: 'Poppins'),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C757D)))
                  : _profiles.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.business_center_outlined, size: 54, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                'No Business profile added yet',
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF212529)),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Add your first Business profile to manage ${_title.toLowerCase()}',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: 210,
                                height: 48,
                                child: ElevatedButton.icon(
                                  onPressed: _addContact,
                                  icon: const Icon(Icons.add, color: Colors.white),
                                  label: const Text('Add Business Profile', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Poppins', color: Colors.white)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF6C757D),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 4, bottom: 20),
                          itemCount: _profiles.length,
                          itemBuilder: (c, i) {
                            final p = _profiles[i];
                            return _buildItem(p);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(DirectoryContact p) {
    return InkWell(
      onTap: () => _onItemClick(p),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE9ECEF), width: 1),
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
            // Profile Image / Initial Avatar
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF4C5B8F),
              ),
              child: ClipOval(
                child: p.imageUrl.isNotEmpty
                    ? FadeInImage.assetNetwork(
                        placeholder: 'assets/images/user.png',
                        image: p.imageUrl,
                        fit: BoxFit.cover,
                        imageErrorBuilder: (context, error, stackTrace) => Image.asset('assets/images/user.png', fit: BoxFit.cover),
                      )
                    : Image.asset('assets/images/user.png', fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),

            // Profile Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF212529), fontFamily: 'Poppins'),
                  ),
                  if (p.service.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      p.service,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF6C757D), fontFamily: 'Poppins'),
                    ),
                  ],
                  if (p.location1 != null && p.location1!.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF212529)),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            p.location1!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF212529), fontFamily: 'Poppins'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Action Text (No Container Card)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.mode == 'traffic' ? Icons.visibility : Icons.edit,
                  size: 14,
                  color: const Color(0xFF6C757D),
                ),
                const SizedBox(width: 4),
                Text(
                  widget.mode == 'traffic' ? 'View' : 'Edit',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6C757D), fontWeight: FontWeight.bold, fontFamily: 'Poppins'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onItemClick(DirectoryContact p) {
    Widget target;
    switch (widget.mode) {
      case 'profile':
        target = AddProfileScreen(email: widget.session.email!, phone: p.phone);
        break;
      case 'keywords':
        target = KeywordScreen(
          api: widget.api,
          phone: p.phone,
          name: p.name,
          service: p.service,
          category: p.category ?? 'Individual',
          initial: "${p.keyword ?? ''}, ${p.tags ?? ''}",
          verified: p.verified,
        );
        break;
      case 'verification':
        target = VerificationScreen(contact: p);
        break;
      case 'promote':
        target = PromoteScreen(session: widget.session, contact: p);
        break;
      case 'traffic':
        target = ReportsScreen(
          api: widget.api, 
          phone: p.phone, 
          tags: p.keyword ?? '',
          type: widget.trafficType ?? 'paid',
        );
        break;
      case 'settings':
        target = VisibilityScreen(api: widget.api, phone: p.phone, initial: p.showContact, contact: p);
        break;
      default:
        return;
    }

    Navigator.push(context, MaterialPageRoute(builder: (_) => target)).then((_) => _load());
  }
}


