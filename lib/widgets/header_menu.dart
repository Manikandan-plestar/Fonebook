import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../models/user_session.dart';
import '../screens/login_screen.dart';
import '../screens/profile_list_screen.dart';
import '../screens/favourites_screen.dart';
import '../screens/app_profile_screen.dart';
import 'notification_dialog.dart';

class HeaderMenu extends StatefulWidget {
  final ApiClient? api;
  final SessionStore? store;
  final UserSession? session;
  final VoidCallback? onUpdate;
  const HeaderMenu({super.key, this.api, this.store, this.session, this.onUpdate});

  @override
  State<HeaderMenu> createState() => _HeaderMenuState();
}

class _HeaderMenuState extends State<HeaderMenu> {
  bool _hasUnread = false;

  @override
  void initState() {
    super.initState();
    SessionStore().addListener(_checkNotifications);
    _checkNotifications();
  }

  @override
  void dispose() {
    SessionStore().removeListener(_checkNotifications);
    super.dispose();
  }

  Future<void> _checkNotifications() async {
    final unread = await SessionStore().hasUnreadNotifications();
    if (mounted) {
      setState(() {
        _hasUnread = unread;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<String>(
          icon: Image.asset('assets/images/three_dots.png', width: 25, height: 30),
          onSelected: (v) async {
            if (v == 'Logout') {
              _confirmAndLogout(context);
              return;
            }

            final effectiveApi = widget.api ?? ApiClient();
            final effectiveSession = (widget.session != null && widget.session!.email != null)
                ? widget.session!
                : await SessionStore().read();

            if (effectiveSession.email == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please login to access management features.')),
              );
              return;
            }

            if (v == 'My Account' || v == 'My Profile') {
              Navigator.of(context).popUntil((route) => route.isFirst);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AppProfileScreen(api: effectiveApi, session: effectiveSession),
                ),
              );
              return;
            }

            if (v == 'Favourites') {
              Navigator.of(context).popUntil((route) => route.isFirst);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FavouritesScreen(
                    api: effectiveApi,
                    store: widget.store ?? SessionStore(),
                    session: effectiveSession,
                  ),
                ),
              );
              return;
            }

            String mode = '';
            if (v == 'Profile' || v == 'Business') mode = 'profile';
            else if (v == 'Keywords') mode = 'keywords';
            else if (v == 'Verification') mode = 'verification';
            else if (v == 'Promote') mode = 'promote';
            else if (v == 'Settings') mode = 'settings';

            if (mode.isNotEmpty) {
              Navigator.of(context).popUntil((route) => route.isFirst);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileListScreen(api: effectiveApi, session: effectiveSession, mode: mode),
                ),
              );
            }
          },
          itemBuilder: (c) => [
            const PopupMenuItem(value: 'My Account', child: Text('My Account')),
            const PopupMenuItem(value: 'Business', child: Text('Busines')),
            const PopupMenuItem(value: 'Keywords', child: Text('Keywords')),
            const PopupMenuItem(value: 'Promote', child: Text('Promote')),
            const PopupMenuItem(value: 'Favourites', child: Text('Favourites')),
            const PopupMenuItem(value: 'Logout', child: Text('Logout')),
          ],
        ),
      ],
    );
  }

  void _showTrafficMenu(BuildContext context, ApiClient effectiveApi, UserSession effectiveSession) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      items: [
        const PopupMenuItem(value: 'organic', child: Text('Organic Traffic')),
        const PopupMenuItem(value: 'paid', child: Text('Paid Traffic')),
      ],
    ).then((value) {
      if (value != null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileListScreen(api: effectiveApi, session: effectiveSession, mode: 'traffic', trafficType: value)));
      }
    });
  }

  void _confirmAndLogout(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shadowColor: Colors.black.withValues(alpha: 0.2),
        elevation: 10,
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
