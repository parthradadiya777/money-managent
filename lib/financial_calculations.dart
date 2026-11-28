DateTime? parseAccountingDate(Map row) {
  for (final key in ['Date', 'Payment Date', 'Month']) {
    final value = '${row[key] ?? ''}'.trim();
    if (value.isEmpty || value.toLowerCase().contains('not detected')) continue;
    final normalized = RegExp(r'^\d{4}-\d{2}.hasMatch(value) ? '$value-01' : value;
    final parsed = DateTime.tryParse(normalized);
    if (parsed != null) return parsed;
  }
  return null;
}

int financialYearStart(DateTime date) => date.month >= 4 ? date.year : date.year - 1;

DateTime accountingPeriodStart(int financialYear, int month) {
  if (month == 0) return DateTime(financialYear, 4, 1);
  if (month < 1 || month > 12) throw ArgumentError.value(month, 'month');
  return DateTime(financialYear + (month >= 4 ? 0 : 1), month, 1);
}

num accountingTotal(Iterable<Map> records, String field) {
  return records.fold<num>(0, (total, row) {
    final raw = '${row[field] ?? 0}'.replaceAll(',', '').trim();
    return total + (num.tryParse(raw) ?? 0);
  });
}

String accountingAccountName(Map row, {String key = 'Account Name'}) {
  final name = '${row[key] ?? row['Bank Account'] ?? ''}'.trim();
  return name.isEmpty ? 'Unassigned (legacy records)' : name;
}

List<Map<String, dynamic>> calculateAccountLedgers({
  required Iterable<Map> openingBalances,
  required Iterable<Map> bankReceipts,
  required Iterable<Map> vendorPayments,
  required Iterable<Map> expenses,
  required DateTime periodStart,
  required DateTime periodEndExclusive,
}) {
  final names = <String>{};
  for (final row in openingBalances) names.add(accountingAccountName(row));
  for (final row in bankReceipts) names.add(accountingAccountName(row));
  for (final row in vendorPayments) names.add(accountingAccountName(row, key: 'Payment Account'));
  for (final row in expenses) names.add(accountingAccountName(row, key: 'Payment Account'));
  if (names.isEmpty) return [];
  final result = <Map<String, dynamic>>[];
  for (final name in names.toList()..sort()) {
    final openingRows = openingBalances.where((row) {
      final date = parseAccountingDate(row);
      return accountingAccountName(row) == name && date != null && !date.isAfter(periodStart);
    });
    bool prior(Map row) {
      final date = parseAccountingDate(row);
      return accountingAccountName(row, key: row.containsKey('Payment Account') ? 'Payment Account' : 'Account Name') == name &&
          date != null && date.isBefore(periodStart);
    }
    bool inPeriod(Map row) {
      final date = parseAccountingDate(row);
      return accountingAccountName(row, key: row.containsKey('Payment Account') ? 'Payment Account' : 'Account Name') == name &&
          date != null && !date.isBefore(periodStart) && date.isBefore(periodEndExclusive);
    }
    final opening = accountingTotal(openingRows, 'Opening Balance') +
        accountingTotal(bankReceipts.where(prior), 'Amount') -
        accountingTotal(vendorPayments.where(prior), 'Amount') -
        accountingTotal(expenses.where(prior), 'Expense');
    final receipts = accountingTotal(bankReceipts.where(inPeriod), 'Amount');
    final payments = accountingTotal(vendorPayments.where(inPeriod), 'Amount');
    final spent = accountingTotal(expenses.where(inPeriod), 'Expense');
    result.add({
      'Account Name': name,
      'Opening Balance': opening,
      'Receipts': receipts,
      'Vendor Payments': payments,
      'Expenses': spent,
      'Closing Balance': opening + receipts - payments - spent,
    });
  }
  return result;
}

num calculateOpeningCashBalance({
  required Iterable<Map> openingBalances,
  required Iterable<Map> bankReceipts,
  required Iterable<Map> vendorPayments,
  required Iterable<Map> expenses,
  required DateTime periodStart,
}) {
  final end = periodStart.month == 4 && periodStart.day == 1
      ? DateTime(periodStart.year + 1, 4, 1)
      : DateTime(periodStart.year, periodStart.month + 1, 1);
  return calculateAccountLedgers(
    openingBalances: openingBalances,
    bankReceipts: bankReceipts,
    vendorPayments: vendorPayments,
    expenses: expenses,
    periodStart: periodStart,
    periodEndExclusive: end,
  ).fold<num>(0, (sum, row) => sum + (row['Opening Balance'] as num));
}
).hasMatch(value) ? '$value-01' : value;
    final parsed = DateTime.tryParse(normalized);
    if (parsed != null) return parsed;
  }
  return null;
}

