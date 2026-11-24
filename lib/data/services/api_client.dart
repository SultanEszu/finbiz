import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();

  static final instance = ApiClient._();
  final StreamController<AppUser?> _sessionChanges =
      StreamController<AppUser?>.broadcast(sync: true);

  static const _accountsKey = 'finbiz_accounts_v1';
  static const _financeKey = 'finbiz_finance_v1';
  static const _sessionKey = 'finbiz_session_v1';

  AppUser? _currentUser;
  final List<Map<String, dynamic>> _categories = [];
  final List<Map<String, dynamic>> _transactions = [];
  final List<Map<String, dynamic>> _debts = [];
  final List<Map<String, dynamic>> _budgets = [];
  final List<Map<String, dynamic>> _notifications = [];
  final List<Map<String, dynamic>> _savings = [];
  List<Map<String, dynamic>> _accounts = [];
  Map<String, dynamic> _profile = {};
  Future<void> _mutation = Future<void>.value();
  bool _initialized = false;

  String get baseUrl => '';
  AppUser? get currentUser => _currentUser;

  Stream<AppUser?> get authStateChanges => Stream.multi((controller) {
    controller.add(_currentUser);
    final subscription = _sessionChanges.stream.listen(controller.add);
    controller.onCancel = subscription.cancel;
  });

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();

    final accountsRaw = prefs.getString(_accountsKey);
    if (accountsRaw != null) {
      _accounts = (jsonDecode(accountsRaw) as List<dynamic>)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    }

    final financeRaw = prefs.getString(_financeKey);
    if (financeRaw == null) {
      _seedData();
      await _persistFinance();
    } else {
      final data = Map<String, dynamic>.from(jsonDecode(financeRaw) as Map);
      _replaceList(_categories, data['categories']);
      _replaceList(_transactions, data['transactions']);
      _replaceList(_debts, data['debts']);
      _replaceList(_budgets, data['budgets']);
      _replaceList(_notifications, data['notifications']);
      _replaceList(_savings, data['savings']);
    }

    final sessionRaw = prefs.getString(_sessionKey);
    if (sessionRaw != null) {
      final session = Map<String, dynamic>.from(jsonDecode(sessionRaw) as Map);
      final account = _accounts.where((item) => item['id'] == session['user_id']).firstOrNull;
      if (account != null) {
        _profile = Map<String, dynamic>.from(account);
        _setCurrentUser(AppUser(id: account['id'] as String, email: account['email'] as String));
      }
    }

    if (_currentUser == null) {
      if (_accounts.isEmpty) {
        final account = {
          'id': _id('user'),
          'email': 'pengguna@finbiz.local',
          'full_name': 'Pengguna FinBiz',
          'role': 'creator',
          'password_hash': '',
          'must_change_password': false,
        };
        _accounts.add(account);
        await _persistAccounts();
      }
      final account = _accounts.first;
      _profile = Map<String, dynamic>.from(account);
      await setSession(
        token: 'local-session',
        user: AppUser(
          id: account['id'] as String,
          email: account['email'] as String,
        ),
      );
    }
    _initialized = true;
  }

  void _seedData() {
    _categories.addAll([
      {'id': 'cat-1', 'name': 'Penjualan', 'type': 'income', 'icon_name': 'store', 'color_value': 0xFF10B981},
      {'id': 'cat-2', 'name': 'Operasional', 'type': 'expense', 'icon_name': 'business', 'color_value': 0xFFF59E0B},
      {'id': 'cat-3', 'name': 'Gaji', 'type': 'expense', 'icon_name': 'people', 'color_value': 0xFF6366F1},
    ]);
    _transactions.addAll([
      {'id': 'tx-1', 'title': 'Pembayaran pelanggan', 'category_id': 'cat-1', 'amount': 2500000, 'transaction_date': DateTime.now().toIso8601String().substring(0, 10), 'transaction_type': 'income', 'description': 'Pembayaran pesanan'},
      {'id': 'tx-2', 'title': 'Belanja operasional', 'category_id': 'cat-2', 'amount': 450000, 'transaction_date': DateTime.now().toIso8601String().substring(0, 10), 'transaction_type': 'expense', 'description': 'Kebutuhan usaha'},
    ]);
  }

  void _replaceList(List<Map<String, dynamic>> target, dynamic raw) {
    target
      ..clear()
      ..addAll((raw as List<dynamic>? ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map)));
  }

  Future<T> _serialized<T>(Future<T> Function() action) async {
    final completer = Completer<T>();
    _mutation = _mutation.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    await _mutation;
    return completer.future;
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) async {
    await initialize();
    if (path == '/finance') {
      final balance = _transactions.fold<double>(0, (total, row) {
        final amount = (row['amount'] as num).toDouble();
        return row['transaction_type'] == 'income' ? total + amount : total - amount;
      });
      return {
        'categories': List<Map<String, dynamic>>.from(_categories),
        'transactions': List<Map<String, dynamic>>.from(_transactions),
        'cash_account_balances': [{'balance': balance}],
        'debts': List<Map<String, dynamic>>.from(_debts),
        'budgets': List<Map<String, dynamic>>.from(_budgets),
        'notifications': List<Map<String, dynamic>>.from(_notifications),
        'savings': List<Map<String, dynamic>>.from(_savings),
      };
    }
    if (path == '/auth/me' || path == '/profile') return {'user': _profileMap};
    if (path == '/profiles') return {'users': [_profileMap]};
    if (path == '/receipts/signed-url') {
      throw const ApiException(501, 'Bukti transaksi belum tersedia dalam penyimpanan lokal.');
    }
    throw const ApiException(404, 'Data tidak ditemukan.');
  }

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body}) async {
    await initialize();
    final payload = body ?? const <String, dynamic>{};
    if (path == '/auth/login') return _login(payload);
    if (path == '/auth/register') return _register(payload);
    if (path == '/auth/forgot-password') return {'message': 'Reset kata sandi harus diproses di perangkat ini.'};
    if (path == '/auth/reset-password' || path == '/auth/change-password') {
      throw const ApiException(501, 'Fitur ini belum tersedia pada penyimpanan lokal.');
    }
    if (path == '/auth/logout') {
      await clearSession();
      return {'message': 'Berhasil keluar.'};
    }

    return _serialized(() async {
      if (path == '/transactions') {
        _validateCategoryDuplicateTransaction(payload);
        _transactions.insert(0, {'id': _id('tx'), ...payload});
      } else if (path == '/categories') {
        final name = (payload['name'] as String).trim().toLowerCase();
        if (_categories.any((item) => (item['name'] as String).trim().toLowerCase() == name)) {
          throw const ApiException(422, 'Nama kategori sudah digunakan.');
        }
        _categories.add({'id': _id('cat'), ...payload});
      } else if (path == '/debts') {
        _debts.insert(0, {'id': _id('debt'), ...payload});
      } else if (path == '/budgets') {
        _budgets.add({'id': _id('budget'), ...payload});
      } else if (path == '/savings') {
        _savings.add({
          'id': _id('saving'),
          'target_name': payload['target_name'],
          'target_amount': payload['target_amount'],
          'current_amount': 0,
          'target_date': payload['target_date'],
        });
      } else {
        throw const ApiException(404, 'Operasi tidak tersedia dalam mode lokal.');
      }
      await _persistFinance();
      return {'message': 'Berhasil disimpan.'};
    });
  }

  Future<Map<String, dynamic>> put(String path, {Map<String, dynamic>? body}) async {
    await initialize();
    final payload = body ?? const <String, dynamic>{};
    return _serialized(() async {
      if (path.startsWith('/transactions/')) {
        final id = path.split('/').last;
        final index = _transactions.indexWhere((item) => item['id'] == id);
        if (index < 0) throw const ApiException(404, 'Transaksi tidak ditemukan.');
        _validateCategoryDuplicateTransaction(payload);
        _transactions[index] = {'id': id, ...payload};
      } else if (path.startsWith('/categories/')) {
        final id = path.split('/').last;
        final index = _categories.indexWhere((item) => item['id'] == id);
        if (index < 0) throw const ApiException(404, 'Kategori tidak ditemukan.');
        final name = (payload['name'] as String).trim().toLowerCase();
        if (_categories.any((item) =>
            item['id'] != id &&
            (item['name'] as String).trim().toLowerCase() == name)) {
          throw const ApiException(422, 'Nama kategori sudah digunakan.');
        }
        _categories[index] = {'id': id, ...payload};
      } else if (path.startsWith('/profiles/') && path.endsWith('/role')) {
        return {'message': 'Role berhasil diperbarui dalam mode lokal.'};
      } else {
        throw const ApiException(404, 'Data tidak ditemukan.');
      }
      await _persistFinance();
      return {'message': 'Berhasil diperbarui.'};
    });
  }

  Future<Map<String, dynamic>> patch(String path, {Map<String, dynamic>? body}) async {
    await initialize();
    if (path == '/profile') {
      final fullName = (body?['full_name'] as String?)?.trim();
      if (fullName == null || fullName.isEmpty) {
        throw const ApiException(422, 'Nama profil tidak boleh kosong.');
      }
      if (_currentUser == null) throw const ApiException(401, 'Silakan masuk terlebih dahulu.');
      return _serialized(() async {
        final index = _accounts.indexWhere((item) => item['id'] == _currentUser!.id);
        if (index < 0) throw const ApiException(404, 'Profil tidak ditemukan.');
        _accounts[index]['full_name'] = fullName;
        _profile = Map<String, dynamic>.from(_accounts[index]);
        await _persistAccounts();
        return {'message': 'Profil berhasil diperbarui.', 'user': _profileMap};
      });
    }
    throw const ApiException(404, 'Data tidak ditemukan.');
  }

  Future<Map<String, dynamic>> delete(String path, {Map<String, dynamic>? body}) async {
    await initialize();
    return _serialized(() async {
      if (path.startsWith('/transactions/')) {
        _transactions.removeWhere((item) => item['id'] == path.split('/').last);
      } else if (path.startsWith('/categories/')) {
        final id = path.split('/').last;
        _categories.removeWhere((item) => item['id'] == id);
        for (final transaction in _transactions) {
          if (transaction['category_id'] == id) transaction['category_id'] = null;
        }
      } else if (path.startsWith('/debts/')) {
        _debts.removeWhere((item) => item['id'] == path.split('/').last);
      } else if (path.startsWith('/budgets/')) {
        _budgets.removeWhere((item) => item['id'] == path.split('/').last);
      } else if (path.startsWith('/savings/')) {
        _savings.removeWhere((item) => item['id'] == path.split('/').last);
      } else {
        throw const ApiException(404, 'Data tidak ditemukan.');
      }
      await _persistFinance();
      return {'message': 'Berhasil dihapus.'};
    });
  }

  Future<Map<String, dynamic>> upload(String path, {required Map<String, String> fields, required String fileField, required String fileName, required List<int> bytes}) async {
    throw const ApiException(501, 'Unggah bukti belum tersedia dalam penyimpanan lokal.');
  }

  Future<Map<String, dynamic>> _register(Map<String, dynamic> body) async {
    final email = (body['email'] as String? ?? '').trim().toLowerCase();
    final password = body['password'] as String? ?? '';
    final fullName = (body['full_name'] as String? ?? '').trim();
    if (!_validEmail(email) || !_validPassword(password) || fullName.isEmpty) {
      throw const ApiException(422, 'Periksa nama, email, dan kekuatan kata sandi.');
    }
    return _serialized(() async {
      if (_accounts.any((item) => (item['email'] as String).toLowerCase() == email)) {
        throw const ApiException(409, 'Email sudah terdaftar pada perangkat ini.');
      }
      final account = {
        'id': _id('user'),
        'email': email,
        'full_name': fullName,
        'role': 'creator',
        'password_hash': sha256.convert(utf8.encode(password)).toString(),
        'must_change_password': false,
      };
      _accounts.add(account);
      await _persistAccounts();
      await setSession(token: 'local-session', user: AppUser(id: account['id'] as String, email: email));
      _profile = Map<String, dynamic>.from(account);
      return {'token': 'local-session', 'user': account};
    });
  }

  Future<Map<String, dynamic>> _login(Map<String, dynamic> body) async {
    final email = (body['email'] as String? ?? '').trim().toLowerCase();
    final password = body['password'] as String? ?? '';
    final account = _accounts.where((item) => (item['email'] as String).toLowerCase() == email).firstOrNull;
    final hash = sha256.convert(utf8.encode(password)).toString();
    if (account == null || account['password_hash'] != hash) {
      throw const ApiException(401, 'Email atau kata sandi tidak sesuai.');
    }
    final user = AppUser(id: account['id'] as String, email: account['email'] as String);
    await setSession(token: 'local-session', user: user);
    _profile = Map<String, dynamic>.from(account);
    return {'token': 'local-session', 'user': account};
  }

  bool _validEmail(String email) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  bool _validPassword(String password) => password.length >= 8 && RegExp(r'[A-Z]').hasMatch(password) && RegExp(r'[a-z]').hasMatch(password) && RegExp(r'[0-9]').hasMatch(password);

  Map<String, dynamic> get _profileMap => {
    'id': _profile['id'] ?? _currentUser?.id ?? 'local-user',
    'email': _profile['email'] ?? _currentUser?.email ?? 'pengguna@finbiz.local',
    'full_name': _profile['full_name'] ?? 'Pengguna FinBiz',
    'role': _profile['role'] ?? 'creator',
    'must_change_password': _profile['must_change_password'] ?? false,
  };

  Future<void> setSession({required String token, required AppUser user}) async {
    _setCurrentUser(user);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode({'token': token, 'user_id': user.id}));
  }

  void _setCurrentUser(AppUser? user) {
    _currentUser = user;
    _sessionChanges.add(user);
  }

  Future<void> clearSession() async {
    // Mode lokal tanpa login: pastikan selalu ada sesi pengguna default.
    if (_accounts.isEmpty) {
      final account = {
        'id': _id('user'),
        'email': 'pengguna@finbiz.local',
        'full_name': 'Pengguna FinBiz',
        'role': 'creator',
        'password_hash': '',
        'must_change_password': false,
      };
      _accounts.add(account);
      await _persistAccounts();
    }
    final account = _accounts.first;
    _profile = Map<String, dynamic>.from(account);
    await setSession(
      token: 'local-session',
      user: AppUser(
        id: account['id'] as String,
        email: account['email'] as String,
      ),
    );
  }

  void _validateCategoryDuplicateTransaction(Map<String, dynamic> body) {
    final categoryId = body['category_id'] as String?;
    if (categoryId != null && !_categories.any((item) => item['id'] == categoryId)) {
      throw const ApiException(422, 'Kategori transaksi tidak valid.');
    }
  }

  Future<void> _persistAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountsKey, jsonEncode(_accounts));
  }

  Future<void> _persistFinance() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_financeKey, jsonEncode({
      'categories': _categories,
      'transactions': _transactions,
      'debts': _debts,
      'budgets': _budgets,
      'notifications': _notifications,
      'savings': _savings,
    }));
  }

  String _id(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  Future<String> exportBackupJson() async {
    await initialize();
    final prefs = await SharedPreferences.getInstance();
    final finance = prefs.getString(_financeKey) ?? '{}';
    return jsonEncode({
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'accounts': _accounts.map((item) {
        final safe = Map<String, dynamic>.from(item);
        safe.remove('password_hash');
        return safe;
      }).toList(),
      'finance': jsonDecode(finance),
    });
  }

  Future<void> restoreBackupJson(String jsonText) async {
    await initialize();
    late final Map<String, dynamic> backup;
    try {
      backup = Map<String, dynamic>.from(jsonDecode(jsonText) as Map);
    } catch (_) {
      throw const ApiException(422, 'Format cadangan JSON tidak valid.');
    }
    final finance = backup['finance'];
    if (backup['version'] != 1 || finance is! Map) {
      throw const ApiException(422, 'Versi atau struktur cadangan tidak didukung.');
    }

    await _serialized(() async {
      final data = Map<String, dynamic>.from(finance);
      _replaceList(_categories, data['categories']);
      _replaceList(_transactions, data['transactions']);
      _replaceList(_debts, data['debts']);
      _replaceList(_budgets, data['budgets']);
      _replaceList(_notifications, data['notifications']);
      _replaceList(_savings, data['savings']);
      await _persistFinance();
    });
  }
}
