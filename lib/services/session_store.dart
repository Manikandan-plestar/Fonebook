import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_session.dart';
import '../models/contact.dart';

class SessionStore extends ChangeNotifier {
  static final SessionStore _instance = SessionStore._internal();
  factory SessionStore() => _instance;
  SessionStore._internal();

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<UserSession> read() async {
    final p = await _prefs;
    return UserSession(
      phone: p.getString('PHONE'),
      email: p.getString('email'),
      place: p.getString('place'),
      place1: p.getString('place1'),
      country: p.getString('country'),
      image: p.getString('image'),
      premium: p.getBool('premium') ?? false,
    );
  }

  Future<void> save(UserSession s) async {
    final p = await _prefs;
    if (s.phone != null) await p.setString('PHONE', s.phone!);
    if (s.email != null) await p.setString('email', s.email!);
    if (s.place != null) await p.setString('place', s.place!);
    if (s.place1 != null) await p.setString('place1', s.place1!);
    if (s.country != null) await p.setString('country', s.country!);
    if (s.image != null) await p.setString('image', s.image!);
    await p.setBool('premium', s.premium);
    notifyListeners();
  }

  Future<void> clear() async {
    final p = await _prefs;
    await p.clear();
    notifyListeners();
  }

  Future<void> logout() => clear();

  Future<void> addToHistory(DirectoryContact c) async {
    final p = await _prefs;
    final list = p.getStringList('history') ?? [];
    
    // Create a copy with current timestamp
    final contactWithTime = DirectoryContact(
      id: c.id,
      name: c.name,
      service: c.service,
      phone: c.phone,
      location: c.location,
      location1: c.location1,
      image: c.image,
      keyword: c.keyword,
      verified: c.verified,
      priorityBalance: c.priorityBalance,
      priority: c.priority,
      email: c.email,
      whatsapp: c.whatsapp,
      landline: c.landline,
      skype: c.skype,
      about: c.about,
      category: c.category,
      whoContact: c.whoContact,
      showContact: c.showContact,
      publish: c.publish,
      timestamp: DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
    );

    final json = jsonEncode(contactWithTime.toJson());
    // Remove if already exists to move to top - matching by id if available, else phone
    list.removeWhere((item) {
      final parsed = DirectoryContact.fromJson(jsonDecode(item));
      if (c.id != null && parsed.id != null) {
        return parsed.id == c.id;
      }
      return parsed.phone == c.phone;
    });
    list.insert(0, json);
    if (list.length > 50) list.removeLast();
    await p.setStringList('history', list);
    notifyListeners();
  }

  Future<List<DirectoryContact>> getHistory() async {
    final p = await _prefs;
    final list = p.getStringList('history') ?? [];
    return list.map((e) => DirectoryContact.fromJson(jsonDecode(e))).toList();
  }

  Future<void> removeFromHistory(DirectoryContact c) async {
    final p = await _prefs;
    final list = p.getStringList('history') ?? [];
    list.removeWhere((item) {
      final parsed = DirectoryContact.fromJson(jsonDecode(item));
      final sameId = c.id != null && parsed.id != null ? parsed.id == c.id : parsed.phone == c.phone;
      final sameTime = c.timestamp == null || parsed.timestamp == c.timestamp;
      return sameId && sameTime;
    });
    await p.setStringList('history', list);
    notifyListeners();
  }

  Future<void> toggleFavourite(DirectoryContact c) async {
    final p = await _prefs;
    final list = p.getStringList('favourites') ?? [];
    final index = list.indexWhere((e) {
      final parsed = DirectoryContact.fromJson(jsonDecode(e));
      if (c.id != null && parsed.id != null) {
        return parsed.id == c.id;
      }
      return parsed.phone == c.phone;
    });
    if (index != -1) {
      list.removeAt(index);
    } else {
      list.insert(0, jsonEncode(c.toJson()));
    }
    await p.setStringList('favourites', list);
    notifyListeners();
  }

  Future<List<DirectoryContact>> getFavourites() async {
    final p = await _prefs;
    final list = p.getStringList('favourites') ?? [];
    return list.map((e) => DirectoryContact.fromJson(jsonDecode(e))).toList();
  }

  bool isFavourite(String phone, List<DirectoryContact> favourites) {
    return favourites.any((e) => e.phone == phone);
  }

