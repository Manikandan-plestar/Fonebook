import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../models/user_session.dart';
import '../widgets/app_header.dart';

class ReportsScreen extends StatefulWidget {
  final ApiClient api;
  final String phone;
  final String tags;
  final String type; // 'organic' or 'paid'
  const ReportsScreen({super.key, required this.api, required this.phone, required this.tags, this.type = 'paid'});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _range = 'All';
  List _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final endpoint = widget.type == 'paid' ? 'check-search3' : 'check-search2';
      final callType = widget.type == 'paid' ? 'paid' : 'normal';

      final data = await widget.api.get(endpoint, {
        'tags': widget.tags,
        'type': _range,
        'phone': widget.phone,
        'call_type': callType,
      });
      
      List list = data as List;
      
      // Secondary check like native app's getNoSearch
      try {
        final noSearchData = await widget.api.get('check-call-count1', {
          'type': _range,
          'phone': widget.phone,
          'call_type': callType,
        });
        if (noSearchData is List) {
          for (var item in noSearchData) {
            if (!list.any((e) => e['tags'] == item['tag'] || (e['tags'] == '' && item['tag'] == ''))) {
               list.add({
                 'tags': item['tag'] ?? '',
                 'call_count': item['call_count'] ?? '0',
                 'search_count': '0',
               });
            }
          }
        }
      } catch(_) {}

      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPaid = widget.type == 'paid';
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Fone Book',
              onBack: () => Navigator.pop(context),
              showMenu: true,
              api: widget.api,
              store: SessionStore(),
              session: UserSession(phone: widget.phone),
            ),
            
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE9ECEF)),
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
                  Expanded(
                    child: Text(
                      isPaid ? 'Paid Traffic Reports' : 'Organic Traffic Reports',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF212529), fontFamily: 'Poppins'),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C757D),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _range,
                        isDense: true,
                        dropdownColor: const Color(0xFF6C757D),
                        iconEnabledColor: Colors.white,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Poppins'),
                        items: ['All', 'Today', 'Yesterday', 'Last 7 days', 'Last Week', 'Last Month']
                            .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(color: Colors.white)))).toList(),
                        onChanged: (v) {
                          setState(() {
                            _range = v!;
                            _load();
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Row(
                children: [
                  const Expanded(
                    flex: 3,
                    child: Text('Search Keywords', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF495057), fontFamily: 'Poppins')),
                  ),
                  SizedBox(
                    width: 60,
                    child: _buildHeaderIcon('assets/images/research.png', label: 'Research'),
                  ),
                  const SizedBox(width: 5),
                  SizedBox(
                    width: 60,
                    child: _buildHeaderIcon('assets/images/phone.png', label: 'Inbound'),
                  ),
                  if (isPaid) ...[
                    const SizedBox(width: 5),
                    const SizedBox(
                      width: 70,
                      child: Text('Amount', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF495057), fontFamily: 'Poppins')),
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 6),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFD7B41A)))
                  : _rows.isEmpty
                      ? const Center(child: Text('No Traffic Reports', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF6C757D), fontFamily: 'Poppins')))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _rows.length,
                          itemBuilder: (c, i) {
                            final r = _rows[i];
                            final callCountStr = r['call_count']?.toString() ?? '0';
                            final callCount = int.tryParse(callCountStr) ?? 0;
                            final amount = (callCount * 0.30).toStringAsFixed(2);
                            return _buildReportItem(
                              r['tags'] ?? '',
                              r['search_count']?.toString() ?? '0',
                              callCountStr,
                              isPaid ? amount : null,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderIcon(String asset, {String? label}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(asset, width: 18, height: 18),
        Text(label ?? '', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF6C757D), fontFamily: 'Poppins')),
      ],
    );
  }

  Widget _buildReportItem(String tag, String searchCount, String callCount, String? amount) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9ECEF)),
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
          Expanded(
            flex: 3,
            child: Text(
              tag.isNotEmpty ? tag : 'General Search', 
              maxLines: 1, 
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF212529), fontFamily: 'Poppins')
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(searchCount, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF495057), fontFamily: 'Poppins')),
          ),
          const SizedBox(width: 5),
          SizedBox(
            width: 60,
            child: Text(callCount, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF495057), fontFamily: 'Poppins')),
          ),
          if (amount != null) ...[
            const SizedBox(width: 5),
            SizedBox(
              width: 70,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '\$$amount', 
                  textAlign: TextAlign.center, 
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF856404), fontFamily: 'Poppins'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
