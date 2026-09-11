import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/contact.dart';
import '../services/session_store.dart';
import '../services/api_client.dart';
import '../utils/string_utils.dart';

class CallDetailsScreen extends StatefulWidget {
  final DirectoryContact contact;
  final SessionStore store;

  const CallDetailsScreen({
    super.key,
    required this.contact,
    required this.store,
  });

  @override
  State<CallDetailsScreen> createState() => _CallDetailsScreenState();
}

enum AppCallType { incoming, outgoing, missed, rejected, blocked }

class _CallDetailsItem {
  final String callTypeLabel;
  final AppCallType callType;
  final DateTime timestamp;
  final int durationSeconds;

  _CallDetailsItem({
    required this.callTypeLabel,
    required this.callType,
    required this.timestamp,
    required this.durationSeconds,
  });
}

class _CallDetailsGroup {
  final String dateTitle;
  final List<_CallDetailsItem> items;

  _CallDetailsGroup({
    required this.dateTitle,
    required this.items,
  });
}

class _CallDetailsScreenState extends State<CallDetailsScreen> {
  bool _loading = true;
  List<_CallDetailsGroup> _groupedLogs = [];
  String _profession = '';

  @override
  void initState() {
    super.initState();
    final initialService = widget.contact.service.trim();
    if (widget.contact.category != 'my_contact' &&
        initialService.isNotEmpty &&
        initialService.toLowerCase() != 'outgoing call' &&
        initialService.toLowerCase() != 'null') {
      _profession = initialService;
    }
    _loadCallHistory();
  }

  String _normalize(String? phone) {
    if (phone == null) return '';
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
  }

  String _getDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final checkDate = DateTime(date.year, date.month, date.day);

