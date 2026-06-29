import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _base = 'https://imliti-api.icyplant-2cc88c2d.northeurope.azurecontainerapps.io';
const _keyAccess  = 'access_token';
const _keyRefresh = 'refresh_token';
const _keyUser    = 'user_json';
const _keyEmail   = 'saved_email';

class AuthUser {
  final int id;
  final String email;
  final String role;
  final String? nombre;

  const AuthUser({
    required this.id,
    required this.email,
    required this.role,
    this.nombre,
  });

  bool get isAdmin => role == 'admin';

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: j['id'] as int,
        email: j['email'] as String,
        role: j['role'] as String,
        nombre: j['nombre'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'role': role,
        'nombre': nombre,
      };
}

class AuthService {
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  final _storage = const FlutterSecureStorage();

  AuthUser? _currentUser;
  AuthUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  // Called on app start — tries to restore session from stored refresh token.
  Future<bool> tryRestoreSession() async {
    final refresh = await _storage.read(key: _keyRefresh);
    if (refresh == null) return false;

    final userJson = await _storage.read(key: _keyUser);
    if (userJson != null) {
      _currentUser = AuthUser.fromJson(
        jsonDecode(userJson) as Map<String, dynamic>,
      );
    }

    // Try to get a fresh access token using the stored refresh token.
    try {
      final res = await http.post(
        Uri.parse('$_base/auth/refresh'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'refresh_token': refresh}),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        await _storage.write(
          key: _keyAccess,
          value: body['access_token'] as String,
        );
        return true;
      }
    } catch (_) {}

    // Refresh failed — clear stale tokens
    await _clearTokens();
    _currentUser = null;
    return false;
  }

  Future<AuthUser> login({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Error al iniciar sesión');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final user = AuthUser.fromJson(body['user'] as Map<String, dynamic>);

    await _storage.write(key: _keyAccess, value: body['access_token'] as String);
    await _storage.write(key: _keyUser, value: jsonEncode(user.toJson()));
    await _storage.write(key: _keyEmail, value: email);

    // Only persist refresh token if "remember me" is checked
    if (rememberMe) {
      await _storage.write(key: _keyRefresh, value: body['refresh_token'] as String);
    }

    _currentUser = user;
    return user;
  }

  Future<void> storeTokensFromRegistration({
    required String accessToken,
    required String refreshToken,
    required AuthUser user,
  }) async {
    await _storage.write(key: _keyAccess, value: accessToken);
    await _storage.write(key: _keyRefresh, value: refreshToken);
    await _storage.write(key: _keyUser, value: jsonEncode(user.toJson()));
    _currentUser = user;
  }

  Future<void> logout() async {
    await _clearTokens();
    _currentUser = null;
  }

  Future<String?> get accessToken => _storage.read(key: _keyAccess);
  Future<String?> get savedEmail  => _storage.read(key: _keyEmail);

  Future<void> _clearTokens() async {
    await _storage.delete(key: _keyAccess);
    await _storage.delete(key: _keyRefresh);
    await _storage.delete(key: _keyUser);
  }
}
