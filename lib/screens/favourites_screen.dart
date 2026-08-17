import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../models/user_session.dart';
import '../models/contact.dart';
import '../widgets/contact_card.dart';
import '../widgets/app_header.dart';
import 'details_screen.dart';

class FavouritesScreen extends StatefulWidget {
  final ApiClient api;
  final SessionStore store;
  final UserSession session;
  const FavouritesScreen({super.key, required this.api, required this.store, required this.session});
  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> {
  List<DirectoryContact> _list = [];
  List<DirectoryContact> _filtered = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() async {
    final favs = await widget.store.getFavourites();
    setState(() {
      _list = favs;
      _filtered = _list;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Favourites',
              onBack: () => Navigator.pop(context),
              showSearch: true,
              searchHint: 'Search Favourites',
              onSearch: (q) {
                setState(() {
                  _filtered = _list.where((e) => e.name.toLowerCase().contains(q.toLowerCase())).toList();
                });
              },
              api: widget.api,
              store: widget.store,
              session: widget.session,
              onUpdate: _load,
            ),
            if (_list.isEmpty)
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 30),
                  child: Center(
                    child: Text('No Phone numbers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (c, i) => ContactCard(
                    contact: _filtered[i],
                    isFavourite: true,
                    onCall: () => widget.store.addToHistory(_filtered[i]),
                    onFavouriteToggle: () async {
                      await widget.store.toggleFavourite(_filtered[i]);
                      _load();
                    },
                    onTap: () {},
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
