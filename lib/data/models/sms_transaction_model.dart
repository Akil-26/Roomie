import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionType {
  debit,  // Money sent/spent
  credit, // Money received
}

enum TransactionMode {
  upi,
  card,
  netBanking,
  cash,
  unknown,
}

class SmsTransactionModel {
  final String id;
  final String userId;
  final TransactionType type;
  final double amount;
  final DateTime timestamp;
  final String? merchantName;
  final String? bankName;
  final String? upiId;
  final TransactionMode mode;
  final String? accountNumber; // Last 4 digits
  final String? referenceNumber;
  final String rawMessage; // Original SMS text
  final String? category; // Auto-categorized or user-set
  final String senderNumber; // SMS sender ID

  SmsTransactionModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.timestamp,
    this.merchantName,
    this.bankName,
    this.upiId,
    this.mode = TransactionMode.unknown,
    this.accountNumber,
    this.referenceNumber,
    required this.rawMessage,
    this.category,
    required this.senderNumber,
  });

  // Convert to Firestore map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'type': type.name,
      'amount': amount,
      'timestamp': Timestamp.fromDate(timestamp),
      'merchantName': merchantName,
      'bankName': bankName,
      'upiId': upiId,
      'mode': mode.name,
      'accountNumber': accountNumber,
      'referenceNumber': referenceNumber,
      'rawMessage': rawMessage,
      'category': category,
      'senderNumber': senderNumber,
    };
  }

  // Create from Firestore map
  factory SmsTransactionModel.fromMap(Map<String, dynamic> map) {
    return SmsTransactionModel(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      type: TransactionType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => TransactionType.debit,
      ),
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      timestamp: (map['timestamp'] as Timestamp).toDate(),
      merchantName: map['merchantName'],
      bankName: map['bankName'],
      upiId: map['upiId'],
      mode: TransactionMode.values.firstWhere(
        (e) => e.name == map['mode'],
        orElse: () => TransactionMode.unknown,
      ),
      accountNumber: map['accountNumber'],
      referenceNumber: map['referenceNumber'],
      rawMessage: map['rawMessage'] ?? '',
      category: map['category'],
      senderNumber: map['senderNumber'] ?? '',
    );
  }

  // Create a copy with modified fields
  SmsTransactionModel copyWith({
    String? id,
    String? userId,
    TransactionType? type,
    double? amount,
    DateTime? timestamp,
    String? merchantName,
    String? bankName,
    String? upiId,
    TransactionMode? mode,
    String? accountNumber,
    String? referenceNumber,
    String? rawMessage,
    String? category,
    String? senderNumber,
  }) {
    return SmsTransactionModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      timestamp: timestamp ?? this.timestamp,
      merchantName: merchantName ?? this.merchantName,
      bankName: bankName ?? this.bankName,
      upiId: upiId ?? this.upiId,
      mode: mode ?? this.mode,
      accountNumber: accountNumber ?? this.accountNumber,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      rawMessage: rawMessage ?? this.rawMessage,
      category: category ?? this.category,
      senderNumber: senderNumber ?? this.senderNumber,
    );
  }

  String get displayName {
    return merchantName ?? upiId ?? bankName ?? 'Transaction';
  }

  String get modeDisplay {
    switch (mode) {
      case TransactionMode.upi:
        return 'UPI';
      case TransactionMode.card:
        return 'Card';
      case TransactionMode.netBanking:
        return 'Net Banking';
      case TransactionMode.cash:
        return 'Cash';
      default:
        return 'Unknown';
    }
  }
}
