import 'package:flutter/material.dart';
import 'package:call_log/call_log.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/contact.dart';
import '../services/session_store.dart';

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

class _CallDetailsItem {
  final String callTypeLabel;
  final CallType callType;
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
  bool _permissionDenied = false;
  List<_CallDetailsGroup> _groupedLogs = [];

  @override
  void initState() {
    super.initState();
    _loadCallHistory();
  }

  String _normalize(String? phone) {
    if (phone == null) return '';
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '00:00';
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    final minStr = mins.toString().padLeft(2, '0');
    final secStr = secs.toString().padLeft(2, '0');
    return '$minStr:$secStr';
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

    try {
      final status = await Permission.phone.request();
      if (status.isGranted) {
        final Iterable<CallLogEntry> entries = await CallLog.get();
        for (final entry in entries) {
          final entryNorm = _normalize(entry.formattedNumber ?? entry.number ?? '');
          if (targetNorm.isNotEmpty && entryNorm.isNotEmpty && targetNorm == entryNorm) {
            String label = 'Call';
            switch (entry.callType) {
              case CallType.incoming:
                label = 'Incoming Call';
                break;
              case CallType.outgoing:
                label = 'Outgoing Call';
                break;
              case CallType.missed:
                label = 'Missed Call';
                break;
              case CallType.rejected:
                label = 'Rejected Call';
                break;
              case CallType.blocked:
                label = 'Blocked Call';
                break;
              default:
                label = 'Call';
            }

            final dt = entry.timestamp != null
                ? DateTime.fromMillisecondsSinceEpoch(entry.timestamp!)
                : DateTime.now();

            allItems.add(_CallDetailsItem(
              callTypeLabel: label,
              callType: entry.callType ?? CallType.outgoing,
              timestamp: dt,
              durationSeconds: entry.duration ?? 0,
            ));
          }
        }
      } else {
        _permissionDenied = true;
      }
    } catch (e) {
      debugPrint('Error reading call logs for details: $e');
    }

    if (allItems.isEmpty) {
      final localHistory = await widget.store.getHistory();
      for (final h in localHistory) {
        final hNorm = _normalize(h.phone);
        if (targetNorm.isNotEmpty && hNorm.isNotEmpty && targetNorm == hNorm) {
          final dt = (h.timestamp != null ? DateTime.tryParse(h.timestamp!) : null) ?? DateTime.now();
          allItems.add(_CallDetailsItem(
            callTypeLabel: h.service.isNotEmpty ? h.service : 'Call',
            callType: h.service.toLowerCase().contains('missed')
                ? CallType.missed
                : (h.service.toLowerCase().contains('incoming') ? CallType.incoming : CallType.outgoing),
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

  Widget _buildAvatar(String displayName, String? imagePath) {
    final hasImg = imagePath != null && imagePath.trim().isNotEmpty && imagePath.trim().toLowerCase() != 'null';
    if (hasImg) {
      final String fullUrl = imagePath!.startsWith('http')
          ? imagePath
          : 'https://apps.plestarinc.com:3002/uploads/${imagePath.replaceAll(RegExp(r'^/uploads/'), '')}';
      return CircleAvatar(
        radius: 34,
        backgroundColor: const Color(0xFFE8EAED),
        backgroundImage: NetworkImage(fullUrl),
      );
    }

    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 34,
      backgroundColor: const Color(0xFF4C5B8F),
      child: Text(
        initial,
        style: const TextStyle(fontSize: 26, color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Poppins'),
      ),
    );
  }

  Widget _buildCallTypeIcon(CallType type, String label) {
    if (label.toLowerCase().contains('missed') || type == CallType.missed) {
      return const Icon(Icons.close, color: Color(0xFFD93025), size: 20);
    } else if (label.toLowerCase().contains('incoming') || type == CallType.incoming) {
      return const Icon(Icons.south_west, color: Color(0xFF1E8E3E), size: 20);
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0.5,
        automaticallyImplyLeading: false,
        title: const Text(
          'Call Details',
          style: TextStyle(color: Color(0xFF202124), fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'Poppins'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4C5B8F)))
          : Column(
              children: [
                // Top Header Box
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(20),
                  width: double.infinity,
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildAvatar(displayName, widget.contact.image),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF202124),
                                    fontFamily: 'Poppins',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  displayPhone,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF5F6368),
                                    fontFamily: 'Poppins',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      // Action buttons: Call & Message
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _makeCall,
                              icon: const Icon(Icons.call, size: 18),
                              label: const Text('Call', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E8E3E),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                elevation: 0,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _openWhatsApp,
                              icon: Image.asset('assets/images/whatsapp.png', width: 20, height: 20),
                              label: const Text(
                                'WhatsApp',
                                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, color: Color(0xFF25D366)),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF25D366)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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
                                  _permissionDenied ? Icons.no_cell : Icons.history,
                                  size: 48,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _permissionDenied
                                      ? 'Call log permission required to view full call history'
                                      : 'No previous call history found',
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
                                      final isMissed = item.callTypeLabel.toLowerCase().contains('missed') || item.callType == CallType.missed;
                                      final durationStr = isMissed ? 'Missed Call' : _formatDuration(item.durationSeconds);

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
                                              item.callTypeLabel,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: isMissed ? const Color(0xFFD93025) : const Color(0xFF202124),
                                                fontFamily: 'Poppins',
                                              ),
                                            ),
                                            subtitle: Text(
                                              '$timeStr • $durationStr',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: isMissed ? const Color(0xFFD93025) : const Color(0xFF5F6368),
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
    );
  }
}
