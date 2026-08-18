import 'dart:async';
import 'package:flutter/material.dart';
import 'package:country_state_city/country_state_city.dart' as csc;
import '../services/api_client.dart';
import '../models/user_session.dart';
import '../models/contact.dart';
import '../widgets/app_header.dart';
import '../widgets/form_widgets.dart';
import '../services/location_service.dart';
import '../services/payment_service.dart';
import '../widgets/payment_dialog.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class PromoteScreen extends StatefulWidget {
  final UserSession session;
  final DirectoryContact contact;
  const PromoteScreen({super.key, required this.session, required this.contact});
  @override
  State<PromoteScreen> createState() => _PromoteScreenState();
}

class _PromoteScreenState extends State<PromoteScreen> {
  final _api = ApiClient();
  bool _isPromoting = false;
  bool _isInternational = false;
  String _searchType = 'broad';
  String _balance = '0.00';
  
  String _selectedCountry = 'All';
  String _selectedState = 'All';
  String _selectedCity = 'All';
  
  String? _countryCode;
  String? _stateCode;
  
  final Set<String> _processedPurchaseIDs = {};
  late StreamSubscription<PurchaseDetails> _purchaseSub;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    
    _purchaseSub = PaymentService().purchaseStream.listen((purchase) async {
      if (purchase.status == PurchaseStatus.purchased) {
        final txId = purchase.purchaseID ?? '${purchase.productID}_${DateTime.now().millisecondsSinceEpoch}';
        if (_processedPurchaseIDs.contains(txId)) return;
        _processedPurchaseIDs.add(txId);

        double creditAmount = 100.0;
        if (purchase.productID == 'promote_2') creditAmount = 250.0;
        if (purchase.productID == 'promote_3') creditAmount = 500.0;
        if (purchase.productID == 'promote_4') creditAmount = 1000.0;

        final currentBal = double.tryParse(_balance) ?? 0.0;
        final newBal = currentBal + creditAmount;
        final newBalStr = newBal.toStringAsFixed(2);

        await _api.post('savepriority', {
          'phone': widget.contact.phone,
          'priority_amount': newBalStr,
          'priority': '0',
        });

        if (mounted) {
          setState(() {
            _balance = newBalStr;
            _isPromoting = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment Successful! Added ₹${creditAmount.toStringAsFixed(2)} to ${widget.contact.name}\'s Promotion Balance.'),
              backgroundColor: Colors.green,
            ),
          );
          _loadStatus();
        }
      } else if (purchase.status == PurchaseStatus.error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Payment Failed: ${purchase.error?.message ?? 'Unknown error'}')),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _purchaseSub.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      // ALWAYS identify balance strictly by widget.contact.phone (unique profile identifier)
      final balRes = await _api.get('check-priority', {'phone': widget.contact.phone});
      
      String foundBal = '0.00';
      if (balRes is List && balRes.isNotEmpty) {
        foundBal = balRes[0]['priority_balance']?.toString() ?? '0.00';
        final data = balRes[0];
        final currentBal = double.tryParse(foundBal) ?? 0.0;
        final dbPriority = data['priority']?.toString() ?? '1';

        bool isProm = dbPriority == '0';
        if (currentBal > 0 && dbPriority == '1') {
          isProm = true;
          await _api.post('savepriority', {
            'phone': widget.contact.phone,
            'priority_amount': foundBal,
            'priority': '0',
          });
        } else if (currentBal <= 0 && dbPriority == '0') {
          isProm = false;
          await _api.post('savepriority', {
            'phone': widget.contact.phone,
            'priority_amount': '0.00',
            'priority': '1',
          });
        }

        if (mounted) {
          setState(() {
            _balance = foundBal;
            _isPromoting = isProm; 
            _isInternational = data['promote_international'] == 'yes';
            _searchType = data['search_type'] ?? 'broad';
            _selectedCountry = data['promote_country'] ?? 'All';
            _selectedState = data['promote_state'] ?? 'All';
            _selectedCity = data['promote_city'] ?? 'All';
          });
        }
      }
    } catch (e) {
      debugPrint("Load status error: $e");
    }
  }

