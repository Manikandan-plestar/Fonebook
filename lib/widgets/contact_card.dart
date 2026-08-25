import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/contact.dart';
import '../services/api_client.dart';

class ContactCard extends StatelessWidget {
  final DirectoryContact contact;
  final VoidCallback onTap;
  final VoidCallback? onCall;
  final VoidCallback? onFavouriteToggle;
  final VoidCallback? onWhatsAppTap;
  final bool isSubscribed;
  final bool isFavourite;
  final bool showFavouriteIcon;
  final bool showTime;
  final bool isFirstThree;
  final bool isMyContact;
  final bool isSponsored;

  const ContactCard({
    super.key,
    required this.contact,
    required this.onTap,
    this.onCall,
    this.onFavouriteToggle,
    this.onWhatsAppTap,
    this.isSubscribed = false,
    this.isFavourite = false,
    this.showFavouriteIcon = true,
    this.showTime = false,
    this.isFirstThree = false,
    this.isMyContact = false,
    this.isSponsored = false,
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

  void _showContactActionDialog(BuildContext context) {
    final wpNum = (contact.whatsapp != null && contact.whatsapp!.isNotEmpty && contact.whatsapp != 'null')
        ? contact.whatsapp!
        : contact.phone;

    final hasName = contact.name.isNotEmpty;
    final hasService = contact.service.isNotEmpty && contact.service != 'null';
    final String titleText = (hasName && hasService)
        ? '${contact.name} - ${contact.service}'
        : (hasName ? contact.name : (hasService ? contact.service : 'Contact Options'));

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shadowColor: Colors.black.withValues(alpha: 0.2),
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        content: SizedBox(
          width: MediaQuery.of(ctx).size.width * 0.85,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titleText,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                  color: Color(0xFF212529),
                ),
              ),
              const SizedBox(height: 20),

              // Option 1: Call
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  if (!isMyContact) {
                    unawaited(ApiClient().post('savecallcount', {
                      'phone_no': contact.phone,
                      'location': contact.location1 ?? '',
                      'tag': '',
                      'country': contact.location ?? ''
                    }));
                  }
                  onCall?.call();
                  final cleanPhone = contact.phone.replaceAll(RegExp(r'[^0-9+]'), '');
                  if (cleanPhone.isNotEmpty) {
                    launchUrl(Uri.parse('tel:$cleanPhone'));
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.phone, color: Colors.black, size: 26),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Call',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Color(0xFF212529),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            contact.phone,
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const Divider(height: 16, thickness: 0.8),

              // Option 2: WhatsApp
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  final cleanPhone = wpNum.replaceAll(RegExp(r'[^0-9+]'), '');
                  if (cleanPhone.isNotEmpty) {
                    launchUrl(Uri.parse('https://wa.me/$cleanPhone'));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('WhatsApp number not available')),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                  child: Row(
                    children: [
                      Image.asset('assets/images/whatsapp.png', width: 28, height: 28),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'WhatsApp',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Color(0xFF212529),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            wpNum,
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curvedAnim = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(curvedAnim),
          child: FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: child,
          ),
        );
      },
    );
  }

  void _showRemoveFavouriteDialog(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim1, anim2) => AlertDialog(
        backgroundColor: const Color(0xFFF0F2F5), // White with grey mix
        surfaceTintColor: const Color(0xFFF0F2F5),
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFFFF3CD),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.star_rounded, color: Color(0xFFD7B41A), size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Remove Favourite',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                  color: Color(0xFF212529),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to remove ${contact.name.isNotEmpty ? contact.name : 'this contact'} from your favourites?',
          style: const TextStyle(
            fontSize: 14,
            fontFamily: 'Poppins',
            color: Color(0xFF495057),
          ),
        ),
        actionsPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16, top: 0),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6C757D),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onFavouriteToggle?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC3545),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'Yes, Remove',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      ),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curvedAnim = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1.0).animate(curvedAnim),
          child: FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSponsoredCard = isSponsored || contact.priority == '0';
    
    final timeAgo = showTime ? _getTimeAgo(contact.timestamp) : "";
    final subtitle = showTime && timeAgo.isNotEmpty ? "${contact.service} • $timeAgo" : contact.service;

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMyContact ? const Color(0xFFFFFDE7) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isMyContact 
              ? const Color(0xFFFFEC8B)
              : (isSponsoredCard ? const Color(0xFFFFD54F) : const Color(0xFFE9ECEF)), 
            width: isMyContact || isSponsoredCard ? 1.2 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isMyContact || isSponsoredCard
                ? const Color(0xFFD7B41A).withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Profile Avatar / Image
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSponsoredCard)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: Text(
                      'Sponsored',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4A4A4A),
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ),
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF4C5B8F),
                  ),
                  child: ClipOval(
                    child: contact.imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: contact.imageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 150,
                            memCacheHeight: 150,
                            placeholder: (context, url) => Image.asset('assets/images/user.png', fit: BoxFit.cover),
                            errorWidget: (context, url, error) => Image.asset('assets/images/user.png', fit: BoxFit.cover),
                          )
                        : Image.asset('assets/images/user.png', fit: BoxFit.cover),
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
                          contact.name,
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
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF6C757D), fontFamily: 'Poppins'),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBE48A),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.person, size: 10, color: Color(0xFF4A3800)),
                          SizedBox(width: 3),
                          Text(
                            'My Contact',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF4A3800),
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
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

            // Favourite Star Icon (before Phone Icon)
            if (showFavouriteIcon && (onFavouriteToggle != null || isFavourite)) ...[
              InkWell(
                onTap: () {
                  if (isFavourite) {
                    _showRemoveFavouriteDialog(context);
                  } else {
                    onFavouriteToggle?.call();
                  }
                },
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    isFavourite ? Icons.star : Icons.star_border,
                    color: isFavourite ? const Color(0xFFF6D207) : Colors.grey,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],

            // Phone Icon (Opens Center Action Dialog for WhatsApp or Call)
            InkWell(
              onTap: () => _showContactActionDialog(context),
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
