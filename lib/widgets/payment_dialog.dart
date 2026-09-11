import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../services/payment_service.dart';

class PaymentDialog extends StatefulWidget {
  const PaymentDialog({super.key});

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  final _payment = PaymentService();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initProducts();
  }

  Future<void> _initProducts() async {
    await _payment.loadProducts(['promote_1', 'promote_2', 'promote_3', 'promote_4']);
    if (mounted) setState(() => _loading = false);
  }

  String _cleanTitle(String title) {
    // Google Play titles often include "(package_name (unreviewed))"
    // We want to strip everything after the first parenthesis if it looks like noise
    if (title.contains('(')) {
      return title.split('(')[0].trim();
    }
    return title;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Add Balance',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF212529),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Select a credit amount to add to your promotion balance.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: Color(0xFF5A5A5A),
              ),
            ),
            const SizedBox(height: 20),
            if (_loading)
              const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
            else if (!_payment.isAvailable)
              const Text(
                'In-App Purchase is not available on this device.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Poppins', color: Colors.red),
              )
            else if (_payment.products.isEmpty)
              const Text(
                'No promotion packages found. Please check your connection or try again later.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Poppins', color: Color(0xFF212529)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _payment.products.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final p = _payment.products[index];
                    return _buildProductCard(p);
                  },
                ),
              ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Color(0xFF6C757D),
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(ProductDetails p) {
    return InkWell(
      onTap: () {
        _payment.buyProduct(p);
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF4C5B8F).withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 5,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _cleanTitle(p.title),
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF212529),
                    ),
                  ),
                  Text(
                    p.description,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Color(0xFF5A5A5A),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              p.price,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF4C5B8F),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
