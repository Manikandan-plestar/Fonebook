import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../models/user_session.dart';
import '../models/contact.dart';
import '../widgets/contact_card.dart';
import '../widgets/app_header.dart';
import 'call_details_screen.dart';

class RecentScreen extends StatefulWidget {
  final ApiClient api;
  final SessionStore store;
  final UserSession session;

  const RecentScreen({
    super.key,
    required this.api,
    required this.store,
    required this.session,
  });

  @override
  State<RecentScreen> createState() => _RecentScreenState();
}

class _RecentScreenState extends State<RecentScreen> {
  List<DirectoryContact> _list = [];
  List<DirectoryContact> _filtered = [];
  List<DirectoryContact> _favs = [];
  String _selectedFilter = 'All';
  String _searchQuery = '';
  bool _loading = false;

  // Multi-select Mode state
  bool _isSelectionMode = false;
  final Set<String> _selectedKeys = {};

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.store.removeListener(_load);
    super.dispose();
  }

  String get _currentUserId =>
      (widget.session.email != null && widget.session.email!.trim().isNotEmpty)
          ? widget.session.email!.trim()
          : (widget.session.phone != null && widget.session.phone!.trim().isNotEmpty)
              ? widget.session.phone!.trim()
              : 'guest@fonebook.com';

  Future<String> _getEffectiveUserId() async {
    final session = await widget.store.read();
    if (session.email != null && session.email!.trim().isNotEmpty) {
      return session.email!.trim();
    }
    if (session.phone != null && session.phone!.trim().isNotEmpty) {
      return session.phone!.trim();
    }
    if (widget.session.email != null && widget.session.email!.trim().isNotEmpty) {
      return widget.session.email!.trim();
    }
    if (widget.session.phone != null && widget.session.phone!.trim().isNotEmpty) {
      return widget.session.phone!.trim();
    }
    return 'guest@fonebook.com';
  }

  String _normalizePhone(String? phone) {
    if (phone == null || phone.isEmpty) return '';
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
  }

  String _getContactGroupKey(DirectoryContact c) {
    final norm = _normalizePhone(c.phone);
    if (norm.isNotEmpty) {
      return 'phone_$norm';
    }
    return 'name_${c.name.trim().toLowerCase()}';
  }

  void _applyFilters() {
    final filteredRaw = _list.where((e) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return e.name.toLowerCase().contains(q) ||
            e.phone.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    final Map<String, DirectoryContact> groupedMap = {};
    for (final contact in filteredRaw) {
      final key = _getContactGroupKey(contact);
      if (!groupedMap.containsKey(key)) {
        groupedMap[key] = contact;
      } else {
        final existing = groupedMap[key]!;
        final existingTime = existing.timestamp ?? '';
        final currentTime = contact.timestamp ?? '';
        if (currentTime.compareTo(existingTime) > 0) {
          groupedMap[key] = contact;
        }
      }
    }

    final groupedList = groupedMap.values.toList();
    groupedList.sort((a, b) {
      final timeA = a.timestamp ?? '';
      final timeB = b.timestamp ?? '';
      return timeB.compareTo(timeA);
    });

    _filtered = groupedList;
  }

  Future<void> _load() async {
    final effectiveUserId = await _getEffectiveUserId();
    final favs = await widget.store.getFavourites();
    List<DirectoryContact> history = [];
    bool backendSuccess = false;

    try {
      final backendLogs = await widget.api.getCallHistoryFromBackend(userId: effectiveUserId);
      debugPrint('[RecentScreen] Loaded ${backendLogs.length} calls for $effectiveUserId');
      backendSuccess = true;
      if (backendLogs.isNotEmpty) {
        for (final raw in backendLogs) {
          if (raw is Map) {
            final name = (raw['name'] ?? raw['recipient_name'] ?? 'Unknown').toString();
            final phone = (raw['phone_number'] ?? raw['phone'] ?? '').toString();
            final rawService = (raw['service'] ?? '').toString();
            final service = (rawService.isNotEmpty &&
                rawService.toLowerCase() != 'outgoing call' &&
                rawService.toLowerCase() != 'null')
                ? rawService
                : '';
            final time = (raw['call_time'] ?? raw['created_at'] ?? '').toString();

            if (phone.isNotEmpty) {
              history.add(DirectoryContact(
                name: name,
                phone: phone,
                service: service,
                timestamp: time,
              ));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[RecentScreen] Error fetching backend call logs: $e');
    }

    if (!backendSuccess) {
      history = await widget.store.getHistory();
    }

    if (mounted) {
      setState(() {
        _list = history;
        _favs = favs;
        _applyFilters();
      });
    }
  }

  void _toggleSelection(DirectoryContact contact) {
    final key = _getContactGroupKey(contact);
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
        if (_selectedKeys.isEmpty) _isSelectionMode = false;
      } else {
        _selectedKeys.add(key);
        _isSelectionMode = true;
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedKeys.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Selected Calls', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete ${_selectedKeys.length} selected call item(s)?'),
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

    if (!confirmed) return;

    final keysToRemove = Set<String>.from(_selectedKeys);
    final targets = _list.where((e) => keysToRemove.contains(_getContactGroupKey(e))).toList();
    final effectiveUserId = await _getEffectiveUserId();

    // Optimistic UI update
    setState(() {
      _list.removeWhere((e) => keysToRemove.contains(_getContactGroupKey(e)));
      _selectedKeys.clear();
      _isSelectionMode = false;
      _applyFilters();
    });

    // Remove from local cache & backend REST API
    for (final target in targets) {
      await widget.store.removeFromHistory(target);
    }
    await widget.api.deleteCallsFromBackend(
      userId: effectiveUserId,
      callIds: targets.map((t) => t.phone).toList(),
    );
  }

  Future<void> _confirmClearAll() async {
    if (_list.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All Call History', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to wipe your entire call history? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins', color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Clear All', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ) ?? false;

    if (!confirmed) return;

    final effectiveUserId = await _getEffectiveUserId();

    // Optimistic UI update
    setState(() {
      _list.clear();
      _selectedKeys.clear();
      _isSelectionMode = false;
      _applyFilters();
    });

    // Clear backend users_calls array & local store
    await widget.store.clearHistory();
    await widget.api.deleteCallsFromBackend(userId: effectiveUserId, clearAll: true);
  }

  Widget _buildTopActionBar() {
    if (_isSelectionMode) {
      return Padding(
        padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF4C5B8F),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedKeys.clear();
                  });
                },
              ),
              const SizedBox(width: 4),
              Text(
                '${_selectedKeys.length} selected',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontFamily: 'Poppins',
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  _selectedKeys.length == _filtered.length ? Icons.select_all : Icons.deselect,
                  color: Colors.white,
                ),
                tooltip: 'Select All',
                onPressed: () {
                  setState(() {
                    if (_selectedKeys.length == _filtered.length) {
                      _selectedKeys.clear();
                      _isSelectionMode = false;
                    } else {
                      _selectedKeys.clear();
                      for (final c in _filtered) {
                        _selectedKeys.add(_getContactGroupKey(c));
                      }
                    }
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                tooltip: 'Delete Selected',
                onPressed: _deleteSelected,
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Recents',
              showSearch: true,
              searchHint: 'Search Recents',
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
            _buildTopActionBar(),
            if (_filtered.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No Recents',
                    style: TextStyle(
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
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 20),
                    itemCount: _filtered.length,
                    itemBuilder: (c, i) {
                      final contact = _filtered[i];
                      final key = _getContactGroupKey(contact);
                      final isSelected = _selectedKeys.contains(key);
                      final isFav = _favs.any((e) => e.phone == contact.phone);
                      final isMyContact = contact.category == 'my_contact';

                      return Dismissible(
                        key: Key('recent_${contact.phone}_${contact.timestamp}_$i'),
                        direction: _isSelectionMode ? DismissDirection.none : DismissDirection.endToStart,
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
                            _list.removeWhere((e) => _getContactGroupKey(e) == key);
                            _applyFilters();
                          });
                          await widget.store.removeFromHistory(contact);
                          await widget.api.deleteCallsFromBackend(
                            userId: _currentUserId,
                            callIds: [contact.phone],
                          );
                        },
                        child: GestureDetector(
                          onLongPress: () => _toggleSelection(contact),
                          child: ContactCard(
                            contact: contact,
                            isFavourite: isFav,
                            showFavouriteIcon: false,
                            isMyContact: isMyContact,
                            showTime: true,
                            isSelectionMode: _isSelectionMode,
                            isSelected: isSelected,
                            onCall: () => widget.store.addToHistory(contact).then((_) => _load()),
                            onFavouriteToggle: () async {
                              await widget.store.toggleFavourite(contact);
                              _load();
                            },
                            onTap: () {
                              if (_isSelectionMode) {
                                _toggleSelection(contact);
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CallDetailsScreen(
                                      contact: contact,
                                      store: widget.store,
                                    ),
                                  ),
                                ).then((_) => _load());
                              }
                            },
                          ),
                        ),
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
