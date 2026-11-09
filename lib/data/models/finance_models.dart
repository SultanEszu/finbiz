import 'dart:convert';

import 'package:flutter/material.dart';

class BusinessModel {
  const BusinessModel({
    required this.id,
    required this.ownerId,
    required this.businessName,
    required this.description,
  });

  final String id;
  final String ownerId;
  final String businessName;
  final String description;

  factory BusinessModel.fromJson(Map<String, dynamic> json) {
    return BusinessModel(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      businessName: json['business_name'] as String,
      description: json['description'] as String? ?? '',
    );
  }
}

class CashAccountModel {
  const CashAccountModel({
    required this.id,
    required this.businessId,
    required this.name,
    required this.accountType,
    required this.openingBalance,
    required this.isActive,
  });

  final String id;
  final String businessId;
  final String name;
  final String accountType;
  final double openingBalance;
  final bool isActive;

  factory CashAccountModel.fromJson(Map<String, dynamic> json) {
    return CashAccountModel(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      name: json['name'] as String,
      accountType: json['account_type'] as String,
      openingBalance: (json['opening_balance'] as num).toDouble(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

enum TransactionType { income, expense }

String transactionTypeLabel(TransactionType type) {
  switch (type) {
    case TransactionType.income:
      return 'Pemasukan';
    case TransactionType.expense:
      return 'Pengeluaran';
  }
}

TransactionType transactionTypeFromString(String value) {
  return value == 'income' ? TransactionType.income : TransactionType.expense;
}

class FinanceCategory {
  const FinanceCategory({
    required this.id,
    required this.name,
    required this.iconName,
    required this.colorValue,
    required this.isExpense,
  });

  final String id;
  final String name;
  final String iconName;
  final int colorValue;
  final bool isExpense;

  IconData get icon => _iconFromName(iconName);
  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'iconName': iconName,
    'colorValue': colorValue,
    'isExpense': isExpense,
  };

  factory FinanceCategory.fromJson(Map<String, dynamic> json) {
    return FinanceCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      iconName: json['iconName'] as String? ?? 'category',
      colorValue: json['colorValue'] as int? ?? Colors.blue.toARGB32(),
      isExpense: json['isExpense'] as bool? ?? true,
    );
  }
}

class FinanceTransaction {
  const FinanceTransaction({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.amount,
    required this.date,
    required this.type,
    required this.description,
  });

  final String id;
  final String title;
  final String categoryId;
  final double amount;
  final DateTime date;
  final TransactionType type;
  final String description;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'categoryId': categoryId,
    'amount': amount,
    'date': date.toIso8601String(),
    'type': type.name,
    'description': description,
  };

  factory FinanceTransaction.fromJson(Map<String, dynamic> json) {
    return FinanceTransaction(
      id: json['id'] as String,
      title: json['title'] as String,
      categoryId: json['categoryId'] as String,
      amount: (json['amount'] as num).toDouble(),
      date: DateTime.parse(json['date'] as String),
      type: transactionTypeFromString(json['type'] as String),
      description: json['description'] as String? ?? '',
    );
  }
}

class DebtEntry {
  const DebtEntry({
    required this.id,
    required this.name,
    required this.contact,
    required this.amount,
    required this.dueDate,
    required this.type,
    required this.description,
  });

  final String id;
  final String name;
  final String contact;
  final double amount;
  final DateTime dueDate;
  final DebtType type;
  final String description;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'contact': contact,
    'amount': amount,
    'dueDate': dueDate.toIso8601String(),
    'type': type.name,
    'description': description,
  };

  factory DebtEntry.fromJson(Map<String, dynamic> json) {
    return DebtEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      contact: json['contact'] as String? ?? '',
      amount: (json['amount'] as num).toDouble(),
      dueDate: DateTime.parse(json['dueDate'] as String),
      type: DebtType.values.firstWhere(
        (e) => e.name == (json['type'] as String),
        orElse: () => DebtType.payable,
      ),
      description: json['description'] as String? ?? '',
    );
  }
}

class FinanceBudget {
  const FinanceBudget({
    required this.id,
    required this.amount,
    required this.period,
    required this.startDate,
    required this.endDate,
  });

  final String id;
  final double amount;
  final String period;
  final DateTime startDate;
  final DateTime endDate;

  factory FinanceBudget.fromJson(Map<String, dynamic> json) {
    return FinanceBudget(
      id: json['id'] as String,
      amount: (json['amount'] as num).toDouble(),
      period: json['period'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
    );
  }
}

class FinanceNotification {
  const FinanceNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  factory FinanceNotification.fromJson(Map<String, dynamic> json) {
    return FinanceNotification(
      id: json['id'] as String,
      title: json['title'] as String,
      message: json['message'] as String? ?? '',
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class SavingsTarget {
  const SavingsTarget({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    this.targetDate,
  });

  final String id;
  final String name;
  final double targetAmount;
  final double currentAmount;
  final DateTime? targetDate;

  factory SavingsTarget.fromJson(Map<String, dynamic> json) {
    return SavingsTarget(
      id: json['id'] as String,
      name: json['target_name'] as String,
      targetAmount: (json['target_amount'] as num).toDouble(),
      currentAmount: (json['current_amount'] as num).toDouble(),
      targetDate: json['target_date'] == null
          ? null
          : DateTime.parse(json['target_date'] as String),
    );
  }
}

enum DebtType { payable, receivable }

String debtTypeLabel(DebtType type) {
  switch (type) {
    case DebtType.payable:
      return 'Hutang';
    case DebtType.receivable:
      return 'Piutang';
  }
}

IconData _iconFromName(String iconName) {
  switch (iconName) {
    case 'shopping_cart':
      return Icons.shopping_cart_outlined;
    case 'restaurant':
      return Icons.restaurant_outlined;
    case 'home':
      return Icons.home_outlined;
    case 'directions_car':
      return Icons.directions_car_outlined;
    case 'trending_up':
      return Icons.trending_up_outlined;
    case 'savings':
      return Icons.savings_outlined;
    case 'favorite':
      return Icons.favorite_outline;
    case 'credit_card':
      return Icons.credit_card_outlined;
    case 'local_hospital':
      return Icons.local_hospital_outlined;
    default:
      return Icons.category_outlined;
  }
}

String encodeJson(Map<String, dynamic> value) => jsonEncode(value);
