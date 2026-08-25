import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../models/user_session.dart';
import '../widgets/app_header.dart';

class KeywordScreen extends StatefulWidget {
  final ApiClient api;
  final String phone;
  final String name;
  final String service;
  final String category;
  final String initial;
  final int verified;

  const KeywordScreen({
    super.key, 
    required this.api, 
    required this.phone, 
    required this.name,
    required this.service,
    required this.category,
    required this.initial, 
    this.verified = 0,
  });

  @override
  State<KeywordScreen> createState() => _KeywordScreenState();
}

class _KeywordScreenState extends State<KeywordScreen> {
  final _tagController = TextEditingController();
  List<String> _tags = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial.isNotEmpty) {
      final all = widget.initial.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      
      final Set<String> filtered = {};
      final lowerService = widget.service.toLowerCase();

      for (var tag in all) {
        final lowerTag = tag.toLowerCase();
        
        // Skip auto-generated location variants (e.g. "Service in City", "Service at State")
        if (lowerTag.contains("$lowerService in ") || 
            lowerTag.contains("$lowerService at ") ||
            (lowerTag.startsWith(lowerService) && lowerTag.length > lowerService.length + 1)) {
          continue;
        }
        
        // Add to set to prevent duplicates
        filtered.add(tag);
      }
      
      // Ensure the base service is present if not already
      if (widget.service.isNotEmpty && !filtered.any((t) => t.toLowerCase() == lowerService)) {
        _tags = [widget.service, ...filtered.toList()];
      } else {
        _tags = filtered.toList();
      }
    } else if (widget.service.isNotEmpty) {
      _tags = [widget.service];
    }
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isNotEmpty) {
      if (widget.verified != 1) {
        if (_tags.length >= 6) { // 1 Service + 5 Tags = 6 total
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only 5 Keywords allowed for Free users')));
          _tagController.clear();
          return;
        }
      }
      setState(() {
        if (!_tags.any((t) => t.toLowerCase() == tag.toLowerCase())) {
          _tags.add(tag);
        }
        _tagController.clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
  }

  Future<void> _save() async {
    final tagsString = _tags.join(', ');
    
    setState(() => _saving = true);
    try {
      await widget.api.post('savetags', {'tags': tagsString, 'phone': widget.phone});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Keywrods updated successfully'), backgroundColor: Colors.green));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Keywords',
              onBack: () => Navigator.pop(context),
              showMenu: true,
              api: widget.api,
              store: SessionStore(),
              session: UserSession(phone: widget.phone),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE9ECEF), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C757D),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.tag, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.name, 
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18, 
                                    fontWeight: FontWeight.bold, 
                                    color: Color(0xFF212529), 
                                    fontFamily: 'Poppins'
                                  ),
                                ),
                                if (widget.service.isNotEmpty)
                                  Text(
                                    widget.service,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF6C757D), fontFamily: 'Poppins'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _tagController,
                            onSubmitted: (_) => _addTag(),
                            textInputAction: TextInputAction.done,
                            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: 15),
                            decoration: InputDecoration(
                              hintText: 'Add Keyword Tag...',
                              hintStyle: const TextStyle(color: Color(0xFF6C757D), fontFamily: 'Poppins'),
                              filled: true,
                              fillColor: const Color(0xFFF1F3F4),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        InkWell(
                          onTap: _addTag,
                          borderRadius: BorderRadius.circular(12),
                          child: const Text('+ Add', style: TextStyle(
                            fontSize: 15, 
                            fontWeight: FontWeight.bold, 
                            color: Color(0xFF6C757D),
                            fontFamily: 'Poppins',
                          )),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 20),
                    
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _tags.map((tag) => _buildChip(tag)).toList(),
                    ),
                    
                    const SizedBox(height: 35),
                    
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C757D),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _saving 
                          ? const CircularProgressIndicator(color: Colors.white) 
                          : const Text('Update Keywords', 
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Poppins', color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF6C757D),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => _removeTag(text),
            child: const Icon(Icons.close, size: 16, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
