import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';
import 'package:roomie/data/models/sms_transaction_model.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:roomie/data/datasources/local_sms_transaction_store.dart';

class SmsTransactionService {
  static final SmsTransactionService _instance = SmsTransactionService._internal();
  factory SmsTransactionService() => _instance;
  SmsTransactionService._internal();

  final Telephony telephony = Telephony.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  // Privacy configuration: if false, rawMessage is hashed before save.
  bool storePlainRawMessage = false;
  bool persistRemoteTransactions = false; // user can opt-in to cloud storage

  // Simple in-memory cache to speed access before Firestore stream delivers.
  final Map<String, SmsTransactionModel> _memoryCache = {};

  void setStorePlainRawMessage(bool value) {
    storePlainRawMessage = value;
  }
  void setPersistRemoteTransactions(bool value) {
    persistRemoteTransactions = value;
  }

  // Common SMS sender IDs for banks and payment apps
  static const List<String> _transactionSenders = [
    // Banks
    'HDFCBK', 'ICICIB', 'SBIIN', 'SBIBNK', 'SBIUPI', 'AXISNB', 'AXISBK', 'PNBSMS', 'BOISMS', 'CNRBBK',
    'UNIONB', 'KTKBNK', 'YESBNK', 'INDUSB', 'SCBANK', 'CITI', 'HSBC', 'IDFCFB', 'KOTAKB', 'FEDBNK', 'BOBARB',
    // UPI Apps
    'PAYTM', 'PHONEPE', 'GPAY', 'BHIMUPI', 'AMAZONP', 'MOBIKW',
    // Payment Gateways
    'RAZORP', 'PAYUBZ', 'CCAVEN', 'INSTAM',
  ];

  /// Request SMS permission
  Future<bool> requestSmsPermission() async {
    if (kIsWeb) return false; // SMS not available on web

    try {
      final status = await Permission.sms.request();
      return status.isGranted;
    } catch (e) {
      debugPrint('Error requesting SMS permission: $e');
      return false;
    }
  }

  /// Check if SMS permission is granted
  Future<bool> hasSmsPermission() async {
    if (kIsWeb) return false;

    try {
      return await Permission.sms.isGranted;
    } catch (e) {
      debugPrint('Error checking SMS permission: $e');
      return false;
    }
  }

