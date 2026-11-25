import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class MyntraLabelParser {
  static List<Map<String, dynamic>> parse(Uint8List bytes) {
    final document = PdfDocument(inputBytes: bytes);
    final output = <Map<String, dynamic>>[];
    try {
      for (var i = 0; i < document.pages.count; i++) {
        final text = PdfTextExtractor(document).extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        final skuMatches = RegExp(
          r'\[\s*([A-Z0-9][A-Z0-9_\\s-]*?)\s*\*\s*([^\]]+)\]',
          caseSensitive: false,
        ).allMatches(text).toList();
        // Myntra PDFs contain a Tax Invoice page followed by its shipping
        // label. Only pages with buyer/shipping-label markers are imported.
        final isLabel = text.toLowerCase().contains("buyer's name and address") ||
            (text.toLowerCase().contains('amount to be paid') && skuMatches.isNotEmpty);
        if (!isLabel || skuMatches.isEmpty) continue;

        final customerBlock = RegExp(
          r"Buyer's Name And Address\s*([\s\S]*?)(?:If undelivered|Seller Details|Buyer Declaration)",
          caseSensitive: false,
        ).firstMatch(text)?.group(1)?.trim() ?? '';
        final customerLines = customerBlock
            .split(RegExp(r'\r?\n'))
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toList();
        final customer = customerLines.isEmpty ? '' : customerLines.first;
        final pin = RegExp(r'\b[1-9][0-9]{5}\b').firstMatch(customerBlock)?.group(0) ?? '';
        final amount = RegExp(
          r'AMOUNT TO BE PAID\s*Rs\.?\s*([0-9,]+(?:\.[0-9]+)?)',
          caseSensitive: false,
        ).firstMatch(text)?.group(1)?.replaceAll(',', '') ?? '';
        final mode = RegExp(r'\b(COD|PREPAID)\b', caseSensitive: false)
            .firstMatch(text)?.group(1)?.toUpperCase() ?? '';
        final courier = text.split(RegExp(r'\r?\n')).map((v) => v.trim())
            .firstWhere((v) => v.toLowerCase().contains('logistics'), orElse: () => '');
        final pageNumber = i + 1;

        for (final match in skuMatches) {
          final sku = (match.group(1) ?? '').replaceAll(RegExp(r'\\s+'), '').toUpperCase();
          final qtyToken = (match.group(2) ?? '').trim();
          final parsedQty = int.tryParse(qtyToken.replaceAll(RegExp(r'[^0-9]'), ''));
          final qty = parsedQty == null || parsedQty < 1 ? 1 : parsedQty;
          final first = sku.split('-').first;
          final brand = first == 'HA' || first == 'H_A'
              ? 'H_A'
              : first == 'ALN' || first == 'AL'
                  ? 'AL'
                  : first == 'SA'
                      ? 'SA'
                      : first;
          output.add({
            'Date': '',
            'Platform': 'Myntra',
            'Firm / Account': '',
            'Order ID': '',
            'SKU / Product': sku,
            'Brand': brand,
            'Size': sku.split('-').isNotEmpty ? sku.split('-').last : '',
            'Color': '',
            'Orders Qty': qty.toString(),
            'Gross Order Value': amount,
            'Delivered Qty': '',
            'Delivered Sales': '',
            'Commission / Fees': '',
            'Shipping Fees': '',
            'Other Deductions': '',
            'Courier': courier,
            'AWB / Tracking No.': '',
            'Customer': customer,
            'Pincode': pin,
            'Payment Mode': mode,
            'Source PDF': 'Myntra PDF',
            'PDF Page': pageNumber.toString(),
            'Label ID': 'MYNTRA-PAGE-$pageNumber',
          });
        }
      }
    } finally {
      document.dispose();
    }
    return output;
  }
}
