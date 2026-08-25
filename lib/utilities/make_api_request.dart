import 'dart:convert';
import 'package:dutch_remit/hadwin_components.dart';
import 'package:http/http.dart' as http;

Future<Map<String, dynamic>> getData(
    {required String urlPath, String? authKey}) async {
  String backendServiceHost = "${ApiConstants.baseUrl}" + urlPath;
  try {
    final response = await http.get(
      Uri.parse(backendServiceHost),
      headers: <String, String>{
        'Content-Type': 'application/json',
        if (authKey != null) 'Authorization': authKey
      },
    ).timeout(const Duration(seconds: 10), onTimeout: () {
      throw Exception('Request timed out');
    });

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return {'apiRequestError': 'empty response from server'};
      }
      try {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        return {
          'apiRequestError': 'invalid JSON response',
          'responseBody': response.body,
        };
      }
    }

    // Non-2xx, but the backend's error handler (Backend/src/errorHandler.js)
    // still returns a real JSON body — { error, needsVirtualAccount,
    // virtualAccountCurrency, ... }. Decode it and merge those fields
    // straight into the result instead of only exposing the generic
    // apiRequestError string, so callers can branch on e.g.
    // `result['needsVirtualAccount']` without re-parsing responseBody
    // themselves.
    Map<String, dynamic> decoded = {};
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map<String, dynamic>) decoded = parsed;
    } catch (_) {
      // Not JSON (e.g. a plain-text 500 from a proxy) — fall through
      // with just the generic error below.
    }

    return {
      ...decoded,
      'apiRequestError': 'status code ${response.statusCode}',
      'statusCode': response.statusCode,
      'responseBody': response.body,
    };
  } catch (e) {
    // Surface a human-readable message instead of the raw exception
    // text (e.g. "ClientException: Failed to fetch, uri=...") which
    // otherwise leaked straight into error dialogs verbatim.
    final message = e.toString().toLowerCase().contains('failed to fetch') ||
            e.toString().toLowerCase().contains('timed out') ||
            e.toString().toLowerCase().contains('socketexception')
        ? 'We couldn\'t reach the server. Please check your connection and try again.'
        : 'Something went wrong. Please try again.';
    return {'apiRequestError': message};
  }
}

Future<Map<String, dynamic>> sendData(
    {required String urlPath,
    required Map<String, dynamic> data,
    String? authKey}) async {
  String backendServiceHost = "${ApiConstants.baseUrl}" + urlPath;
  try {
    final response = await http.post(
      Uri.parse(backendServiceHost),
      headers: <String, String>{
        'Content-Type': 'application/json',
        if (authKey != null) 'Authorization': authKey
      },
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 10), onTimeout: () {
      throw Exception('Request timed out');
    });

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return {'apiRequestError': 'empty response from server'} as Map<String, dynamic>;
      }
      try {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        return {
          'apiRequestError': 'invalid JSON response',
          'responseBody': response.body,
        };
      }
    }

    // Non-2xx, but the backend's error handler (Backend/src/errorHandler.js)
    // still returns a real JSON body — { error, needsVirtualAccount,
    // virtualAccountCurrency, ... }. Decode it and merge those fields
    // straight into the result instead of only exposing the generic
    // apiRequestError string, so callers can branch on e.g.
    // `result['needsVirtualAccount']` without re-parsing responseBody
    // themselves.
    Map<String, dynamic> decoded = {};
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map<String, dynamic>) decoded = parsed;
    } catch (_) {
      // Not JSON (e.g. a plain-text 500 from a proxy) — fall through
      // with just the generic error below.
    }

    return {
      ...decoded,
      'apiRequestError': 'status code ${response.statusCode}',
      'statusCode': response.statusCode,
      'responseBody': response.body,
    };
  } catch (e) {
    final message = e.toString().toLowerCase().contains('failed to fetch') ||
            e.toString().toLowerCase().contains('timed out') ||
            e.toString().toLowerCase().contains('socketexception')
        ? 'We couldn\'t reach the server. Please check your connection and try again.'
        : 'Something went wrong. Please try again.';
    return {'apiRequestError': message};
  }
}

Future<int> checkUrlValidity(String url) async {
  try {
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 5), onTimeout: () {
      throw Exception('Request timed out');
    });

    return response.statusCode;
  } catch (e) {
    return 404;
  }
}

