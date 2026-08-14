import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../models/user_session.dart';
import '../models/contact.dart';
import '../widgets/contact_card.dart';
import '../widgets/app_header.dart';
import 'details_screen.dart';

class WorldwideScreen extends StatefulWidget {
  final ApiClient api;
  const WorldwideScreen({super.key, required this.api});
  @override
  State<WorldwideScreen> createState() => _WorldwideScreenState();
}

class _WorldwideScreenState extends State<WorldwideScreen> {
  List<DirectoryContact> _list = [];
  bool _loading = true;
  String _country = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await SessionStore().read();
    setState(() => _loading = true);
    try {
      final data = await widget.api.get('check-contact', {'type': 'world', 'location': _country == 'All' ? null : _country});
      final List l = data;
      setState(() {
        _list = l.map((e) => DirectoryContact.fromJson(e)).toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: FutureBuilder<UserSession?>(
          future: SessionStore().read(),
          builder: (context, snapshot) {
            final session = snapshot.data;
            return Column(
              children: [
                AppHeader(
                  title: 'Fone Book',
                  onBack: () => Navigator.pop(context),
                  showMenu: session != null && session.phone != null,
                  api: widget.api,
                  store: SessionStore(),
                  session: session,
                ),
                
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(5),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                    ),
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search by country...',
                        prefixIcon: Icon(Icons.search, color: Color(0xFFD7B41A)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 15),
                      ),
                      onSubmitted: (v) {
                        setState(() {
                          _country = v.isEmpty ? 'All' : v;
                          _load();
                        });
                      },
                    ),
                  ),
                ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('World Directory', 
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF232323))),
                  ),
                ),
                const SizedBox(height: 10),
                
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFFD7B41A)))
                      : _list.isEmpty
                          ? const Center(child: Text('No contacts found in this region', style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              itemCount: _list.length,
                              itemBuilder: (c, i) => ContactCard(
                                contact: _list[i],
                                onCall: () => SessionStore().addToHistory(_list[i]),
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen(contact: _list[i]))),
                              ),
                            ),
                ),
              ],
            );
          }
        ),
      ),
    );
  }
}
