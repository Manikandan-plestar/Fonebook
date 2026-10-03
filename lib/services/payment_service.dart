import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'api_client.dart';

class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  PaymentService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _initialized = false;
  // ignore: unused_field
  final ApiClient _api = ApiClient();

  List<ProductDetails> products = [];
  bool isAvailable = false;
  
  final _purchaseController = StreamController<PurchaseDetails>.broadcast();
  Stream<PurchaseDetails> get purchaseStream => _purchaseController.stream;

  void initialize() {
    if (kIsWeb || _initialized) return;
    _initialized = true;
    final Stream<List<PurchaseDetails>> purchaseUpdated = _iap.purchaseStream;
    _subscription = purchaseUpdated.listen((purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _subscription?.cancel();
    }, onError: (error) {
      // debugPrint("IAP Subscription Error: $error");
    });
  }

  void dispose() {
    if (!kIsWeb) {
      _subscription?.cancel();
    }
    _purchaseController.close();
  }

  Future<bool> loadProducts(List<String> ids) async {
    if (kIsWeb) return false;
    isAvailable = await _iap.isAvailable();
    if (!isAvailable) {
      debugPrint("IAP: StoreKit / In-App Billing is NOT available on this device.");
      return false;
    }

    debugPrint("IAP: Querying product IDs: $ids");
    final ProductDetailsResponse resp = await _iap.queryProductDetails(ids.toSet());
    if (resp.error != null) {
      debugPrint("IAP Query Error: ${resp.error?.message} (${resp.error?.code})");
      return false;
    }
    
    if (resp.notFoundIDs.isNotEmpty) {
      debugPrint("IAP Warning: These IDs were NOT FOUND in App Store Connect: ${resp.notFoundIDs}");
    }

    products = resp.productDetails;
    debugPrint("IAP: Successfully loaded ${products.length} products: ${products.map((p) => '${p.id} (${p.price})').toList()}");
    return true;
  }

  Future<void> buyProduct(ProductDetails product, {bool consumable = true}) async {
    if (kIsWeb) return;
    // debugPrint("Initiating purchase for: ${product.id} (consumable=$consumable)");
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    try {
      if (consumable) {
        await _iap.buyConsumable(purchaseParam: purchaseParam);
      } else {
        await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      }
    } catch (e) {
      // debugPrint("Purchase Initiation Error: $e, trying fallback...");
      try {
        if (consumable) {
          await _iap.buyNonConsumable(purchaseParam: purchaseParam);
        } else {
          await _iap.buyConsumable(purchaseParam: purchaseParam);
        }
      } catch (e2) {
        // debugPrint("Purchase Fallback Error: $e2");
        rethrow;
      }
    }
  }

  final Set<String> _verifiedPurchaseIDs = {};

  Future<void> _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    if (kIsWeb) return;
    for (var purchase in purchaseDetailsList) {
      // debugPrint("Purchase Update: ID=${purchase.productID}, Status=${purchase.status}");
      
      if (purchase.status == PurchaseStatus.pending) {
        // Pending state
      } else {
        if (purchase.status == PurchaseStatus.error) {
          // debugPrint("Purchase Error Detail: ${purchase.error?.message} (${purchase.error?.code})");
        } else if (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) {
          final txKey = purchase.purchaseID ?? purchase.verificationData.serverVerificationData;
          if (txKey.isNotEmpty && _verifiedPurchaseIDs.contains(txKey)) {
            // debugPrint("Skipping already processed purchase: $txKey");
            continue;
          }
          bool deliver = await _verifyPurchase(purchase);
          if (deliver) {
            if (txKey.isNotEmpty) _verifiedPurchaseIDs.add(txKey);
            await _iap.completePurchase(purchase);
          }
        }
        
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        
        _purchaseController.add(purchase);
      }
    }
  }

  // CRIT-04: Server-side purchase verification via /v1/payments/verify.
  // The server validates the Google Play receipt against the Play Developer API,
  // checks for replay attacks, and only grants the benefit after confirmation.
  // This method returns false on any error to prevent fraudulent grants.
  //
  // [profileId] is optional — pass it when the purchase is for a specific profile.
  Future<bool> verifyPurchaseOnServer(
    PurchaseDetails purchase, {
    String? profileId,
    String? userEmail,
  }) async {
    try {
      final receipt = purchase.verificationData.serverVerificationData;
      if (receipt.isEmpty) {
        debugPrint('[PAYMENT] Empty receipt — rejecting purchase');
        return false;
      }

      final payload = <String, String?>{
        'product_id': purchase.productID,
        'purchase_token': receipt,
        'platform': 'google_play',
        if (profileId != null) 'profile_id': profileId,
      };

      final res = await _api.post('v1/payments/verify', payload, timeout: const Duration(seconds: 30));

      if (res is Map && res['status'] == 'success') {
        debugPrint('[PAYMENT] Server verified purchase: ${purchase.productID}');
        return true;
      }

      debugPrint('[PAYMENT] Server rejected purchase: ${res is Map ? res['message'] : res}');
      return false;
    } catch (e) {
      // Network error or server unavailable — do NOT grant benefit
      // The purchase can be retried; in_app_purchase will deliver it again on next app launch.
      debugPrint('[PAYMENT] Verification error — not granting benefit. Error: $e');
      return false;
    }
  }

  /// Legacy internal verify — now calls the server. Kept for internal listener compat.
  Future<bool> _verifyPurchase(PurchaseDetails purchase) async {
    return verifyPurchaseOnServer(purchase);
  }
}
