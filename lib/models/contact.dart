import 'package:flutter/foundation.dart';

const _assetBase = kDebugMode 
    ? 'http://10.0.2.2/Local%20testing%20file/' 
    : 'https://apps.plestarinc.com/';


class DirectoryContact {
  final String? id;
  final String name;
  final String service;
  final String phone;
  final String? location;
  final String? location1;
  final String? city;
  final String? state;
  final String? image;
  final String? keyword;
  final String? tags;
  final int verified;
  final String priorityBalance;
  final String priority;
  final String? email;
  final String? whatsapp;
  final String? landline;
  final String? skype;
  final String? about;
  final String? category;
  final String? whoContact;
  final String showContact;
  final String publish;
  final String? timestamp; // For Recent/History
  final String favouriteCount;
  final String? additionalPhones;
  final String? additionalServices;
  final List<dynamic>? reviews;
  final double? latitude;
  final double? longitude;

  const DirectoryContact({
    this.id,
    required this.name,
    required this.service,
    required this.phone,
    this.location,
    this.location1,
    this.city,
    this.state,
    this.image,
    this.keyword,
    this.tags,
    this.verified = 0,
    this.priorityBalance = '0',
    this.priority = '1',
    this.email,
    this.whatsapp,
    this.landline,
    this.skype,
    this.about,
    this.category,
    this.whoContact,
    this.showContact = 'mwelsf',
    this.publish = 'yes',
    this.timestamp,
    this.favouriteCount = '0',
    this.additionalPhones,
    this.additionalServices,
    this.reviews,
    this.latitude,
    this.longitude,
  });

  static final Map<String, int> _sessionBusters = {};
  static void bust(String key) {
    _sessionBusters[key] = DateTime.now().millisecondsSinceEpoch;
  }

  String get imageUrl {
    if (image == null || image == 'null' || image!.isEmpty) return '';
    final base = image!.startsWith('http') ? image! : '${_assetBase}uploads/$image';
    
    final dbVersion = timestamp?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    final localVersion = _sessionBusters[id ?? phone] ?? _sessionBusters[phone] ?? 0;

    return '$base?v=$dbVersion&s=$localVersion';
  }

  factory DirectoryContact.fromJson(Map<String, dynamic> json) {
    String p(String k) => json[k]?.toString() ?? '';
    final idVal = p('id');
    final lat = double.tryParse(p('latitude')) ?? double.tryParse(p('lat'));
    final lng = double.tryParse(p('longitude')) ?? double.tryParse(p('lng')) ?? double.tryParse(p('lon'));

    return DirectoryContact(
      id: idVal.isNotEmpty ? idVal : null,
      name: p('name'),
      service: p('service'),
      phone: p('phone_no') == '' ? (p('phone') == '' ? p('phone1') : p('phone')) : p('phone_no'),
      location: p('location'),
      location1: p('location1'),
      city: p('city'),
      state: p('state'),
      image: p('image'),
      keyword: p('keywords') == '' ? p('keyword') : p('keywords'),
      tags: p('tags'),
      verified: int.tryParse(p('verification')) ?? 0,
      priorityBalance: p('priority_balance') == '' ? (p('priority_amount') == '' ? '0' : p('priority_amount')) : p('priority_balance'),
      priority: p('priority') == '' ? '1' : p('priority'),
      email: p('email'),
      whatsapp: p('wpno'),
      landline: p('landlineno'),
      skype: p('skypeno'),
      about: p('about'),
      category: p('category'),
      whoContact: p('who_contact'),
      showContact: p('show_contact') == '' ? 'mwelsf' : p('show_contact'),
      publish: p('publish') == '' ? 'yes' : p('publish'),
      timestamp: p('time') == '' ? p('created') : p('time'),
      favouriteCount: p('favourite_count') == '' ? '0' : p('favourite_count'),
      additionalPhones: p('phonenos'),
      additionalServices: p('services'),
      reviews: json['reviews'] is List ? json['reviews'] : null,
      latitude: lat,
      longitude: lng,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'service': service,
        'phone_no': phone,
        'location': location,
        'location1': location1,
        'city': city,
        'state': state,
        'image': image,
        'keywords': keyword,
        'tags': tags,
        'verification': verified.toString(),
        'priority_balance': priorityBalance,
        'priority': priority,
        'email': email,
        'wpno': whatsapp,
        'landlineno': landline,
        'skypeno': skype,
        'about': about,
        'category': category,
        'who_contact': whoContact,
        'show_contact': showContact,
        'publish': publish,
        'time': timestamp,
        if (latitude != null) 'latitude': latitude.toString(),
        if (longitude != null) 'longitude': longitude.toString(),
      };
}
