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
      debugPrint("IAP Subscription Error: $error");
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
      debugPrint("In-App Billing not available on this device.");
      return false;
    }

    debugPrint("Loading products: $ids");
    final ProductDetailsResponse resp = await _iap.queryProductDetails(ids.toSet());
    if (resp.error != null) {
      debugPrint("IAP Query Error: ${resp.error?.message} (${resp.error?.code})");
      return false;
    }
    
    if (resp.notFoundIDs.isNotEmpty) {
      debugPrint("Warning: Some IDs were not found in App Store / Play Console: ${resp.notFoundIDs}");
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

  final Set<String> _verifiedPurchaseIDs = {};

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
          final txKey = purchase.purchaseID ?? purchase.verificationData.serverVerificationData;
          if (txKey.isNotEmpty && _verifiedPurchaseIDs.contains(txKey)) {
            debugPrint("Skipping already processed purchase: $txKey");
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
