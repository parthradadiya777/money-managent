DateTime? parseAccountingDate(Map row) {
  for (final key in ['Date', 'Payment Date', 'Month']) {
    final value = '${row[key] ?? ''}'.trim();
    if (value.isEmpty || value.toLowerCase().contains('not detected')) continue;
    final normalized = RegExp(r'^\d{4}-\d{2}$').hasMatch(value) ? '$value-01' : value;
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

num calculateOpeningCashBalance({
  required Iterable<Map> openingBalances,
  required Iterable<Map> bankReceipts,
  required Iterable<Map> vendorPayments,
  required Iterable<Map> expenses,
  required DateTime periodStart,
}) {
  final opening = openingBalances.where((row) {
    final date = parseAccountingDate(row);
    return date != null && !date.isAfter(periodStart);
  });
  bool beforePeriod(Map row) {
    final date = parseAccountingDate(row);
    return date != null && date.isBefore(periodStart);
  }
  return accountingTotal(opening, 'Opening Balance') +
      accountingTotal(bankReceipts.where(beforePeriod), 'Amount') -
      accountingTotal(vendorPayments.where(beforePeriod), 'Amount') -
      accountingTotal(expenses.where(beforePeriod), 'Expense');
}
