import 'package:flutter/material.dart';
import 'package:call_log/call_log.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../models/user_session.dart';
import '../models/contact.dart';
import '../widgets/contact_card.dart';
import '../widgets/app_header.dart';

class RecentScreen extends StatefulWidget {
  final ApiClient api;
  final SessionStore store;
  final UserSession session;
  const RecentScreen({super.key, required this.api, required this.store, required this.session});
  @override
  State<RecentScreen> createState() => _RecentScreenState();
}

class _RecentScreenState extends State<RecentScreen> {
  List<DirectoryContact> _list = [];
  List<DirectoryContact> _filtered = [];
  List<DirectoryContact> _favs = [];
  String _selectedFilter = 'All';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _applyFilters() {
    _filtered = _list.where((e) {
      bool matchesTab = true;
      final serviceLower = e.service.toLowerCase();
      if (_selectedFilter == 'Missed') {
        matchesTab = serviceLower.contains('missed') || serviceLower.contains('rejected');
      } else if (_selectedFilter == 'Incoming') {
        matchesTab = serviceLower.contains('incoming');
      } else if (_selectedFilter == 'Outgoing') {
        matchesTab = serviceLower.contains('outgoing') || serviceLower == 'call';
      }

      bool matchesSearch = true;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        matchesSearch = e.name.toLowerCase().contains(q) ||
            e.phone.toLowerCase().contains(q) ||
            e.service.toLowerCase().contains(q);
      }

      return matchesTab && matchesSearch;
    }).toList();
  }

  void _load() async {
    final favs = await widget.store.getFavourites();
    List<DirectoryContact> history = [];

    try {
      final status = await Permission.phone.request();
      if (status.isGranted) {
        final Iterable<CallLogEntry> entries = await CallLog.get();
        final DateFormat sdf = DateFormat('yyyy-MM-dd HH:mm:ss');
        for (final entry in entries) {
          final String rawName = entry.name?.trim() ?? '';
          final String phone = entry.formattedNumber ?? entry.number ?? '';
          final String name = rawName.isNotEmpty ? rawName : (phone.isNotEmpty ? phone : 'Unknown');

          String service = 'Call';
          switch (entry.callType) {
            case CallType.incoming:
              service = 'Incoming Call';
              break;
            case CallType.outgoing:
              service = 'Outgoing Call';
              break;
            case CallType.missed:
              service = 'Missed Call';
              break;
            case CallType.rejected:
              service = 'Rejected Call';
              break;
            case CallType.blocked:
              service = 'Blocked Call';
              break;
            default:
              service = 'Call';
          }

          final String timestamp = entry.timestamp != null
              ? sdf.format(DateTime.fromMillisecondsSinceEpoch(entry.timestamp!))
              : '';

          history.add(DirectoryContact(
            name: name,
            service: service,
            phone: phone,
            timestamp: timestamp,
          ));
        }
      }
    } catch (e) {
      debugPrint('Error reading call log: $e');
    }

    if (history.isEmpty) {
      history = await widget.store.getHistory();
    }

    setState(() {
      _list = history;
      _favs = favs;
      _applyFilters();
    });
  }

  Widget _buildFilterTabs() {
    final tabs = ['All', 'Missed', 'Incoming', 'Outgoing'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: tabs.map((tab) {
          final isSelected = _selectedFilter == tab;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedFilter = tab;
                    _applyFilters();
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF4C5B8F) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF4C5B8F) : const Color(0xFFE0E0E0),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isSelected
                            ? const Color(0xFF4C5B8F).withValues(alpha: 0.25)
                            : Colors.black.withValues(alpha: 0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      tab,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? Colors.white : const Color(0xFF616161),
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
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
              title: 'Recent',
              showSearch: true,
              searchHint: 'Search Recent',
              onSearch: (q) {
                setState(() {
                  _searchQuery = q;
                  _applyFilters();
                });
              },
              api: widget.api,
              store: widget.store,
              session: widget.session,
              onUpdate: _load,
            ),
            _buildFilterTabs(),
            if (_filtered.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    _list.isEmpty
                        ? 'No Recent Contacts'
                        : 'No $_selectedFilter Calls',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6C757D),
                      fontFamily: 'Poppins',
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (c, i) {
                    final contact = _filtered[i];
                    final isFav = _favs.any((e) => e.phone == contact.phone);
                    final isMyContact = contact.category == 'my_contact';
                    
                    return Dismissible(
                      key: Key('recent_${contact.phone}_${contact.timestamp}_$i'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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
                            title: const Text('Delete Recent Call', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
                            content: Text('Are you sure you want to remove ${contact.name} from your recent call history?'),
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
                        setState(() {
                          _list.removeWhere((e) => e.phone == contact.phone && e.timestamp == contact.timestamp);
                          _applyFilters();
                        });
                        await widget.store.removeFromHistory(contact);
                      },
                      child: ContactCard(
                        contact: contact,
                        isFavourite: isFav,
                        showFavouriteIcon: false,
                        isMyContact: isMyContact,
                        showTime: true,
                        onCall: () => widget.store.addToHistory(contact).then((_) => _load()),
                        onFavouriteToggle: () async {
                          await widget.store.toggleFavourite(contact);
                          _load();
                        },
                        onTap: () {},
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

