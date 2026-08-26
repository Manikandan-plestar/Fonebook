import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const _apiBase = 'http://10.0.2.2:8000/';
// 'https://apps.plestarinc.com:3002/';

class ApiClient {
  final http.Client _client = http.Client();

  Uri _uri(String path, [Map<String, String?> query = const {}]) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final params = <String, String>{};
    for (final entry in query.entries) {
      if (entry.value != null && entry.value!.isNotEmpty) params[entry.key] = entry.value!;
    }
    return Uri.parse('$_apiBase$cleanPath').replace(queryParameters: params.isEmpty ? null : params);
  }

  Future<dynamic> get(String path, [Map<String, String?> query = const {}]) async {
    final resp = await _client.get(_uri(path, query)).timeout(const Duration(seconds: 25));
    if (resp.statusCode != 200) throw Exception('Server Error: ${resp.statusCode}');
    return jsonDecode(resp.body);
  }

  Future<dynamic> post(String path, Map<String, String?> fields, {Duration? timeout}) async {
    final body = <String, String>{};
    for (final entry in fields.entries) {
      if (entry.value != null) body[entry.key] = entry.value!;
    }
    final resp = await _client.post(_uri(path), body: body).timeout(timeout ?? const Duration(seconds: 25));
    debugPrint('[API] POST $path -> Status: ${resp.statusCode}, Body: ${resp.body}');
    if (resp.statusCode != 200) {
      throw Exception('Server Error ${resp.statusCode}: ${resp.body}');
    }
    try {
      return jsonDecode(resp.body);
    } catch (_) {
      return resp.body;
    }
  }
}
