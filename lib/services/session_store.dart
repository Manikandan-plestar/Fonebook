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
    // Remove if already exists to move to top
    list.removeWhere((item) => DirectoryContact.fromJson(jsonDecode(item)).phone == c.phone);
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

  Future<void> toggleFavourite(DirectoryContact c) async {
    final p = await _prefs;
    final list = p.getStringList('favourites') ?? [];
    final phone = c.phone;
    final index = list.indexWhere((e) => DirectoryContact.fromJson(jsonDecode(e)).phone == phone);
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
}
