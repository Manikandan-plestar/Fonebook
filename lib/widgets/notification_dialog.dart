import 'package:flutter/material.dart';
import '../services/session_store.dart';

class NotificationDialog extends StatefulWidget {
  const NotificationDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) => const NotificationDialog(),
    );
    await SessionStore().markNotificationsRead();
  }

  @override
  State<NotificationDialog> createState() => _NotificationDialogState();
}

class _NotificationDialogState extends State<NotificationDialog> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await SessionStore().getNotifications();
    if (mounted) {
      setState(() {
        _notifications = list;
        _loading = false;
      });
    }
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.delete_outline, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text(
              'Delete Notification',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF212529)),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete this notification?',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Color(0xFF495057)),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteAt(int index) async {
    await SessionStore().deleteNotification(index);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      elevation: 10,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: const [
              Icon(Icons.notifications_outlined, color: Color(0xFFD7B41A), size: 26),
              SizedBox(width: 8),
              Text(
                'Notifications',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  fontSize: 19,
                  color: Color(0xFF212529),
                ),
              ),
            ],
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.close, color: Colors.grey, size: 22),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: screenSize.width * 0.82,
        height: screenSize.height * 0.42,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFD7B41A)))
            : _notifications.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notifications_none, size: 56, color: Colors.grey.shade400),
                        const SizedBox(height: 14),
                        const Text(
                          'No notifications yet',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _notifications.length,
                    separatorBuilder: (c, i) => const Divider(height: 1, color: Color(0xFFE9ECEF)),
                    itemBuilder: (c, i) {
                      final item = _notifications[i];
                      final title = item['title']?.toString() ?? 'Notification';
                      final message = item['message']?.toString() ?? '';
                      final timestamp = item['timestamp']?.toString() ?? '';
                      final itemKey = item['id']?.toString() ?? '$i-$timestamp';

                      return Dismissible(
                        key: Key(itemKey),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (direction) async {
                          return await _confirmDelete(context);
                        },
                        onDismissed: (direction) async {
                          await _deleteAt(i);
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.shade400,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: const [
                              Icon(Icons.delete_outline, color: Colors.white, size: 22),
                              SizedBox(width: 6),
                              Text(
                                'Delete',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFFF8DF),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.phone_android, color: Color(0xFFD7B41A), size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.5,
                                        color: Color(0xFF212529),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      message,
                                      style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        color: Color(0xFF495057),
                                        height: 1.35,
                                      ),
                                    ),
                                    if (timestamp.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        timestamp,
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 11.5,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                tooltip: 'Delete notification',
                                onPressed: () async {
                                  final confirm = await _confirmDelete(context);
                                  if (confirm) {
                                    await _deleteAt(i);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Close',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, color: Color(0xFF4C5B8F), fontSize: 15),
          ),
        ),
      ],
    );
  }
}
