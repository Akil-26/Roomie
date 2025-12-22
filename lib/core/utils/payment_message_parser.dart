/// Utility class to parse payment requests from chat messages
class PaymentMessageParser {
  // Regex patterns to detect payment messages
  static final List<RegExp> _paymentPatterns = [
    // "send money $10", "send money ₹10", "send money 10"
    RegExp(r'send\s+money\s+(?:\$|₹|Rs\.?\s*)?(\d+(?:\.\d{1,2})?)', caseSensitive: false),
    // "pay $10", "pay me $10", "pay ₹10"
    RegExp(r'pay(?:\s+me)?\s+(?:\$|₹|Rs\.?\s*)?(\d+(?:\.\d{1,2})?)', caseSensitive: false),
    // "$10 please", "send $10", "₹10 please"
    RegExp(r'(?:send|give)\s+(?:\$|₹|Rs\.?\s*)(\d+(?:\.\d{1,2})?)', caseSensitive: false),
    // "₹100", "Rs 100", "Rs. 100"
    RegExp(r'(?:₹|Rs\.?)\s*(\d+(?:\.\d{1,2})?)', caseSensitive: false),
    // Direct amount mention with payment keywords
    RegExp(r'(?:need|want|request)\s+(?:\$|₹|Rs\.?\s*)?(\d+(?:\.\d{1,2})?)', caseSensitive: false),
  ];

  /// Check if a message contains a payment request
  static bool isPaymentMessage(String message) {
    if (message.trim().isEmpty) return false;
    
    for (final pattern in _paymentPatterns) {
      if (pattern.hasMatch(message)) {
        return true;
      }
    }
    return false;
  }

  /// Extract amount from payment message
  /// Returns null if no amount found
  static double? extractAmount(String message) {
    for (final pattern in _paymentPatterns) {
      final match = pattern.firstMatch(message);
      if (match != null && match.groupCount >= 1) {
        final amountStr = match.group(1);
        if (amountStr != null) {
          return double.tryParse(amountStr);
        }
      }
    }
    return null;
  }

  /// Extract description/note from payment message (everything except the amount)
  static String? extractDescription(String message) {
    double? amount = extractAmount(message);
    if (amount == null) return null;

    // Remove the payment amount part to get description
    String description = message;
    for (final pattern in _paymentPatterns) {
      description = description.replaceFirst(pattern, '').trim();
    }

    // Clean up extra spaces and punctuation
    description = description
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[,.\-:\s]+|[,.\-:\s]+$'), '')
        .trim();

    return description.isEmpty ? null : description;
  }

  /// Parse complete payment info from message
  static PaymentInfo? parsePaymentInfo(String message) {
    if (!isPaymentMessage(message)) return null;

    final amount = extractAmount(message);
    if (amount == null || amount <= 0) return null;

    final description = extractDescription(message);

    return PaymentInfo(
      amount: amount,
      description: description,
      originalMessage: message,
    );
  }

  /// Check if message mentions specific users (for group chats)
  /// Returns list of mentioned usernames (e.g., @username)
  static List<String> extractMentionedUsers(String message) {
    final mentionPattern = RegExp(r'@(\w+)');
    final matches = mentionPattern.allMatches(message);
    return matches.map((m) => m.group(1)!).toList();
  }
}

/// Data class to hold parsed payment information
class PaymentInfo {
  final double amount;
  final String? description;
  final String originalMessage;

  PaymentInfo({
    required this.amount,
    this.description,
    required this.originalMessage,
  });

  @override
  String toString() {
    return 'PaymentInfo(amount: \$$amount, description: $description)';
  }
}