  Future<void> _updatePriority(bool value) async {
    final currentBal = double.tryParse(_balance) ?? 0.0;
    if (value && currentBal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Promotion Balance is ₹0.00. Please add balance to enable promotion.")),
      );
      setState(() => _isPromoting = false);
      showDialog(
        context: context,
        builder: (c) => const PaymentDialog(),
      );
      return;
    }
    setState(() => _isPromoting = value);
    final messenger = ScaffoldMessenger.of(context);
    await _api.post('savepriority', {
      'phone': widget.contact.phone,
      'priority_amount': _balance,
      'priority': value ? '0' : '1',
    });
    if (mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(value ? 'Promotion Enabled! Profile is now Sponsored.' : 'Promotion Disabled.'),
          backgroundColor: value ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _updateSearchType(String type) async {
    setState(() => _searchType = type);
    await _api.post('save_search_type1', {
      'phone': widget.contact.phone,
      'type': type,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully'), backgroundColor: Colors.green, duration: Duration(seconds: 1)));
    }
  }

  Future<void> _savePromote() async {
    await _api.post('savepromote', {
      'phone': widget.contact.phone,
      'international': _isInternational ? 'yes' : 'no',
      'country': _selectedCountry,
      'state': _selectedState,
      'city': _selectedCity,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully'), backgroundColor: Colors.green, duration: Duration(seconds: 1)));
    }
  }

  String _formatBalance(String val) {
    double d = double.tryParse(val) ?? 0.0;
    if (d < 1000) return d.toStringAsFixed(2);
    if (d < 1000000) return "${(d / 1000).toStringAsFixed(2)}K";
    return "${(d / 1000000).toStringAsFixed(2)}M";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Fone Book',
              onBack: () => Navigator.pop(context),
              showMenu: false,
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
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C757D),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.campaign, color: Colors.white, size: 26),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.contact.name, 
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF212529), fontFamily: 'Poppins'),
                                ),
                                Text(
                                  widget.contact.phone, 
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF6C757D), fontFamily: 'Poppins'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C757D),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.account_balance_wallet, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              const Text('Balance for Promotion', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white, fontFamily: 'Poppins')),
                              const Spacer(),
                              Text('₹ ${_formatBalance(_balance)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Poppins')),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: InkWell(
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (c) => const PaymentDialog(),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD7B41A),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  '+ Add Amount', 
                                  style: TextStyle(color: Color(0xFF212529), fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Poppins'),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE9ECEF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSwitchRow('Enable Promotion', _isPromoting, _updatePriority, isMain: true),
                          const Divider(height: 24),
                          const Text('Search Keyword Match Type', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF212529), fontFamily: 'Poppins')),
                          const SizedBox(height: 6),
                          _buildSwitchRow('Broad (Default)', _searchType == 'broad', (v) {
                            if (v) _updateSearchType('broad');
                          }),
                          _buildSwitchRow('Phrase', _searchType == 'phrase', (v) {
                            if (v) _updateSearchType('phrase');
                          }),
                          _buildSwitchRow('Exact', _searchType == 'exact', (v) {
                            if (v) _updateSearchType('exact');
                          }),
                        ],
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

  Widget _buildSwitchRow(String label, bool value, ValueChanged<bool> onChanged, {bool isMain = false}) {
    return Padding(
      padding: EdgeInsets.only(left: isMain ? 0 : 20, top: 5, bottom: 5),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: isMain ? 17 : 16, color: Colors.black, fontFamily: 'Poppins')),
          const Spacer(),
          Transform.scale(
            scale: 1.1,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFFD7B41A),
              activeTrackColor: const Color(0xFFD7B41A).withOpacity(0.3),
              inactiveThumbColor: const Color(0xFF808080),
              inactiveTrackColor: const Color(0xFFE6E6E6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow(String label, String value, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 12, bottom: 12),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 16, color: Colors.black, fontFamily: 'Poppins')),
          const Spacer(),
          InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.only(bottom: 2),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.black26, width: 1)),
              ),
              child: Text(
                value,
                style: const TextStyle(fontSize: 16, color: Colors.black, fontFamily: 'Poppins'),
              ),
            ),
          ),
          const SizedBox(width: 5),
        ],
      ),
    );
  }
}