    if (checkDate == today) {
      return 'Today';
    } else if (checkDate == yesterday) {
      return 'Yesterday';
    } else if (date.year == now.year) {
      return DateFormat('MMM d').format(date);
    } else {
      return DateFormat('MMM d, yyyy').format(date);
    }
  }

  Future<void> _makeCall() async {
    final cleanPhone = widget.contact.phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      widget.store.addToHistory(widget.contact);
    }
  }

  Future<void> _openWhatsApp() async {
    final wpNum = (widget.contact.whatsapp != null &&
            widget.contact.whatsapp!.isNotEmpty &&
            widget.contact.whatsapp != 'null')
        ? widget.contact.whatsapp!
        : widget.contact.phone;

    var cleanPhone = wpNum.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.length == 10) {
      cleanPhone = '91$cleanPhone';
    }

    if (cleanPhone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp number not available')),
        );
      }
      return;
    }

    final uri = Uri.parse('https://wa.me/$cleanPhone');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp is not installed or number is not registered on WhatsApp')),
        );
      }
    } catch (e) {
      debugPrint('WhatsApp launch error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp is not installed or number is not registered on WhatsApp')),
        );
      }
    }
  }

  Future<void> _sendSms() async {
    final cleanPhone = widget.contact.phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    final uri = Uri.parse('sms:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _loadCallHistory() async {
    setState(() => _loading = true);
    final targetNorm = _normalize(widget.contact.phone);
    final List<_CallDetailsItem> allItems = [];

    final session = await widget.store.read();
    final effectiveUserId = (session.email != null && session.email!.trim().isNotEmpty)
        ? session.email!.trim()
        : (session.phone != null && session.phone!.trim().isNotEmpty)
            ? session.phone!.trim()
            : 'guest@fonebook.com';

    try {
      final backendLogs = await ApiClient().getCallHistoryFromBackend(userId: effectiveUserId);
      for (final raw in backendLogs) {
        if (raw is Map) {
          final phone = (raw['phone_number'] ?? raw['phone'] ?? '').toString();
          final hNorm = _normalize(phone);
          if (targetNorm.isNotEmpty && hNorm.isNotEmpty && targetNorm == hNorm) {
            final s = (raw['service'] ?? '').toString().trim();
            if (_profession.isEmpty &&
                s.isNotEmpty &&
                s.toLowerCase() != 'outgoing call' &&
                s.toLowerCase() != 'null') {
              _profession = s;
            }
            final timeStr = (raw['call_time'] ?? raw['created_at'] ?? '').toString();
            DateTime dt = DateTime.now();
            if (timeStr.isNotEmpty) {
              try {
                dt = DateTime.parse(timeStr);
              } catch (_) {
                dt = (DateFormat('yyyy-MM-dd HH:mm:ss').tryParse(timeStr)) ?? DateTime.now();
              }
            }
            allItems.add(_CallDetailsItem(
              callTypeLabel: 'Call',
              callType: AppCallType.outgoing,
              timestamp: dt,
              durationSeconds: 0,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('[CallDetailsScreen] Error loading backend history: $e');
    }

    if (_profession.isEmpty) {
      final favs = await widget.store.getFavourites();
      for (final f in favs) {
        if (_normalize(f.phone) == targetNorm) {
          final s = f.service.trim();
          if (s.isNotEmpty &&
              s.toLowerCase() != 'outgoing call' &&
              s.toLowerCase() != 'null') {
            _profession = s;
            break;
          }
        }
      }
    }

    if (allItems.isEmpty) {
      final localHistory = await widget.store.getHistory();
      for (final h in localHistory) {
        final hNorm = _normalize(h.phone);
        if (targetNorm.isNotEmpty && hNorm.isNotEmpty && targetNorm == hNorm) {
          final s = h.service.trim();
          if (_profession.isEmpty &&
              s.isNotEmpty &&
              s.toLowerCase() != 'outgoing call' &&
              s.toLowerCase() != 'null') {
            _profession = s;
          }
          DateTime dt = DateTime.now();
          if (h.timestamp != null && h.timestamp!.isNotEmpty) {
            try {
              dt = DateTime.parse(h.timestamp!);
            } catch (_) {
              dt = (DateFormat('yyyy-MM-dd HH:mm:ss').tryParse(h.timestamp!)) ?? DateTime.now();
            }
          }
          allItems.add(_CallDetailsItem(
            callTypeLabel: 'Call',
            callType: AppCallType.outgoing,
            timestamp: dt,
            durationSeconds: 0,
          ));
        }
      }
    }

    allItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final Map<String, List<_CallDetailsItem>> groupedMap = {};
    for (final item in allItems) {
      final header = _getDateHeader(item.timestamp);
      groupedMap.putIfAbsent(header, () => []).add(item);
    }

    final List<_CallDetailsGroup> groups = groupedMap.entries.map((e) {
      return _CallDetailsGroup(dateTitle: e.key, items: e.value);
    }).toList();

    if (mounted) {
      setState(() {
        _groupedLogs = groups;
        _loading = false;
      });
    }
  }

  Widget _buildAvatar(String name, String? imageUrl) {
    return Container(
      width: 56,
      height: 56,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF4C5B8F),
      ),
      child: ClipOval(
        child: (imageUrl != null && imageUrl.isNotEmpty)
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Image.asset('assets/images/user.png', fit: BoxFit.cover),
              )
            : Image.asset('assets/images/user.png', fit: BoxFit.cover),
      ),
    );
  }

  Widget _buildCallTypeIcon(AppCallType type, String label) {
    if (type == AppCallType.missed) {
      return const Icon(Icons.call_missed, color: Color(0xFFD93025), size: 20);
    } else if (label.toLowerCase().contains('incoming')) {
      return const Icon(Icons.call_received, color: Color(0xFF1E8E3E), size: 20);
    } else if (label.toLowerCase().contains('rejected') || label.toLowerCase().contains('blocked')) {
      return const Icon(Icons.block, color: Color(0xFF757575), size: 20);
    } else {
      return const Icon(Icons.north_east, color: Color(0xFF1A73E8), size: 20);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.contact.name.isNotEmpty ? widget.contact.name : widget.contact.phone;
    final displayPhone = widget.contact.phone;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F9),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF4C5B8F)))
            : Column(
                children: [
                  Container(
                    height: 60,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF5F5F5),
                      border: Border(bottom: BorderSide(color: Color(0xFFD7D7D7), width: 1)),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Color(0xFF232323)),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: Text(
                            'Call Details',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF232323),
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Card(
                      elevation: 0.5,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _buildAvatar(displayName, widget.contact.image),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName.toTitleCase(),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF202124),
                                      fontFamily: 'Poppins',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (_profession.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      _profession.toTitleCase(),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF4C5B8F),
                                        fontFamily: 'Poppins',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  if (widget.contact.category == 'my_contact') ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4C5B8F).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          Icon(Icons.person, size: 12, color: Color(0xFF4C5B8F)),
                                          SizedBox(width: 4),
                                          Text(
                                            'My Contact',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF4C5B8F),
                                              fontFamily: 'Poppins',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                // Call History Section Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Call History',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF202124),
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ),
                ),

                // Call History Grouped List
                Expanded(
                  child: _groupedLogs.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.history,
                                  size: 48,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No previous call history found',
                                  style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontFamily: 'Poppins'),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          itemCount: _groupedLogs.length,
                          itemBuilder: (context, groupIndex) {
                            final group = _groupedLogs[groupIndex];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 10, bottom: 6, left: 4),
                                  child: Text(
                                    group.dateTitle,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF5F6368),
                                      fontFamily: 'Poppins',
                                    ),
                                  ),
                                ),
                                Card(
                                  elevation: 0.5,
                                  color: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  child: Column(
                                    children: List.generate(group.items.length, (itemIndex) {
                                      final item = group.items[itemIndex];
                                      final timeStr = DateFormat('hh:mm a').format(item.timestamp);
                                      final isMissed = item.callType == AppCallType.missed;

                                      return Column(
                                        children: [
                                          ListTile(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                                            leading: Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: isMissed
                                                    ? const Color(0xFFFCE8E6)
                                                    : (item.callTypeLabel.toLowerCase().contains('incoming')
                                                        ? const Color(0xFFE6F4EA)
                                                        : const Color(0xFFE8F0FE)),
                                                shape: BoxShape.circle,
                                              ),
                                              child: _buildCallTypeIcon(item.callType, item.callTypeLabel),
                                            ),
                                            title: Text(
                                              DateFormat('MMM d, yyyy').format(item.timestamp),
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF202124),
                                                fontFamily: 'Poppins',
                                              ),
                                            ),
                                            subtitle: Text(
                                              timeStr,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: Color(0xFF5F6368),
                                                fontFamily: 'Poppins',
                                              ),
                                            ),
                                          ),
                                          if (itemIndex < group.items.length - 1)
                                            const Divider(height: 1, indent: 64, endIndent: 16),
                                        ],
                                      );
                                    }),
                                  ),
                                ),
                              ],
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
