import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const _apiBase ='https://apps.plestarinc.com:3002/';

    // ? 'http://10.0.2.2:8000/'
     

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

  Future<dynamic> delete(String path, Map<String, dynamic> bodyPayload, [Map<String, String?> query = const {}]) async {
    final uri = _uri(path, query);
    final req = http.Request('DELETE', uri);
    req.headers['Content-Type'] = 'application/json';
    req.body = jsonEncode(bodyPayload);
    final streamedResp = await _client.send(req).timeout(const Duration(seconds: 25));
    final resp = await http.Response.fromStream(streamedResp);
    debugPrint('[API] DELETE $path -> Status: ${resp.statusCode}, Body: ${resp.body}');
    if (resp.statusCode != 200) {
      throw Exception('Server Error ${resp.statusCode}: ${resp.body}');
    }
    try {
      return jsonDecode(resp.body);
    } catch (_) {
      return resp.body;
    }
  }

  Future<dynamic> addCallToBackend({
    required String name,
    required String phone,
    String? service,
    required String userId,
    String? callTime,
  }) async {
    try {
      final payload = <String, String?>{
        'name': name,
        'phone_number': phone,
        'service': service,
        'user_id': userId,
        'owner_email': userId,
        'call_time': callTime ?? DateTime.now().toIso8601String(),
      };
      return await post('api/user_calls', payload);
    } catch (e) {
      debugPrint('[API] addCallToBackend error: $e');
      return null;
    }
  }

  Future<List<dynamic>> getCallHistoryFromBackend({required String userId}) async {
    try {
      final query = <String, String?>{
        'user_id': userId,
        'owner_email': userId,
      };
      final res = await get('api/user_calls', query);
      if (res is Map && res['data'] is List) {
        return res['data'] as List;
      } else if (res is List) {
        return res;
      }
      return [];
    } catch (e) {
      debugPrint('[API] getCallHistoryFromBackend error: $e');
      return [];
    }
  }

  Future<dynamic> deleteCallsFromBackend({
    List<String>? callIds,
    bool clearAll = false,
    required String userId,
  }) async {
    try {
      final query = <String, String?>{
        'user_id': userId,
        'owner_email': userId,
        if (clearAll) 'clear_all': 'true',
      };
      final payload = <String, dynamic>{
        'user_id': userId,
        'owner_email': userId,
        'clear_all': clearAll,
        if (callIds != null) 'call_ids': callIds,
      };
      return await delete('api/user_calls', payload, query);
    } catch (e) {
      debugPrint('[API] deleteCallsFromBackend error: $e');
      return null;
    }
  }
}
