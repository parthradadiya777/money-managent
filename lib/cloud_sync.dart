import 'dart:convert';
import 'package:http/http.dart' as http;

class CloudSyncService {
  static const String baseUrl = String.fromEnvironment('API_BASE_URL');
  static bool get configured => baseUrl.trim().isNotEmpty;
  String? token;

  CloudSyncService({this.token});

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Uri _uri(String path) => Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');

  Future<Map<String, dynamic>> authenticate({
    required String email,
    required String password,
    String? businessName,
    required bool register,
  }) async {
    final path = register ? '/api/auth/register' : '/api/auth/login';
    final body = <String, dynamic>{'email': email, 'password': password};
    if (register) body['business_name'] = businessName;
    final response = await http.post(_uri(path), headers: _headers, body: jsonEncode(body));
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['detail'] ?? 'Authentication failed');
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> fetchRecords() async {
    final response = await http.get(_uri('/api/records'), headers: _headers);
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['detail'] ?? 'Could not download cloud data');
    }
    return (data['records'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> upsertRecords(List<Map<String, dynamic>> records) async {
    for (var start = 0; start < records.length; start += 500) {
      final chunk = records.skip(start).take(500).toList();
      final response = await http.put(
        _uri('/api/records/batch'),
        headers: _headers,
        body: jsonEncode({'records': chunk}),
      );
      final data = _decode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data['detail'] ?? 'Cloud upload failed');
      }
    }
  }

  Future<void> deleteRecord(String recordId) async {
    final response = await http.delete(
      _uri('/api/records/${Uri.encodeComponent(recordId)}'),
      headers: _headers,
    );
    if (response.statusCode != 404 && (response.statusCode < 200 || response.statusCode >= 300)) {
      final data = _decode(response);
      throw Exception(data['detail'] ?? 'Cloud delete failed');
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      return {'detail': response.body.isEmpty ? 'Unexpected server response' : response.body};
    }
  }
}
