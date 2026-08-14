import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../models/contact.dart';
import '../services/api_client.dart';

class ContactCard extends StatelessWidget {
  final DirectoryContact contact;
  final VoidCallback onTap;
  final VoidCallback? onCall;
  final bool isFavourite;
  final bool showTime;
  final bool isFirstThree;
  final bool isMyContact;
  const ContactCard({
    super.key,
    required this.contact,
    required this.onTap,
    this.onCall,
    this.isFavourite = false,
    this.showTime = false,
    this.isFirstThree = false,
    this.isMyContact = false,
  });

  String _getTimeAgo(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return "";
    try {
      final sdf = DateFormat('yyyy-MM-dd HH:mm:ss');
      final date = sdf.parse(timestamp);
      final diff = DateTime.now().difference(date);

      if (diff.inSeconds < 60) return "Just now";
      if (diff.inMinutes < 60) return "${diff.inMinutes} ${diff.inMinutes == 1 ? 'min ago' : 'mins ago'}";
      if (diff.inHours < 24) return "${diff.inHours} ${diff.inHours == 1 ? 'hr ago' : 'hrs ago'}";
      if (diff.inDays == 1) return "1 day ago";
      if (diff.inDays < 30) return "${diff.inDays} days ago";
      if (diff.inDays < 60) return "1 mon ago";
      if (diff.inDays < 365) return "${diff.inDays ~/ 30} mons ago";
      return "${diff.inDays ~/ 365} yrs ago";
    } catch (_) {
      return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    // Condition: priority == '0' and balance >= 0.30, and only for first 3 positions
    final isAd = isFirstThree && 
                 contact.priority == '0' && 
                 (double.tryParse(contact.priorityBalance) ?? 0) >= 0.30;
    
    final timeAgo = showTime ? _getTimeAgo(contact.timestamp) : "";
    final subtitle = showTime && timeAgo.isNotEmpty ? "${contact.service} • $timeAgo" : contact.service;

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isMyContact 
              ? const Color(0xFFFFECB3)
              : const Color(0xFFE9ECEF), 
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Profile Avatar / Image
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF4C5B8F),
                  ),
                  child: ClipOval(
                    child: contact.imageUrl.isNotEmpty
                        ? FadeInImage.assetNetwork(
                            placeholder: 'assets/images/user.png',
                            image: contact.imageUrl,
                            fit: BoxFit.cover,
                            imageErrorBuilder: (c, e, s) => Image.asset('assets/images/user.png', fit: BoxFit.cover),
                          )
                        : Image.asset('assets/images/user.png', fit: BoxFit.cover),
                  ),
                ),
                if (isAd)
                  Positioned(
                    top: -4,
                    left: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD7B41A),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Ad',
                        style: TextStyle(fontSize: 9, color: Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Poppins'),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),

            // Main Text Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          "${contact.name}${isFavourite ? ' ★' : ''}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF212529), fontFamily: 'Poppins'),
                        ),
                      ),
                      if (contact.verified == 1)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Image.asset('assets/images/verified.png', width: 15, height: 15),
                        ),
                    ],
                  ),

                  if (isMyContact) ...[
                    if (contact.service.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        contact.service,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF6C757D), fontFamily: 'Poppins'),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.person, size: 12, color: Color(0xFF6C757D)),
                        SizedBox(width: 3),
                        Text(
                          'My Contact',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF6C757D),
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF6C757D), fontFamily: 'Poppins'),
                      ),
                    ],
                    if (contact.location1 != null && contact.location1!.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF212529)),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              contact.location1!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, color: Color(0xFF212529), fontWeight: FontWeight.w600, fontFamily: 'Poppins'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Call Button
            InkWell(
              onTap: () async {
                if (!isMyContact) {
                  unawaited(ApiClient().post('savecallcount', {
                    'phone_no': contact.phone,
                    'location': contact.location1 ?? '',
                    'tag': '',
                    'country': contact.location ?? ''
                  }));
                }
                onCall?.call();
                launchUrl(Uri.parse('tel:${contact.phone}'));
              },
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.phone, color: Colors.black, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
