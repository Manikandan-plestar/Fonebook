import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'api_client.dart';

class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  PaymentService._internal();

  late final InAppPurchase _iap;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  // ignore: unused_field
  final ApiClient _api = ApiClient();

  List<ProductDetails> products = [];
  bool isAvailable = false;
  
  final _purchaseController = StreamController<PurchaseDetails>.broadcast();
  Stream<PurchaseDetails> get purchaseStream => _purchaseController.stream;

  void initialize() {
    if (kIsWeb) return;
    _iap = InAppPurchase.instance;
    final Stream<List<PurchaseDetails>> purchaseUpdated = _iap.purchaseStream;
    _subscription = purchaseUpdated.listen((purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _subscription.cancel();
    }, onError: (error) {
      debugPrint("IAP Subscription Error: $error");
    });
  }

  void dispose() {
    if (!kIsWeb) {
      _subscription.cancel();
    }
    _purchaseController.close();
  }

  Future<bool> loadProducts(List<String> ids) async {
    if (kIsWeb) return false;
    isAvailable = await _iap.isAvailable();
    if (!isAvailable) {
      debugPrint("Google Play Billing not available on this device.");
      return false;
    }

    debugPrint("Loading products: $ids");
    final ProductDetailsResponse resp = await _iap.queryProductDetails(ids.toSet());
    if (resp.error != null) {
      debugPrint("IAP Query Error: ${resp.error?.message} (${resp.error?.code})");
      return false;
    }
    
    if (resp.notFoundIDs.isNotEmpty) {
      debugPrint("Warning: Some IDs were not found in Play Console: ${resp.notFoundIDs}");
    }

    products = resp.productDetails;
    debugPrint("Found ${products.length} products available.");
    return true;
  }

  Future<void> buyProduct(ProductDetails product) async {
    if (kIsWeb) return;
    debugPrint("Initiating purchase for: ${product.id}");
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    try {
      await _iap.buyConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      debugPrint("Purchase Initiation Error: $e");
    }
  }

  Future<void> _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    if (kIsWeb) return;
    for (var purchase in purchaseDetailsList) {
      debugPrint("Purchase Update: ID=${purchase.productID}, Status=${purchase.status}");
      
      if (purchase.status == PurchaseStatus.pending) {
        // Pending state
      } else {
        if (purchase.status == PurchaseStatus.error) {
          debugPrint("Purchase Error Detail: ${purchase.error?.message} (${purchase.error?.code})");
        } else if (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) {
          bool deliver = await _verifyPurchase(purchase);
          if (deliver) {
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

  Future<bool> _verifyPurchase(PurchaseDetails purchase) async {
    try {
      debugPrint("Verifying purchase token on backend...");
      // Placeholder for your backend verification logic
      return true; 
    } catch (e) {
      debugPrint("Verify Purchase Error: $e");
      return false;
    }
  }
}
