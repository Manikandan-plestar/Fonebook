import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
    _tabController = TabController(length: 4, vsync: this);
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
    _isFav = favs.any((e) => e.phone == widget.contact.phone);

    try {
      final data = await ApiClient().get('check_search_type', {'phone': widget.contact.phone});
      if (data != null && data is List && data.isNotEmpty) {
        setState(() {
          _fullContact = DirectoryContact.fromJson(data[0]);
          _favCount = int.tryParse(_fullContact!.favouriteCount) ?? 0;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _call(String phone) {
    _store.addToHistory(_fullContact ?? widget.contact);
    launchUrl(Uri.parse('tel:$phone'));
  }

  void _showAddReviewSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddReviewBottomSheet(
        contactPhone: (widget.contact.phone),
        reviewerName: _session?.email?.split('@')[0] ?? 'Guest',
        reviewerPhone: _session?.phone ?? '',
        onSuccess: _load, // Refresh data after post
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
      backgroundColor: const Color(0xFFF5F5F5),
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
                    // Hero Image
                    GestureDetector(
                      onTap: _showFullImage,
                      child: Container(
                        width: double.infinity,
                        height: 250,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                        ),
                        child: c.imageUrl.isNotEmpty
                            ? FadeInImage.assetNetwork(
                                placeholder: 'assets/images/user.png',
                                image: c.imageUrl,
                                fit: BoxFit.cover,
                                imageErrorBuilder: (c, e, s) => Image.asset('assets/images/user.png', fit: BoxFit.cover),
                              )
                            : Image.asset('assets/images/user.png', fit: BoxFit.cover),
                      ),
                    ),

                    // Tab Bar
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
                          Tab(text: 'Services'),
                          Tab(text: 'Reviews'),
                          Tab(text: 'Location'),
                        ],
                      ),
                    ),

                    // Tab Bar View
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildAboutTab(c, show),
                          _buildServicesTab(c),
                          _buildReviewsTab(c),
                          _buildLocationTab(c, show),
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
    final bool hasAbout = c.about != null && c.about!.isNotEmpty && c.about != 'null';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Action Icons Row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _DetailAction(
                  icon: 'assets/images/gmail.png', 
                  onTap: () {
                    if (show.contains('e') && c.email != null && c.email!.isNotEmpty && c.email != 'null') {
                      launchUrl(Uri.parse('mailto:${c.email}'));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email is off')));
                    }
                  },
                ),
                _DetailAction(
                  icon: 'assets/images/skype.png', 
                  onTap: () {
                    if (show.contains('s') && c.skype != null && c.skype!.isNotEmpty && c.skype != 'null') {
                      launchUrl(Uri.parse('skype:${c.skype}?call'));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Skype is off')));
                    }
                  },
                ),
                _DetailAction(
                  icon: 'assets/images/whatsapp.png', 
                  onTap: () {
                    if (show.contains('w')) {
                      launchUrl(Uri.parse('https://wa.me/${c.phone}'));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Whatsapp is off')));
                    }
                  },
                ),
                _DetailAction(
                  icon: 'assets/images/phone.png', 
                  width: 28,
                  onTap: () {
                    if (show.contains('m')) {
                      _call(c.phone);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone is off')));
                    }
                  },
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DetailAction(
                      icon: _isFav ? 'assets/images/favourite1.png' : 'assets/images/star.png',
                      width: 28,
                      rightMargin: 0,
                      onTap: () async {
                        final String action = _isFav ? 'remove' : 'add';
                        setState(() {
                          _isFav = !_isFav;
                          if (_isFav) { _favCount++; } else { if (_favCount > 0) _favCount--; }
                        });
                        try {
                          await _store.toggleFavourite(c);
                          await ApiClient().post('addfavourite', {
                            'phone_no': c.phone,
                            'count': action == 'add' ? "1" : "0",
                          });
                        } catch (e) { debugPrint("Favorite Sync Error: $e"); }
                      },
                    ),
                    Text(_favCount.toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
                  ],
                ),
              ],
            ),
          ),
          /*const SizedBox(height: 25),

          // Details List
          _buildInfoSection('Profile Details', [
            _InfoItem(label: 'Phone', value: show.contains('m') ? (c.phone.length > 6 ? "${c.phone.substring(0, c.phone.length - 6)}XXXXXX" : c.phone) : 'Hidden', onTap: () {
              if (show.contains('m')) _call(c.phone);
              else ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone is off')));
            }),
          ]),*/

          if (hasAbout) ...[
            const SizedBox(height: 25),
            const Padding(
              padding: EdgeInsets.only(left: 5, bottom: 10),
              child: Text('About Bio', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey, fontFamily: 'Poppins')),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 5))],
              ),
              child: Text(
                c.about!,
                style: const TextStyle(fontSize: 15, color: Color(0xFF272000), fontFamily: 'Poppins', height: 1.5),
              ),
            ),
          ],
          
          if (c.additionalPhones != null && c.additionalPhones!.isNotEmpty && c.additionalPhones != 'null') ...[
             const SizedBox(height: 25),
             _buildInfoSection('Additional Contacts', 
               c.additionalPhones!.split(', ').where((s) => s.contains(':')).map((s) {
                final parts = s.split(':');
                final label = parts[0].trim();
                final value = parts[1].trim();
                final bool isEmail = value.contains('@');
                return _InfoItem(
                  label: label, 
                  value: !isEmail ? (value.length > 6 ? "${value.substring(0, value.length - 6)}XXXXXX" : value) : value,
                  onTap: () {
                    if (isEmail) {
                      if (show.contains('e')) launchUrl(Uri.parse('mailto:$value'));
                      else ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email is off')));
                    } else {
                      if (show.contains('m')) _call(value);
                      else ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone is off')));
                    }
                  },
                );
              }).toList()
             ),
          ],
        ],
      ),
    );
  }

  Widget _buildServicesTab(DirectoryContact c) {
    final bool hasServices = c.additionalServices != null && c.additionalServices!.isNotEmpty && c.additionalServices != 'null';
    final bool hasKeywords = c.keyword != null && c.keyword!.isNotEmpty && c.keyword != 'null';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasServices) ...[
            const Padding(
              padding: EdgeInsets.only(left: 5, bottom: 10),
              child: Text('Skills & Services', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey, fontFamily: 'Poppins')),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 5))],
              ),
              child: Column(
                children: c.additionalServices!.split(',').map((service) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle, size: 18, color: Color(0xFFD7B41A)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            service.trim(),
                            style: const TextStyle(fontSize: 15, color: Color(0xFF272000), fontFamily: 'Poppins', height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          if (hasKeywords) ...[
            const SizedBox(height: 25),
            const Padding(
              padding: EdgeInsets.only(left: 5, bottom: 10),
              child: Text('Keywords', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey, fontFamily: 'Poppins')),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 5))],
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: c.keyword!.split(',').map((k) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(k.trim(), style: const TextStyle(fontSize: 13, fontFamily: 'Poppins', color: Color(0xFF272000))),
                )).toList(),
              ),
            ),
          ],
          
          if (!hasServices && !hasKeywords)
            const Center(child: Padding(
              padding: EdgeInsets.only(top: 50),
              child: Text('No Skills or Services listed', style: TextStyle(fontFamily: 'Poppins', color: Colors.grey)),
            )),
        ],
      ),
    );
  }

  Widget _buildReviewsTab(DirectoryContact c) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('User Reviews', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
              ElevatedButton.icon(
                onPressed: _showAddReviewSheet,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Review', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD7B41A),
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: (c.reviews == null || c.reviews!.isEmpty)
                ? const Center(
                    child: Text(
                      'No reviews yet. Be the first to review!',
                      style: TextStyle(fontFamily: 'Poppins', color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    itemCount: c.reviews!.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 15),
                    itemBuilder: (context, index) {
                      final rev = c.reviews![index];
                      final reviewerName = rev['reviewer_name']?.toString() ?? 'User';
                      final comment = rev['comment']?.toString() ?? '';
                      final rating = int.tryParse(rev['rating']?.toString() ?? '0') ?? 0;
                      final date = rev['created']?.toString().split('T')[0] ?? '';

                      return Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 5))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const CircleAvatar(backgroundColor: Color(0xFFD7B41A), child: Icon(Icons.person, color: Colors.white)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(reviewerName, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
                                      Text(date, style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Poppins')),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: List.generate(
                                      5,
                                      (i) => Icon(
                                            Icons.star,
                                            color: i < rating ? const Color(0xFFD7B41A) : Colors.grey[300],
                                            size: 16,
                                          )),
                                ),
                              ],
                            ),
                            if (comment.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                comment,
                                style: const TextStyle(fontFamily: 'Poppins', color: Colors.black87),
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

  Widget _buildLocationTab(DirectoryContact c, String show) {
    final address = show.contains('f') ? c.location : c.location1;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Full Location', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
          const SizedBox(height: 20),
          InkWell(
            onTap: () {
              if (address != null) {
                launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1\u0026query=${Uri.encodeComponent(address)}'));
              }
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 8))],
                border: Border.all(color: const Color(0xFFD7B41A).withOpacity(0.2), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.location_on, color: Color(0xFFD7B41A), size: 30),
                      SizedBox(width: 10),
                      Text('Click to view on Map', style: TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Poppins')),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Text(
                    address ?? 'No address provided',
                    style: const TextStyle(fontSize: 18, fontFamily: 'Poppins', height: 1.5, color: Color(0xFF272000)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, List<_InfoItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 5, bottom: 10),
          child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey, fontFamily: 'Poppins')),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 5))],
          ),
          child: Column(
            children: items.asMap().entries.map((e) {
              final bool isLast = e.key == items.length - 1;
              return Column(
                children: [
                  _buildDetailRow(e.value),
                  if (!isLast) const Divider(height: 1, color: Color(0xFFF0F0F0), indent: 20, endIndent: 20),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(_InfoItem item) {
    final bool hideLabel = item.label.isEmpty;
    return InkWell(
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        child: Row(
          crossAxisAlignment: item.isLongText ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            if (!hideLabel)
              SizedBox(
                width: 100,
                child: Text(item.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF5A5A5A), fontFamily: 'Poppins')),
              ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.value ?? '-',
                      style: TextStyle(
                        fontSize: 16, 
                        color: const Color(0xFF272000), 
                        fontFamily: 'Poppins', 
                        fontWeight: hideLabel ? FontWeight.normal : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (item.isVerified)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Image.asset('assets/images/verified.png', width: 18, height: 18),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoItem {
  final String label;
  final String? value;
  final bool isVerified;
  final bool isLongText;
  final VoidCallback? onTap;
  _InfoItem({required this.label, this.value, this.isVerified = false, this.isLongText = false, this.onTap});
}

class _DetailAction extends StatelessWidget {
  final String icon;
  final VoidCallback onTap;
  final double width;
  final double height;
  final double rightMargin;
  const _DetailAction({required this.icon, required this.onTap, this.width = 25, this.height = 30, this.rightMargin = 15});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(right: rightMargin),
      child: InkWell(
        onTap: onTap,
        child: Image.asset(icon, width: width, height: height),
      ),
    );
  }
}

class _AddReviewBottomSheet extends StatefulWidget {
  final String contactPhone;
  final String reviewerName;
  final String reviewerPhone;
  final VoidCallback onSuccess;

  const _AddReviewBottomSheet({
    required this.contactPhone,
    required this.reviewerName,
    required this.reviewerPhone,
    required this.onSuccess,
  });

  @override
  State<_AddReviewBottomSheet> createState() => _AddReviewBottomSheetState();
}

class _AddReviewBottomSheetState extends State<_AddReviewBottomSheet> {
  int _rating = 0;
  final _commentController = TextEditingController();
  bool _isPosting = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.only(
        left: 25,
        right: 25,
        top: 25,
        bottom: MediaQuery.of(context).viewInsets.bottom + 25,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 25),
          const Text(
            'Write a Review',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              fontFamily: 'Poppins',
              color: Color(0xFF272000),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'How was your experience? Rate and share your thoughts.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 25),
          
          // Star Rating
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (index) {
                return IconButton(
                  onPressed: () => setState(() => _rating = index + 1),
                  icon: Icon(
                    index < _rating ? Icons.star : Icons.star_border,
                    size: 40,
                    color: const Color(0xFFD7B41A),
                  ),
                );
              }),
            ),
          ),
          
          const SizedBox(height: 25),
          
          TextField(
            controller: _commentController,
            maxLines: 4,
            style: const TextStyle(fontFamily: 'Poppins'),
            decoration: InputDecoration(
              hintText: 'Share your experience...',
              hintStyle: const TextStyle(color: Colors.grey, fontFamily: 'Poppins'),
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(15),
            ),
          ),
          
          const SizedBox(height: 30),
          
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: _isPosting ? null : _submitReview,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD7B41A),
                foregroundColor: Colors.black,
                elevation: 5,
                shadowColor: const Color(0xFFD7B41A).withOpacity(0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: _isPosting 
                ? const SizedBox(width: 25, height: 25, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                : const Text(
                'Post Review',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitReview() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a rating')));
      return;
    }

    setState(() => _isPosting = true);

    try {
      final res = await ApiClient().post('save_review', {
        'contact_phone': widget.contactPhone,
        'reviewer_name': widget.reviewerName,
        'reviewer_phone': widget.reviewerPhone,
        'rating': _rating.toString(),
        'comment': _commentController.text.trim(),
      });

      if (res.toString().toLowerCase().contains('success')) {
        widget.onSuccess();
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Review posted successfully!'), backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.toString())));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }
}
