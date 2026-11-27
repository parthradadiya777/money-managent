import 'package:flutter_test/flutter_test.dart';
import 'package:moneymanagement/financial_calculations.dart';

void main() {
  group('Accounting date and financial year', () {
    test('parses YYYY-MM month values', () {
      expect(parseAccountingDate({'Month': '2026-11'}), DateTime(2026, 11, 1));
    });
    test('maps March to previous financial year', () {
      expect(financialYearStart(DateTime(2027, 3, 31)), 2026);
    });
    test('maps April to new financial year', () {
      expect(financialYearStart(DateTime(2027, 4, 1)), 2027);
    });
    test('monthly period starts in correct calendar year', () {
      expect(accountingPeriodStart(2026, 11), DateTime(2026, 11, 1));
      expect(accountingPeriodStart(2026, 2), DateTime(2027, 2, 1));
    });
  });
  group('Financial totals', () {
    test('parses comma-separated amounts', () {
      expect(accountingTotal([
        {'Amount': '1,25,000'}, {'Amount': '250.50'}, {'Amount': 'invalid'},
      ], 'Amount'), 125250.50);
    });
    test('carries opening cash forward using prior-period movements only', () {
      final result = calculateOpeningCashBalance(
        openingBalances: [
          {'Date': '2026-04-01', 'Opening Balance': '10,000'},
          {'Date': '2026-11-01', 'Opening Balance': '500'},
        ],
        bankReceipts: [
          {'Date': '2026-10-31', 'Amount': '2,000'},
          {'Date': '2026-11-01', 'Amount': '9,000'},
        ],
        vendorPayments: [{'Date': '2026-10-15', 'Amount': '1,000'}],
        expenses: [{'Date': '2026-10-20', 'Expense': '500'}],
        periodStart: DateTime(2026, 11, 1),
      );
      expect(result, 11500);
    });
  });
}
