import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/contact.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../models/user_session.dart';
import '../widgets/app_header.dart';

class DetailsScreen extends StatefulWidget {
  final DirectoryContact contact;
  const DetailsScreen({super.key, required this.contact});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> with SingleTickerProviderStateMixin {
  final SessionStore _store = SessionStore();
  UserSession? _session;
  DirectoryContact? _fullContact;
  bool _isLoading = true;
  bool _isFav = false;
  int _favCount = 0;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _favCount = int.tryParse(widget.contact.favouriteCount) ?? 0;
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _load() async {
    _session = await _store.read();
    final favs = await _store.getFavourites();
    _isFav = _store.isContactFavourite(widget.contact, favs);

    try {
      final queryParams = <String, String>{
        if (widget.contact.id != null && widget.contact.id!.isNotEmpty) 'id': widget.contact.id!,
        'phone': widget.contact.phone,
      };
      final data = await ApiClient().get('check_search_type', queryParams);
      if (data != null && data is List && data.isNotEmpty) {
        final first = data[0];
        if (first is Map<String, dynamic> && !first.containsKey('error')) {
          if (mounted) {
            setState(() {
              _fullContact = DirectoryContact.fromJson(first);
              _favCount = int.tryParse(_fullContact!.favouriteCount) ?? 0;
              _isLoading = false;
            });
          }
          return;
        }
      }
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _call(String phone) {
    _store.addToHistory(_fullContact ?? widget.contact);
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleanPhone.isNotEmpty) {
      launchUrl(Uri.parse('tel:$cleanPhone'));
    }
  }

  void _showAddReviewSheet() {
    final c = _fullContact ?? widget.contact;
    final profileId = c.id;
    if (profileId == null || profileId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot submit review: Business Profile ID is missing.')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddReviewBottomSheet(
        contactId: profileId,
        contactPhone: c.phone,
        reviewerName: _session?.email?.split('@')[0] ?? 'Guest',
        reviewerPhone: _session?.phone ?? '',
        onSuccess: _load,
      ),
    );
  }

  void _showFullImage() {
    final c = _fullContact ?? widget.contact;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  child: c.imageUrl.isNotEmpty
                      ? FadeInImage.assetNetwork(
                          placeholder: 'assets/images/user.png',
                          image: c.imageUrl,
                          fit: BoxFit.contain,
                          imageErrorBuilder: (c, e, s) => Image.asset('assets/images/user.png', fit: BoxFit.contain),
                        )
                      : Image.asset('assets/images/user.png', fit: BoxFit.contain),
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _fullContact ?? widget.contact;
    final show = c.showContact.toLowerCase();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Fone Book',
              onBack: () => Navigator.pop(context),
              session: _session,
              store: _store,
              api: ApiClient(),
            ),
            if (_isLoading && _fullContact == null)
              const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFFD7B41A))))
            else
              Expanded(
                child: Column(
                  children: [
                    // Top Header Profile Card (Shows ONLY Name & Avatar & Favourite Star)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Avatar Image
                          GestureDetector(
                            onTap: _showFullImage,
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF4C5B8F),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: c.imageUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: c.imageUrl,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) => Image.asset('assets/images/user.png', fit: BoxFit.cover),
                                        errorWidget: (context, url, error) => Image.asset('assets/images/user.png', fit: BoxFit.cover),
                                      )
                                    : Image.asset('assets/images/user.png', fit: BoxFit.cover),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),

                          // ONLY Name
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    c.name,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF212529),
                                      fontFamily: 'Poppins',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (c.verified == 1)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Image.asset('assets/images/verified.png', width: 18, height: 18),
                                  ),
                              ],
                            ),
                          ),

                          // Top Right Favourite Star Icon
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () async {
                                  final String action = _isFav ? 'remove' : 'add';
                                  setState(() {
                                    _isFav = !_isFav;
                                    if (_isFav) { _favCount++; } else { if (_favCount > 0) _favCount--; }
                                  });
                                  try {
                                    await _store.toggleFavourite(c);
                                    await ApiClient().post('addfavourite', {
                                      if (c.id != null && c.id!.isNotEmpty) 'id': c.id!,
                                      'phone_no': c.phone,
                                      'count': action == 'add' ? "1" : "0",
                                    });
                                  } catch (e) {
                                    debugPrint("Favorite Sync Error: $e");
                                  }
                                },
                                borderRadius: BorderRadius.circular(20),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                    _isFav ? Icons.star : Icons.star_border,
                                    color: _isFav ? const Color(0xFFF6D207) : Colors.grey.shade500,
                                    size: 28,
                                  ),
                                ),
                              ),
                              Text(
                                _favCount.toString(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Poppins',
                                  color: Color(0xFF212529),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Tab Bar (About & Reviews)
                    Container(
                      color: Colors.white,
                      child: TabBar(
                        controller: _tabController,
                        indicatorColor: const Color(0xFFD7B41A),
                        indicatorWeight: 3,
                        labelColor: const Color(0xFFD7B41A),
                        unselectedLabelColor: Colors.grey,
                        labelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 15),
                        tabs: const [
                          Tab(text: 'About'),
                          Tab(text: 'Reviews'),
                        ],
                      ),
                    ),

                    // Tab Views
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildAboutTab(c, show),
                          _buildReviewsTab(c),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutTab(DirectoryContact c, String show) {
    final List<String> allSkills = [];
    if (c.additionalServices != null && c.additionalServices!.isNotEmpty && c.additionalServices != 'null') {
      for (var s in c.additionalServices!.split(',')) {
        final t = s.trim();
        if (t.isNotEmpty && !allSkills.any((e) => e.toLowerCase() == t.toLowerCase())) {
          allSkills.add(t);
        }
      }
    }
    if (c.keyword != null && c.keyword!.isNotEmpty && c.keyword != 'null') {
      for (var k in c.keyword!.split(',')) {
        final t = k.trim();
        if (t.isNotEmpty && !allSkills.any((e) => e.toLowerCase() == t.toLowerCase())) {
          allSkills.add(t);
        }
      }
    }
    final bool hasLocation = c.location1 != null && c.location1!.trim().isNotEmpty;
    final bool hasPhone = c.phone.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Profession Card (Label & Value)
          if (c.service.isNotEmpty) ...[
            _buildDetailCard(
              title: 'Profession',
              child: Text(
                c.service,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF212529),
                  fontFamily: 'Poppins',
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 2. About / Bio Card
          if (c.about != null && c.about!.trim().isNotEmpty && c.about != 'null') ...[
            _buildDetailCard(
              title: 'Bio',
              child: Text(
                c.about!.trim(),
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF212529),
                  fontFamily: 'Poppins',
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 2. Skills Card (Clean Chips Only)
          if (allSkills.isNotEmpty) ...[
            _buildDetailCard(
              title: 'Skills',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: allSkills.map((skill) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F3F5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE9ECEF)),
                  ),
                  child: Text(
                    skill,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontFamily: 'Poppins',
                      color: Color(0xFF343A40),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 3. Contact Number Card
          if (hasPhone) ...[
            _buildDetailCard(
              title: 'Contact Number',
              child: Row(
                children: [
                  const Icon(Icons.phone_outlined, size: 18, color: Color(0xFF495057)),
                  const SizedBox(width: 10),
                  Text(
                    c.phone,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF212529),
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 4. Address / Location Card
          if (hasLocation) ...[
            _buildDetailCard(
              title: 'Address',
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 18, color: Color(0xFF495057)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      c.location1!,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF212529),
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // 5. Action Buttons Bar (WhatsApp & Call)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // WhatsApp Button (Direct launch)
                Expanded(
                  child: InkWell(
                    onTap: () {
                      final wpNum = (c.whatsapp != null && c.whatsapp!.isNotEmpty && c.whatsapp != 'null')
                          ? c.whatsapp!
                          : c.phone;
                      final cleanPhone = wpNum.replaceAll(RegExp(r'[^0-9+]'), '');
                      if (cleanPhone.isNotEmpty) {
                        launchUrl(Uri.parse('https://wa.me/$cleanPhone'));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WhatsApp number not available')));
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset('assets/images/whatsapp.png', width: 26, height: 26),
                          const SizedBox(width: 8),
                          const Text(
                            'WhatsApp',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: Color(0xFF212529),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                Container(height: 28, width: 1, color: Colors.grey.shade300),

                // Call Button (Direct launch)
                Expanded(
                  child: InkWell(
                    onTap: () {
                      final cleanPhone = c.phone.replaceAll(RegExp(r'[^0-9+]'), '');
                      if (cleanPhone.isNotEmpty) {
                        _call(c.phone);
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.phone, color: Colors.black, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'Call',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: Color(0xFF212529),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDetailCard({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6C757D),
              fontFamily: 'Poppins',
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _buildReviewsTab(DirectoryContact c) {
    final reviews = c.reviews;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'User Reviews',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, fontFamily: 'Poppins', color: Color(0xFF212529)),
              ),
              ElevatedButton.icon(
                onPressed: _showAddReviewSheet,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Review', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD7B41A),
                  foregroundColor: const Color(0xFF272000),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: (reviews == null || reviews.isEmpty)
                ? const Center(
                    child: Text(
                      'No reviews yet',
                      style: TextStyle(fontFamily: 'Poppins', color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    itemCount: reviews.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final rawRev = reviews[index];
                      if (rawRev is! Map) return const SizedBox.shrink();
                      final rev = Map<String, dynamic>.from(rawRev);
                      final reviewerName = rev['reviewer_name']?.toString() ?? 'User';
                      final comment = rev['comment']?.toString() ?? '';
                      final rating = int.tryParse(rev['rating']?.toString() ?? '0') ?? 0;
                      final date = rev['created']?.toString().split('T')[0] ?? '';

                      return Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Color(0xFFD7B41A),
                                  child: Icon(Icons.person, color: Colors.white, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(reviewerName, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Poppins', color: Color(0xFF212529))),
                                      if (date.isNotEmpty)
                                        Text(date, style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Poppins')),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: List.generate(5, (starIdx) {
                                    return Icon(
                                      starIdx < rating ? Icons.star : Icons.star_border,
                                      color: const Color(0xFFF6D207),
                                      size: 16,
                                    );
                                  }),
                                ),
                              ],
                            ),
                            if (comment.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                comment,
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13.5, color: Color(0xFF495057), height: 1.4),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AddReviewBottomSheet extends StatefulWidget {
  final String contactId;
  final String contactPhone;
  final String reviewerName;
  final String reviewerPhone;
  final VoidCallback onSuccess;

  const _AddReviewBottomSheet({
    required this.contactId,
    required this.contactPhone,
    required this.reviewerName,
    required this.reviewerPhone,
    required this.onSuccess,
  });

  @override
  State<_AddReviewBottomSheet> createState() => _AddReviewBottomSheetState();
}

class _AddReviewBottomSheetState extends State<_AddReviewBottomSheet> {
  int _rating = 5;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _submitReview() async {
    final comment = _commentController.text.trim();
    if (comment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a review comment')));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final res = await ApiClient().post('save_review', {
        'contact_id': widget.contactId,
        'contact_phone': widget.contactPhone,
        'reviewer_name': widget.reviewerName,
        'reviewer_phone': widget.reviewerPhone,
        'rating': _rating.toString(),
        'comment': comment,
      });

      if (mounted) {
        bool isSuccess = false;
        if (res is Map) {
          if (res['status'] == 'success' || (res['message'] != null && res['message'].toString().toLowerCase().contains('success'))) {
            isSuccess = true;
          } else if (res['error'] != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'].toString())));
            return;
          }
        } else if (res.toString().toLowerCase().contains('success')) {
          isSuccess = true;
        }

        if (isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Review submitted successfully!'), backgroundColor: Colors.green),
          );
          widget.onSuccess();
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.toString())));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to submit review: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Write a Review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Poppins', color: Color(0xFF212529))),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              return IconButton(
                icon: Icon(
                  index < _rating ? Icons.star : Icons.star_border,
                  color: const Color(0xFFF6D207),
                  size: 32,
                ),
                onPressed: () => setState(() => _rating = index + 1),
              );
            }),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _commentController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Share your experience...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: const Color(0xFFF8F9FA),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitReview,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD7B41A),
                foregroundColor: const Color(0xFF272000),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Text('Submit Review', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
            ),
          ),
        ],
      ),
    );
  }
}