  bool isContactFavourite(DirectoryContact contact, List<DirectoryContact> favourites) {
    return favourites.any((e) {
      if (contact.id != null && e.id != null) {
        return e.id == contact.id;
      }
      return e.phone == contact.phone;
    });
  }

  // Category Storage & Management
  Future<List<String>> getCategories() async {
    final p = await _prefs;
    final custom = p.getStringList('custom_categories') ?? [];
    final defaults = ['Family', 'Friends', 'Office'];
    final list = <String>[...defaults];
    for (final c in custom) {
      if (!list.any((e) => e.toLowerCase() == c.toLowerCase())) {
        list.add(c);
      }
    }
    return list;
  }

  Future<void> addCategory(String cat) async {
    final trimmed = cat.trim();
    if (trimmed.isEmpty) return;
    final p = await _prefs;
    final custom = p.getStringList('custom_categories') ?? [];
    if (!custom.any((e) => e.toLowerCase() == trimmed.toLowerCase())) {
      custom.add(trimmed);
      await p.setStringList('custom_categories', custom);
      notifyListeners();
    }
  }

  Future<void> setContactCategory(String phone, String category) async {
    final p = await _prefs;
    final map = (jsonDecode(p.getString('contact_categories_map') ?? '{}') as Map).cast<String, dynamic>();
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.isNotEmpty) {
      map[cleanPhone] = category;
      await p.setString('contact_categories_map', jsonEncode(map));
      notifyListeners();
    }
  }

  Future<Map<String, String>> getAllContactCategories() async {
    final p = await _prefs;
    final raw = (jsonDecode(p.getString('contact_categories_map') ?? '{}') as Map).cast<String, dynamic>();
    return raw.map((k, v) => MapEntry(k, v.toString()));
  }

  // Application Profile Storage
  Future<Map<String, dynamic>?> getAppProfile({String? email}) async {
    final p = await _prefs;
    final raw = p.getString('app_profile');
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (email != null && email.trim().isNotEmpty) {
        final cachedEmail = (map['email'] ?? map['owner_email'] ?? '').toString().trim().toLowerCase();
        if (cachedEmail.isNotEmpty && cachedEmail != email.trim().toLowerCase()) {
          return null;
        }
      }
      return map;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveAppProfile(Map<String, dynamic> profile) async {
    final p = await _prefs;
    await p.setString('app_profile', jsonEncode(profile));
    notifyListeners();
  }

  // Notifications Management
  Future<List<Map<String, dynamic>>> getNotifications() async {
    final p = await _prefs;
    final list = p.getStringList('app_notifications') ?? [];
    return list.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  Future<void> addNotification({required String title, required String message}) async {
    final p = await _prefs;
    final list = p.getStringList('app_notifications') ?? [];
    final item = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'title': title,
      'message': message,
      'timestamp': DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now()),
      'isRead': false,
    };
    list.insert(0, jsonEncode(item));
    await p.setStringList('app_notifications', list);
    notifyListeners();
  }

  Future<void> markNotificationsRead() async {
    final p = await _prefs;
    final list = p.getStringList('app_notifications') ?? [];
    final updated = list.map((e) {
      final map = jsonDecode(e) as Map<String, dynamic>;
      map['isRead'] = true;
      return jsonEncode(map);
    }).toList();
    await p.setStringList('app_notifications', updated);
    notifyListeners();
  }

  Future<void> deleteNotification(int index) async {
    final p = await _prefs;
    final list = p.getStringList('app_notifications') ?? [];
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      await p.setStringList('app_notifications', list);
      notifyListeners();
    }
  }

  Future<bool> hasUnreadNotifications() async {
    final p = await _prefs;
    final list = p.getStringList('app_notifications') ?? [];
    for (final e in list) {
      final map = jsonDecode(e) as Map<String, dynamic>;
      if (map['isRead'] == false) return true;
    }
    return false;
  }

  Future<Map<String, dynamic>?> getLatestUnreadNotification() async {
    final p = await _prefs;
    final list = p.getStringList('app_notifications') ?? [];
    for (final e in list) {
      final map = jsonDecode(e) as Map<String, dynamic>;
      if (map['isRead'] == false) return map;
    }
    return null;
  }
}
