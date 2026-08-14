import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../models/user_session.dart';
import 'header_menu.dart';

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

  @override
  Widget build(BuildContext context) {
    return Container(
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
              child: Image.asset('assets/images/logo.png', width: 34, height: 34, fit: BoxFit.contain),
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
    );
  }
}
