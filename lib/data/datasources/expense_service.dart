import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:roomie/data/models/expense_model.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/data/datasources/cloudinary_service.dart';
import 'package:roomie/data/datasources/firestore_service.dart';

class ExpenseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  final CloudinaryService _cloudinaryService = CloudinaryService();
  final FirestoreService _firestoreService = FirestoreService();

  static const String _collection = 'expenses';

  // Create a new expense
  Future<String?> createExpense({
    required String title,
    required String description,
    required double amount,
    required ExpenseType type,
    required String groupId,
    required List<String> participantIds,
    DateTime? dueDate,
    File? receiptImage,
    XFile? webReceiptImage,
    Map<String, double>? customSplitAmounts, // If null, split equally
  }) async {
    try {
      final user = _authService.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Get user details
      final userDetails = await _firestoreService.getUserDetails(user.uid);
      final userName = userDetails?['username'] ?? 'Unknown User';

      // Upload receipt if provided
      String? receiptUrl;
      if (receiptImage != null) {
        receiptUrl = await _cloudinaryService.uploadFile(
          file: receiptImage,
          folder: CloudinaryFolder.other,
        );
      } else if (webReceiptImage != null && kIsWeb) {
        final bytes = await webReceiptImage.readAsBytes();
        receiptUrl = await _cloudinaryService.uploadBytes(
          bytes: bytes,
          fileName: webReceiptImage.name,
          folder: CloudinaryFolder.other,
        );
      }

      // Calculate split amounts
      Map<String, double> splitAmounts;
      if (customSplitAmounts != null) {
        splitAmounts = customSplitAmounts;
      } else {
        // Equal split
        final amountPerPerson = amount / participantIds.length;
        splitAmounts = {for (String id in participantIds) id: amountPerPerson};
      }

      // Initialize payment status (all false initially)
      final paymentStatus = {for (String id in participantIds) id: false};

      final expense = ExpenseModel(
        id: '', // Will be set by Firestore
        title: title,
        description: description,
        amount: amount,
        type: type,
        status: ExpenseStatus.pending,
        groupId: groupId,
        createdBy: user.uid,
        createdByName: userName,
        participants: participantIds,
        splitAmounts: splitAmounts,
        paymentStatus: paymentStatus,
        createdAt: DateTime.now(),
        dueDate: dueDate,
        receiptUrl: receiptUrl,
      );

      final docRef = await _firestore
          .collection(_collection)
          .add(expense.toFirestore());
      print('✅ Expense created with ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ Error creating expense: $e');
      rethrow;
    }
  }

  // Get expenses for a group
  Stream<List<ExpenseModel>> getGroupExpenses(String groupId) {
    return _firestore
        .collection(_collection)
        .where('groupId', isEqualTo: groupId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .map((doc) => ExpenseModel.fromFirestore(doc))
                  .toList(),
        );
  }

  // Get expenses where user is a participant
  Stream<List<ExpenseModel>> getUserExpenses(String userId) {
    return _firestore
        .collection(_collection)
        .where('participants', arrayContains: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .map((doc) => ExpenseModel.fromFirestore(doc))
                  .toList(),
        );
  }

  // Mark expense as paid by a user
  Future<void> markAsPaid(String expenseId, String userId) async {
    try {
      await _firestore.collection(_collection).doc(expenseId).update({
        'paymentStatus.$userId': true,
      });
      print('✅ Marked expense $expenseId as paid by $userId');
    } catch (e) {
      print('❌ Error marking expense as paid: $e');
      rethrow;
    }
  }

  // Mark expense as unpaid by a user
  Future<void> markAsUnpaid(String expenseId, String userId) async {
    try {
      await _firestore.collection(_collection).doc(expenseId).update({
        'paymentStatus.$userId': false,
      });
      print('✅ Marked expense $expenseId as unpaid by $userId');
    } catch (e) {
      print('❌ Error marking expense as unpaid: $e');
      rethrow;
    }
  }

  // Update expense status
  Future<void> updateExpenseStatus(
    String expenseId,
    ExpenseStatus status,
  ) async {
    try {
      await _firestore.collection(_collection).doc(expenseId).update({
        'status': status.toString(),
      });
      print('✅ Updated expense $expenseId status to $status');
    } catch (e) {
      print('❌ Error updating expense status: $e');
      rethrow;
    }
  }

  // Delete expense
  Future<void> deleteExpense(String expenseId) async {
    try {
      await _firestore.collection(_collection).doc(expenseId).delete();
      print('✅ Deleted expense $expenseId');
    } catch (e) {
      print('❌ Error deleting expense: $e');
      rethrow;
    }
  }

  // Calculate user balances for a group
  Future<List<UserBalance>> calculateGroupBalances(String groupId) async {
    try {
      final expenses =
          await _firestore
              .collection(_collection)
              .where('groupId', isEqualTo: groupId)
              .where('status', isEqualTo: ExpenseStatus.pending.toString())
              .get();

      final Map<String, UserBalance> balances = {};

      for (final doc in expenses.docs) {
        final expense = ExpenseModel.fromFirestore(doc);

        for (final participantId in expense.participants) {
          final owedAmount = expense.splitAmounts[participantId] ?? 0.0;
          final hasPaid = expense.paymentStatus[participantId] ?? false;
          final paidAmount = hasPaid ? owedAmount : 0.0;

          if (balances.containsKey(participantId)) {
            final current = balances[participantId]!;
            balances[participantId] = UserBalance(
              userId: participantId,
              userName: current.userName,
              totalOwed: current.totalOwed + owedAmount,
              totalPaid: current.totalPaid + paidAmount,
              netBalance: current.netBalance,
            );
          } else {
            // Get user name
            final userDetails = await _firestoreService.getUserDetails(
              participantId,
            );
            final userName = userDetails?['username'] ?? 'Unknown User';

            balances[participantId] = UserBalance(
              userId: participantId,
              userName: userName,
              totalOwed: owedAmount,
              totalPaid: paidAmount,
              netBalance: 0.0, // Will calculate after
            );
          }
        }
      }

      // Calculate net balances
      final balanceList =
          balances.values.map((balance) {
            final netBalance = balance.totalPaid - balance.totalOwed;
            return UserBalance(
              userId: balance.userId,
              userName: balance.userName,
              totalOwed: balance.totalOwed,
              totalPaid: balance.totalPaid,
              netBalance: netBalance,
            );
          }).toList();

      return balanceList;
    } catch (e) {
      print('❌ Error calculating group balances: $e');
      rethrow;
    }
  }

  // Get single expense by ID
  Future<ExpenseModel?> getExpenseById(String expenseId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(expenseId).get();
      if (doc.exists) {
        return ExpenseModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('❌ Error getting expense by ID: $e');
      return null;
    }
  }

  // Get expenses summary for dashboard
  Future<Map<String, dynamic>> getExpensesSummary(String groupId) async {
    try {
      final snapshot =
          await _firestore
              .collection(_collection)
              .where('groupId', isEqualTo: groupId)
              .get();

      double totalExpenses = 0.0;
      double pendingAmount = 0.0;
      double paidAmount = 0.0;
      int totalExpenseCount = snapshot.docs.length;
      int pendingCount = 0;

      for (final doc in snapshot.docs) {
        final expense = ExpenseModel.fromFirestore(doc);
        totalExpenses += expense.amount;

        if (expense.status == ExpenseStatus.pending) {
          pendingCount++;
          pendingAmount += expense.getTotalPending();
          paidAmount += expense.getTotalPaid();
        }
      }

      return {
        'totalExpenses': totalExpenses,
        'pendingAmount': pendingAmount,
        'paidAmount': paidAmount,
        'totalExpenseCount': totalExpenseCount,
        'pendingCount': pendingCount,
        'completedCount': totalExpenseCount - pendingCount,
      };
    } catch (e) {
      print('❌ Error getting expenses summary: $e');
      return {
        'totalExpenses': 0.0,
        'pendingAmount': 0.0,
        'paidAmount': 0.0,
        'totalExpenseCount': 0,
        'pendingCount': 0,
        'completedCount': 0,
      };
    }
  }
}
