import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../models/user_session.dart';
import 'header_menu.dart';

import 'notification_dialog.dart';

class AppHeader extends StatefulWidget {
  final String title;
  final bool showSearch;
  final String searchHint;
  final ValueChanged<String>? onSearch;
  final VoidCallback? onBack;
  final ApiClient? api;
  final SessionStore? store;
  final UserSession? session;
  final VoidCallback? onUpdate;
  final bool showMenu;
  final List<Widget>? actions;

  const AppHeader({
    super.key,
    required this.title,
    this.showSearch = false,
    this.searchHint = 'Search',
    this.onSearch,
    this.onBack,
    this.api,
    this.store,
    this.session,
    this.onUpdate,
    this.showMenu = true,
    this.actions,
  });

  @override
  State<AppHeader> createState() => _AppHeaderState();
}

class _AppHeaderState extends State<AppHeader> {
  bool _isSearching = false;
  Map<String, dynamic>? _latestNotification;

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
    final latest = await SessionStore().getLatestUnreadNotification();
    if (mounted) {
      setState(() {
        _latestNotification = latest;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(
            color: Color(0xFFF5F5F5),
            border: Border(bottom: BorderSide(color: Color(0xFFD7D7D7), width: 1)),
          ),
          child: Row(
            children: [
              if (widget.onBack != null && !_isSearching)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.arrow_back, color: Colors.black), 
                  onPressed: widget.onBack
                ),
              
              if (!_isSearching)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Image.asset('assets/images/big-icon.png', width: 34, height: 34, fit: BoxFit.contain),
                ),

              if (_isSearching)
                Expanded(
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.black),
                        onPressed: () => setState(() => _isSearching = false),
                      ),
                      Expanded(
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFD7D7D7)),
                          ),
                          child: TextField(
                            autofocus: true,
                            onChanged: widget.onSearch,
                            style: const TextStyle(fontSize: 16, fontFamily: 'Poppins'),
                            decoration: InputDecoration(
                              hintText: widget.searchHint,
                              hintStyle: const TextStyle(fontSize: 14, fontFamily: 'Poppins'),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title.isEmpty ? 'Fone Book' : widget.title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF232323), fontFamily: 'Poppins'),
                  ),
                ),
                if (widget.showSearch)
                  IconButton(
                    icon: const Icon(Icons.search, color: Color(0xFF5F6368)),
                    onPressed: () => setState(() => _isSearching = true),
                  ),
              ],
              
              if (widget.actions != null && !_isSearching) ...widget.actions!,
              if (widget.showMenu && !_isSearching) HeaderMenu(api: widget.api, store: widget.store, session: widget.session, onUpdate: widget.onUpdate),
            ],
          ),
        ),
        if (_latestNotification != null)
          Material(
            color: const Color(0xFFFFF8DF),
            child: InkWell(
              onTap: () async {
                await NotificationDialog.show(context);
                _checkNotifications();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFD7B41A), width: 1.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active, color: Color(0xFFD7B41A), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _latestNotification!['message']?.toString() ?? _latestNotification!['title']?.toString() ?? 'Notification received',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF212529),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_ios, color: Color(0xFFD7B41A), size: 14),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