int financialYearStart(DateTime date) => date.month >= 4 ? date.year : date.year - 1;

DateTime accountingPeriodStart(int financialYear, int month) {
  if (month == 0) return DateTime(financialYear, 4, 1);
  if (month < 1 || month > 12) throw ArgumentError.value(month, 'month');
  return DateTime(financialYear + (month >= 4 ? 0 : 1), month, 1);
}

num accountingTotal(Iterable<Map> records, String field) {
  return records.fold<num>(0, (total, row) {
    final raw = '${row[field] ?? 0}'.replaceAll(',', '').trim();
    return total + (num.tryParse(raw) ?? 0);
  });
}

String accountingAccountName(Map row, {String key = 'Account Name'}) {
  final name = '${row[key] ?? row['Bank Account'] ?? ''}'.trim();
  return name.isEmpty ? 'Unassigned (legacy records)' : name;
}

List<Map<String, dynamic>> calculateAccountLedgers({
  required Iterable<Map> openingBalances,
  required Iterable<Map> bankReceipts,
  required Iterable<Map> vendorPayments,
  required Iterable<Map> expenses,
  required DateTime periodStart,
  required DateTime periodEndExclusive,
}) {
  final names = <String>{};
  for (final row in openingBalances) names.add(accountingAccountName(row));
  for (final row in bankReceipts) names.add(accountingAccountName(row));
  for (final row in vendorPayments) names.add(accountingAccountName(row, key: 'Payment Account'));
  for (final row in expenses) names.add(accountingAccountName(row, key: 'Payment Account'));
  if (names.isEmpty) return [];
  final result = <Map<String, dynamic>>[];
  for (final name in names.toList()..sort()) {
    final openingRows = openingBalances.where((row) {
      final date = parseAccountingDate(row);
      return accountingAccountName(row) == name && date != null && !date.isAfter(periodStart);
    });
    bool prior(Map row) {
      final date = parseAccountingDate(row);
      return accountingAccountName(row, key: row.containsKey('Payment Account') ? 'Payment Account' : 'Account Name') == name &&
          date != null && date.isBefore(periodStart);
    }
    bool inPeriod(Map row) {
      final date = parseAccountingDate(row);
      return accountingAccountName(row, key: row.containsKey('Payment Account') ? 'Payment Account' : 'Account Name') == name &&
          date != null && !date.isBefore(periodStart) && date.isBefore(periodEndExclusive);
    }
    final opening = accountingTotal(openingRows, 'Opening Balance') +
        accountingTotal(bankReceipts.where(prior), 'Amount') -
        accountingTotal(vendorPayments.where(prior), 'Amount') -
        accountingTotal(expenses.where(prior), 'Expense');
    final receipts = accountingTotal(bankReceipts.where(inPeriod), 'Amount');
    final payments = accountingTotal(vendorPayments.where(inPeriod), 'Amount');
    final spent = accountingTotal(expenses.where(inPeriod), 'Expense');
    result.add({
      'Account Name': name,
      'Opening Balance': opening,
      'Receipts': receipts,
      'Vendor Payments': payments,
      'Expenses': spent,
      'Closing Balance': opening + receipts - payments - spent,
    });
  }
  return result;
}

num calculateOpeningCashBalance({
  required Iterable<Map> openingBalances,
  required Iterable<Map> bankReceipts,
  required Iterable<Map> vendorPayments,
  required Iterable<Map> expenses,
  required DateTime periodStart,
}) {
  final end = periodStart.month == 4 && periodStart.day == 1
      ? DateTime(periodStart.year + 1, 4, 1)
      : DateTime(periodStart.year, periodStart.month + 1, 1);
  return calculateAccountLedgers(
    openingBalances: openingBalances,
    bankReceipts: bankReceipts,
    vendorPayments: vendorPayments,
    expenses: expenses,
    periodStart: periodStart,
    periodEndExclusive: end,
  ).fold<num>(0, (sum, row) => sum + (row['Opening Balance'] as num));
}
