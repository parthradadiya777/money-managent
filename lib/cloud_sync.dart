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
    const pageSize = 1000;
    var offset = 0;
    final all = <Map<String, dynamic>>[];
    while (true) {
      final response = await http.get(
        _uri('/api/records?limit=$pageSize&offset=$offset'),
        headers: _headers,
      );
      final data = _decode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data['detail'] ?? 'Could not download cloud data');
      }
      final page = (data['records'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      all.addAll(page);
      if (page.length < pageSize) break;
      offset += pageSize;
    }
    return all;
  }

  Future<Map<String, dynamic>> fetchMe() async {
    final response = await http.get(_uri('/api/auth/me'), headers: _headers);
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['detail'] ?? 'Could not load account');
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> listPartners() async {
    final response = await http.get(_uri('/api/admin/partners'), headers: _headers);
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['detail'] ?? 'Could not load partners');
    }
    return (data['partners'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchPartnerActivity({String? tenantId, int limit = 300}) async {
    final query = <String, String>{'limit': '$limit'};
    if (tenantId != null && tenantId.isNotEmpty) query['tenant_id'] = tenantId;
    final response = await http.get(_uri('/api/admin/partner-activity').replace(queryParameters: query), headers: _headers);
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['detail'] ?? 'Could not load partner activity');
    }
    return (data['activities'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createPartner({
    required String name, required String loginId, required String password,
  }) async {
    final response = await http.post(
      _uri('/api/admin/partners'),
      headers: _headers,
      body: jsonEncode({'name': name, 'login_id': loginId, 'password': password}),
    );
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['detail'] ?? 'Could not create partner');
    }
    return data;
  }

  Future<void> updatePartner(String tenantId, Map<String, dynamic> changes) async {
    final response = await http.patch(
      _uri('/api/admin/partners/$tenantId'),
      headers: _headers,
      body: jsonEncode(changes),
    );
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['detail'] ?? 'Could not update partner');
    }
  }

  Future<Map<String, dynamic>> sendPartnerBackupTest(String tenantId) async {
    final response = await http.post(
      _uri('/api/admin/partners/$tenantId/backup-test'),
      headers: _headers,
    );
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['detail'] ?? 'Could not send test backup email');
    }
    return data;
  }

  Future<void> resetPartnerPassword(String tenantId, String newPassword) async {
    final response = await http.post(
      _uri('/api/admin/partners/$tenantId/reset-password'),
      headers: _headers,
      body: jsonEncode({'new_password': newPassword}),
    );
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['detail'] ?? 'Could not reset partner password');
    }
  }

  Future<Map<String, dynamic>> accessPartner(String tenantId) async {
    final response = await http.post(
      _uri('/api/admin/partners/$tenantId/access'),
      headers: _headers,
    );
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['detail'] ?? 'Could not open partner workspace');
    }
    return data;
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


  Future<Map<String, dynamic>> parseShippingPdf({
    required List<int> bytes, required String filename,
    required String platform, required String firm,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/api/orders/parse-label-pdf'));
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['platform'] = platform;
    request.fields['firm'] = firm;
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await request.send().timeout(const Duration(minutes: 2));
    final response = await http.Response.fromStream(streamed);
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['detail'] ?? 'PDF parsing failed');
    }
    return data;
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
