import 'package:flutter_test/flutter_test.dart';
import 'package:moneymanagement/financial_calculations.dart';

void main() {
  group('Accounting date and financial year', () {
    test('parses YYYY-MM month values', () => expect(parseAccountingDate({'Month':'2026-11'}), DateTime(2026,11,1)));
    test('maps March and April to correct financial years', () {
      expect(financialYearStart(DateTime(2027,3,31)), 2026);
      expect(financialYearStart(DateTime(2027,4,1)), 2027);
    });
    test('monthly period starts in correct calendar year', () {
      expect(accountingPeriodStart(2026,11), DateTime(2026,11,1));
      expect(accountingPeriodStart(2026,2), DateTime(2027,2,1));
    });
    test('parses comma-separated amounts', () {
      expect(accountingTotal([{'Amount':'1,25,000'},{'Amount':'250.50'},{'Amount':'invalid'}], 'Amount'), 125250.50);
    });
  });

  group('Account-wise reconciliation', () {
    final start = DateTime(2026,11,1), end = DateTime(2026,12,1);
    test('calculates separate bank and cash closing balances', () {
      final ledgers = calculateAccountLedgers(
        openingBalances: [
          {'Date':'2026-04-01','Account Type':'Bank','Account Name':'HDFC','Opening Balance':'10000'},
          {'Date':'2026-04-01','Account Type':'Cash','Account Name':'Cash','Opening Balance':'2000'},
        ],
        bankReceipts: [
          {'Date':'2026-11-03','Account Name':'HDFC','Amount':'5000'},
          {'Date':'2026-11-04','Account Name':'Cash','Amount':'300'},
        ],
        vendorPayments: [
          {'Date':'2026-11-05','Payment Account':'HDFC','Amount':'1000'},
        ],
        expenses: [
          {'Date':'2026-11-06','Payment Account':'Cash','Expense':'200'},
        ],
        periodStart:start, periodEndExclusive:end,
      );
      expect(ledgers, hasLength(2));
      final hdfc=ledgers.firstWhere((r)=>r['Account Name']=='HDFC');
      final cash=ledgers.firstWhere((r)=>r['Account Name']=='Cash');
      expect(hdfc['Opening Balance'],10000);
      expect(hdfc['Closing Balance'],14000);
      expect(cash['Closing Balance'],2100);
    });
    test('carries prior movements forward but excludes current-period movements', () {
      final ledgers=calculateAccountLedgers(
        openingBalances:[{'Date':'2026-04-01','Account Name':'SBI','Opening Balance':'1000'}],
        bankReceipts:[
          {'Date':'2026-10-31','Account Name':'SBI','Amount':'2000'},
          {'Date':'2026-11-01','Account Name':'SBI','Amount':'9000'},
        ],
        vendorPayments:[{'Date':'2026-10-15','Payment Account':'SBI','Amount':'500'}],
        expenses:[{'Date':'2026-10-20','Payment Account':'SBI','Expense':'100'}],
        periodStart:start,periodEndExclusive:end,
      );
      expect(ledgers.single['Opening Balance'],2400);
      expect(ledgers.single['Closing Balance'],11400);
    });
    test('keeps legacy entries in an explicit unassigned ledger', () {
      final ledgers=calculateAccountLedgers(
        openingBalances:[],bankReceipts:[{'Date':'2026-11-03','Amount':'500'}],
        vendorPayments:[],expenses:[],periodStart:start,periodEndExclusive:end,
      );
      expect(ledgers.single['Account Name'],'Unassigned (legacy records)');
      expect(ledgers.single['Closing Balance'],500);
    });
  });
}
