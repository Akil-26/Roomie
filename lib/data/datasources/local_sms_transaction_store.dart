import 'dart:async';
import 'package:hive_flutter/hive_flutter.dart';
// ignore: unnecessary_import
import 'package:hive/hive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:roomie/data/models/sms_transaction_model.dart';

class LocalSmsTransactionStore {
  static final LocalSmsTransactionStore _instance = LocalSmsTransactionStore._internal();
  factory LocalSmsTransactionStore() => _instance;
  LocalSmsTransactionStore._internal();

  static const _secureKeyName = 'hive_sms_tx_key_v1';
  static const _boxName = 'sms_transactions_box';

  final _controller = StreamController<List<SmsTransactionModel>>.broadcast();
  Box? _box;
  List<SmsTransactionModel> _cache = [];

  static bool _hiveInited = false;

  Future<void> init() async {
    if (!_hiveInited) {
      await Hive.initFlutter();
      _hiveInited = true;
    }
    // Acquire / generate encryption key
    final secureStorage = const FlutterSecureStorage();
    String? encodedKey = await secureStorage.read(key: _secureKeyName);
    List<int> encryptionKey;
    if (encodedKey == null) {
      final keyBytes = List<int>.generate(32, (i) => (DateTime.now().microsecondsSinceEpoch + i) % 256);
      encodedKey = keyBytes.join(',');
      await secureStorage.write(key: _secureKeyName, value: encodedKey);
      encryptionKey = keyBytes;
    } else {
      encryptionKey = encodedKey.split(',').map(int.parse).toList();
    }
    _box = await Hive.openBox(_boxName, encryptionCipher: HiveAesCipher(encryptionKey));
    _loadCache();
  }

  void _loadCache() {
    if (_box == null) return;
    _cache = _box!.values
        .whereType<Map>()
        .map((raw) => SmsTransactionModel.fromMap(Map<String, dynamic>.from(raw)))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _controller.add(List.unmodifiable(_cache));
  }

  Future<void> saveAll(List<SmsTransactionModel> transactions) async {
    if (_box == null) return;
    final batchMap = <String, Map<String, dynamic>>{};
    for (final t in transactions) {
      batchMap[t.id] = t.toMap();
    }
    await _box!.putAll(batchMap);
    _loadCache();
  }

  List<SmsTransactionModel> getUser(String userId) {
    return _cache.where((t) => t.userId == userId).toList();
  }

  Stream<List<SmsTransactionModel>> watchUser(String userId) {
    return _controller.stream.map((all) => all.where((t) => t.userId == userId).toList());
  }
}