  /// Read SMS messages and extract transactions
  Future<List<SmsTransactionModel>> readSmsTransactions({
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    if (kIsWeb) return [];

    final user = _authService.currentUser;
    if (user == null) return [];

    try {
      final hasPermission = await hasSmsPermission();
      if (!hasPermission) {
        debugPrint('SMS permission not granted');
        return [];
      }

      // Get SMS messages
      final messages = await telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      final transactions = <SmsTransactionModel>[];

      for (final sms in messages) {
        // Filter by sender OR by content heuristics
        final sender = sms.address ?? '';
        final body = sms.body ?? '';
        if (!_isTransactionSender(sender) && !_looksLikeTransactionMessage(body)) continue;

        // Filter by date
        final smsDate = DateTime.fromMillisecondsSinceEpoch(sms.date ?? 0);
        if (fromDate != null && smsDate.isBefore(fromDate)) continue;
        if (toDate != null && smsDate.isAfter(toDate)) continue;

        // Parse transaction from SMS body
        final transaction = _parseSmsTransaction(
          body,
          smsDate,
          sender,
          user.uid,
        );

        if (transaction != null) {
          transactions.add(transaction);
        }
      }

      return transactions;
    } catch (e) {
      debugPrint('Error reading SMS transactions: $e');
      return [];
    }
  }

  /// Check if sender is a transaction sender
  bool _isTransactionSender(String sender) {
    final normalizedSender = sender.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    return _transactionSenders.any((s) => normalizedSender.contains(s));
  }

  /// Heuristic: message looks like a transaction even if sender is unknown
  bool _looksLikeTransactionMessage(String message) {
    final upper = message.toUpperCase();
    final hasAmount = _extractAmount(message) != null;
    final hasTxnKeyword = upper.contains('DEBIT') || upper.contains('DEBITED') || upper.contains('CREDIT') ||
        upper.contains('CREDITED') || upper.contains('RECEIVED') || upper.contains('PAID') ||
        upper.contains('PAYMENT') || upper.contains('PURCHASE') || upper.contains('SPENT') ||
        upper.contains('WITHDRAWN') || upper.contains('UPI') || upper.contains('NEFT') ||
        upper.contains('IMPS') || upper.contains('RTGS') || upper.contains('UTR') || upper.contains('RRN');
    return hasAmount && hasTxnKeyword;
  }

  /// Parse SMS message to extract transaction details
  SmsTransactionModel? _parseSmsTransaction(
    String message,
    DateTime timestamp,
    String sender,
    String userId,
  ) {
    try {
      final upperMessage = message.toUpperCase();

      // Determine transaction type
      TransactionType? type;
      if (upperMessage.contains('DEBITED') ||
          upperMessage.contains('DEBIT ') ||
          upperMessage.contains('SPENT') ||
          upperMessage.contains('PAID') ||
          upperMessage.contains('PURCHASE') ||
          upperMessage.contains('WITHDRAWN') ||
          upperMessage.contains('SENT') ||
          upperMessage.contains('TXN DEBIT')) {
        type = TransactionType.debit;
      } else if (upperMessage.contains('CREDITED') ||
                 upperMessage.contains('CREDIT ') ||
                 upperMessage.contains('RECEIVED') ||
                 upperMessage.contains('DEPOSITED') ||
                 upperMessage.contains('TXN CREDIT')) {
        type = TransactionType.credit;
      }

      if (type == null) return null;

      // Extract amount
      final amount = _extractAmount(message);
      if (amount == null || amount <= 0) return null;

      // Extract other details
      final merchantName = _extractMerchantName(message);
      final bankName = _extractBankName(message);
      final upiId = _extractUpiId(message);
      final mode = _extractTransactionMode(message);
      final accountNumber = _extractAccountNumber(message);
      final referenceNumber = _extractReferenceNumber(message);
      final category = _categorizeTransaction(merchantName, message);

      final model = SmsTransactionModel(
        id: '${timestamp.millisecondsSinceEpoch}_${sender}_${_shortFingerprint(message)}',
        userId: userId,
        type: type,
        amount: amount,
        timestamp: timestamp,
        merchantName: merchantName,
        bankName: bankName,
        upiId: upiId,
        mode: mode,
        accountNumber: accountNumber,
        referenceNumber: referenceNumber,
        rawMessage: storePlainRawMessage ? message : _hashMessage(message),
        category: category,
        senderNumber: sender,
      );
      _memoryCache[model.id] = model;
      return model;
    } catch (e) {
      debugPrint('Error parsing SMS transaction: $e');
      return null;
    }
  }

  /// Extract amount from SMS
  double? _extractAmount(String message) {
    // Patterns: Rs.1,234.56 | Rs 1,234.5 | INR 1234 | ₹1,234.00
    final patterns = [
      RegExp(r'(?:RS\.?|INR|₹)\s?(\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?)', caseSensitive: false),
      RegExp(r'(\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?)\s?(?:RS|INR|₹)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(message);
      if (match != null) {
        final amountStr = match.group(1)?.replaceAll(',', '');
        return double.tryParse(amountStr ?? '');
      }
    }

    return null;
  }

  /// Extract merchant/payee name
  String? _extractMerchantName(String message) {
    // Patterns: "to MERCHANT", "at MERCHANT", "from MERCHANT", "via MERCHANT", "by MERCHANT"
    final patterns = [
      RegExp(r'(?:to|at|via|by)\s+([A-Za-z0-9&\-\.\s]{2,40})', caseSensitive: false),
      RegExp(r'from\s+([A-Za-z0-9&\-\.\s]{2,40})', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(message);
      if (match != null) {
        return match.group(1)?.trim();
      }
    }

    return null;
  }

  /// Extract bank name
  String? _extractBankName(String message) {
    final banks = ['HDFC', 'ICICI', 'SBI', 'AXIS', 'PNB', 'BOI', 'CANARA', 'UNION', 'KOTAK', 'YES', 'INDUSIND', 'IDFC', 'FEDERAL', 'BOB', 'CITI', 'HSBC'];
    
    for (final bank in banks) {
      if (message.toUpperCase().contains(bank)) {
        return bank;
      }
    }

    return null;
  }

  /// Extract UPI ID
  String? _extractUpiId(String message) {
    final pattern = RegExp(r'([a-zA-Z0-9.\-_]+@[a-zA-Z]+)');
    final match = pattern.firstMatch(message);
    return match?.group(1);
  }

  /// Extract transaction mode
  TransactionMode _extractTransactionMode(String message) {
    final upper = message.toUpperCase();
    
    if (upper.contains('UPI')) return TransactionMode.upi;
    if (upper.contains('CARD') || upper.contains('DEBIT CARD') || upper.contains('CREDIT CARD')) {
      return TransactionMode.card;
    }
    if (upper.contains('NEFT') || upper.contains('IMPS') || upper.contains('RTGS')) {
      return TransactionMode.netBanking;
    }
    if (upper.contains('ATM') || upper.contains('CASH')) return TransactionMode.cash;

    return TransactionMode.unknown;
  }

  /// Extract account number (last 4 digits)
  String? _extractAccountNumber(String message) {
    final pattern = RegExp(r'A/C\s?\*+(\d{4})|\*+(\d{4})', caseSensitive: false);
    final match = pattern.firstMatch(message);
    return match?.group(1) ?? match?.group(2);
  }

  /// Extract reference/transaction number
  String? _extractReferenceNumber(String message) {
    final pattern = RegExp(r'(?:REF(?:ERENCE)?|UPI|TXN|UTR|RRN)\s?(?:NO\.?|ID\.?|#)?\s?:?\s?([A-Z0-9\-]{6,30})', caseSensitive: false);
    final match = pattern.firstMatch(message);
    return match?.group(1);
  }

  /// Auto-categorize transaction
  String? _categorizeTransaction(String? merchantName, String message) {
    if (merchantName == null) return null;

    final upper = merchantName.toUpperCase();
    final messageUpper = message.toUpperCase();

    // Food & Dining
    if (upper.contains('ZOMATO') || upper.contains('SWIGGY') || 
        upper.contains('UBER EATS') || upper.contains('RESTAURANT') ||
        messageUpper.contains('FOOD')) {
      return 'Food & Dining';
    }

    // Shopping
    if (upper.contains('AMAZON') || upper.contains('FLIPKART') || 
        upper.contains('MYNTRA') || upper.contains('AJIO') ||
        messageUpper.contains('SHOPPING')) {
      return 'Shopping';
    }

    // Transportation
    if (upper.contains('UBER') || upper.contains('OLA') || 
        upper.contains('RAPIDO') || messageUpper.contains('PETROL') ||
        messageUpper.contains('FUEL')) {
      return 'Transportation';
    }

    // Utilities
    if (messageUpper.contains('ELECTRICITY') || messageUpper.contains('WATER') ||
        messageUpper.contains('GAS') || messageUpper.contains('RECHARGE')) {
      return 'Utilities';
    }

    // Entertainment
    if (upper.contains('NETFLIX') || upper.contains('PRIME') ||
        upper.contains('HOTSTAR') || upper.contains('SPOTIFY')) {
      return 'Entertainment';
    }

    return 'Other';
  }

  /// Save transactions to Firestore
  Future<void> saveSmsTransactions(List<SmsTransactionModel> transactions) async {
    try {
      final batch = _firestore.batch();

      for (final transaction in transactions) {
        final docRef = _firestore
            .collection('users')
            .doc(transaction.userId)
            .collection('sms_transactions')
            .doc(transaction.id);
        batch.set(docRef, transaction.toMap(), SetOptions(merge: true));
        _memoryCache[transaction.id] = transaction;
      }
      // Always save locally
      await LocalSmsTransactionStore().saveAll(transactions);
      if (persistRemoteTransactions) {
        await batch.commit();
        debugPrint('✅ Saved ${transactions.length} SMS transactions (remote + local)');
      } else {
        debugPrint('💾 Saved ${transactions.length} SMS transactions locally (remote disabled)');
      }
    } catch (e) {
      debugPrint('❌ Error saving SMS transactions: $e');
    }
  }

  /// Get user's SMS transactions from Firestore
  Stream<List<SmsTransactionModel>> getUserSmsTransactions(String userId) {
    // If remote persistence disabled, stream directly from local store
    if (!persistRemoteTransactions) {
      // ensure local cache has been initialized
      return LocalSmsTransactionStore().watchUser(userId);
    }
    // Emit memory cache first (if any) then Firestore stream
    final controller = StreamController<List<SmsTransactionModel>>();
    // Initial emit from cache filtered by userId
    final initial = _memoryCache.values.where((m) => m.userId == userId).toList()
      ..sort((a,b)=> b.timestamp.compareTo(a.timestamp));
    controller.add(initial);

    _firestore
        .collection('users')
        .doc(userId)
        .collection('sms_transactions')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => SmsTransactionModel.fromMap(doc.data()))
              .toList();
        })
        .listen((remoteList) {
          for (final t in remoteList) {
            _memoryCache[t.id] = t;
          }
          controller.add(remoteList);
        });

    return controller.stream;
  }

  /// Sync SMS transactions (read and save)
  Future<int> syncSmsTransactions({DateTime? fromDate}) async {
    final transactions = await readSmsTransactions(fromDate: fromDate);
    if (transactions.isNotEmpty) {
      await saveSmsTransactions(transactions);
    }
    return transactions.length;
  }

  // Create a short stable-ish fingerprint of message content
  String _shortFingerprint(String input) {
    int sum = 0;
    for (final code in input.codeUnits) {
      sum = (sum * 131 + code) & 0x7fffffff;
    }
    return (sum % 100000000).toString();
  }

  String _hashMessage(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
