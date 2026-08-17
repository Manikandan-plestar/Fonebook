import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../models/user_session.dart';
import '../widgets/app_header.dart';
import 'login_screen.dart';
import 'profile_list_screen.dart';
import 'favourites_screen.dart';
import 'my_contacts_screen.dart';

class SettingsScreen extends StatelessWidget {
  final ApiClient api;
  final UserSession session;
  const SettingsScreen({super.key, required this.api, required this.session});

  @override
  Widget build(BuildContext context) {
    final items = [
      {'title': 'Profile', 'mode': 'profile', 'icon': Icons.person_outline},
      {'title': 'Keywords', 'mode': 'keywords', 'icon': Icons.tag},
      {'title': 'Verification', 'mode': 'verification', 'icon': Icons.verified_user_outlined},
      {'title': 'Promote', 'mode': 'promote', 'icon': Icons.campaign_outlined},
      {'title': 'Traffic reports', 'mode': 'traffic', 'icon': Icons.bar_chart_outlined},
      {'title': 'Profile Settings', 'mode': 'settings', 'icon': Icons.settings_outlined},
      {'title': 'Favourites', 'mode': 'favourites', 'icon': Icons.star_outline},
      {'title': 'My Contacts', 'mode': 'my_contacts', 'icon': Icons.contacts_outlined},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Fone Book',
              onBack: () => Navigator.pop(context),
              showMenu: false,
              api: api,
              session: session,
              store: SessionStore(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: Column(
                  children: [
                    const Text(
                      'Settings',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF212529), fontFamily: 'Poppins'),
                    ),
                    const SizedBox(height: 16),
                    
                    ...items.map((item) => _buildMenuItem(
                      context, 
                      item['title'] as String, 
                      item['mode'] as String, 
                      item['icon'] as IconData,
                    )),
                    
                    const SizedBox(height: 30),
                    
                    InkWell(
                      onTap: () => _confirmAndLogout(context),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5F5),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFFC9C9)),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.logout, color: Colors.red, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Log out',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red, fontFamily: 'Poppins'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, String title, String mode, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9ECEF), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        onTap: () {
          if (mode == 'traffic') {
            _showTrafficMenu(context);
          } else if (mode == 'favourites') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => FavouritesScreen(api: api, store: SessionStore(), session: session)));
          } else if (mode == 'my_contacts') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => MyContactsScreen(api: api, session: session)));
          } else {
            Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileListScreen(api: api, session: session, mode: mode)));
          }
        },
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF6C757D),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF212529), fontFamily: 'Poppins'),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 22),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  void _showTrafficMenu(BuildContext context) {
    showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(100, 400, 20, 0),
      items: [
        const PopupMenuItem(value: 'organic', child: Text('Organic Traffic')),
        const PopupMenuItem(value: 'paid', child: Text('Paid Traffic')),
      ],
    ).then((value) {
      if (value != null) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileListScreen(api: api, session: session, mode: 'traffic', trafficType: value)));
      }
    });
  }

  void _confirmAndLogout(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.logout, color: Colors.red, size: 22),
            SizedBox(width: 8),
            Text(
              'Logout', 
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF212529)),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to log out of Fone Book?',
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text(
              'Logout',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ).then((confirm) async {
      if (confirm == true && context.mounted) {
        await SessionStore().clear();
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()), 
            (r) => false,
          );
        }
      }
    });
  }
}
