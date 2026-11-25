import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Meesho labels contain shipping and tax-invoice content on one page.
/// Only the Product Details label table creates order rows.
class MeeshoLabelParser {
  static String _first(RegExp pattern, String text, [int group = 1]) =>
      pattern.firstMatch(text)?.group(group)?.trim() ?? '';

  static String _dateToIso(String value) {
    final match = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$')
        .firstMatch(value.trim());
    if (match == null) return value.trim();
    return '${match.group(3)}-${match.group(2)!.padLeft(2, '0')}-${match.group(1)!.padLeft(2, '0')}';
  }

  static String _clean(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  static List<Map<String, dynamic>> parse(Uint8List bytes) {
    if (bytes.isEmpty) throw const FormatException('The selected PDF is empty.');
    final document = PdfDocument(inputBytes: bytes);
    final output = <Map<String, dynamic>>[];
    try {
      final pageCount = document.pages.count;
      if (pageCount <= 0) {
        throw const FormatException('The PDF does not contain readable pages.');
      }
      final extractor = PdfTextExtractor(document);
      for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        String pageText;
        try {
          // Syncfusion's endPageIndex is inclusive; keep it within the page count.
          pageText = extractor.extractText(
            startPageIndex: pageIndex,
            endPageIndex: pageIndex,
          );
        } catch (_) {
          continue;
        }
        final lower = pageText.toLowerCase();
        if (!lower.contains('customer address') ||
            !lower.contains('product details') ||
            !lower.contains('order no')) {
          continue;
        }

        final compact = _clean(pageText);
        final tableStart = compact.toLowerCase().indexOf('product details');
        final invoiceStart = compact.toLowerCase().indexOf('tax invoice', tableStart);
        if (tableStart < 0) continue;
        final labelTable = compact.substring(
          tableStart,
          invoiceStart > tableStart ? invoiceStart : compact.length,
        );

        final skuRow = RegExp(
          r'SKU\s+Size\s+Qty\s+Color\s+Order\s+No\.?\s*'
          r'([A-Za-z0-9]{6,20})\s+'
          r'(Free\s+Size|XS|S|M|L|XL|XXL|3XL|4XL|One\s+Size)\s+'
          r'(\d+)\s+'
          r'([A-Za-z][A-Za-z -]{0,25}?)\s+'
          r'(\d{12,}(?:_\d+)?)',
          caseSensitive: false,
        );
        final skuRows = skuRow.allMatches(labelTable).toList();
        if (skuRows.isEmpty) continue;

        final customerBlock = _first(
          RegExp(r'Customer Address\s+([\s\S]*?)\s+If undelivered', caseSensitive: false),
          pageText,
        );
        final customerLines = customerBlock
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        final customer = customerLines.isEmpty ? '' : customerLines.first;
        final pincode = _first(RegExp(r'\b[1-9]\d{5}\b'), customerBlock);

        final firm = _first(
          RegExp(r'If undelivered,\s*return to:\s*([^\r\n]+)', caseSensitive: false),
          pageText,
        );
        final orderId = _first(
          RegExp(r'Purchase Order No\.?\s*([0-9]+)', caseSensitive: false),
          pageText,
        );
        final invoiceNo = _first(
          RegExp(r'Invoice No\.?\s*([A-Za-z0-9-]+)', caseSensitive: false),
          pageText,
        );
        final orderDate = _dateToIso(_first(
          RegExp(r'Order Date\s*(\d{1,2}[./-]\d{1,2}[./-]\d{4})', caseSensitive: false),
          pageText,
        ));
        final courierMatch = RegExp(
          r'\b(Delhivery|Shadowfax|Xpressbees|Ecom\s*Express|Ekart|DTDC|Blue\s*Dart)\b',
          caseSensitive: false,
        ).firstMatch(pageText);
        final courier = courierMatch?.group(1) ?? '';
        final trackingCandidates = RegExp(r'\b(?:[A-Z]{1,5}[A-Z0-9]{8,}|[0-9]{12,})\b')
            .allMatches(pageText.toUpperCase())
            .map((m) => m.group(0)!)
            .where((value) => value != orderId && !value.startsWith('24DQP'))
            .toList();
        final tracking = trackingCandidates.isEmpty ? '' : trackingCandidates.first;

        final totalSection = RegExp(
          r'\bTotal\b([\s\S]*?)(?:Tax is not payable|$)',
          caseSensitive: false,
        ).firstMatch(pageText)?.group(1) ?? '';
        final amounts = RegExp(r'Rs\.?\s*([0-9,]+(?:\.[0-9]{1,2})?)', caseSensitive: false)
            .allMatches(totalSection)
            .map((m) => m.group(1)!.replaceAll(',', ''))
            .toList();
        final totalAmount = amounts.isEmpty ? '' : amounts.last;
        final paymentMode = RegExp(r'\bCOD\b', caseSensitive: false).hasMatch(pageText)
            ? 'COD'
            : 'Prepaid';
        final description = _first(
          RegExp(r'Description\s+([\s\S]*?)\s+HSN\b', caseSensitive: false),
          pageText,
        );

        for (final row in skuRows) {
          final sku = row.group(1)!.trim();
          final size = _clean(row.group(2)!);
          final qty = int.tryParse(row.group(3)!) ?? 1;
          final color = _clean(row.group(4)!);
          final rowOrder = row.group(5)!.trim();
          final baseOrder = orderId.isNotEmpty
              ? orderId
              : rowOrder.replaceFirst(RegExp(r'_\d+$'), '');
          output.add({
            'Date': orderDate,
            'Platform': 'Meesho',
            'Firm / Account': firm,
            'Order ID': baseOrder,
            'SKU / Product': sku,
            // Meesho label has a seller/store name but no distinct product-brand field.
            'Brand': firm,
            'Size': size,
            'Color': color,
            'Orders Qty': qty.toString(),
            'Gross Order Value': totalAmount,
            'Delivered Qty': '',
            'Delivered Sales': '',
            'Commission / Fees': '',
            'Shipping Fees': '',
            'Other Deductions': '',
            'Courier': courier,
            'AWB / Tracking No.': tracking,
            'Customer': customer,
            'Pincode': pincode,
            'Payment Mode': paymentMode,
            'Source PDF': 'Meesho PDF',
            'PDF Page': (pageIndex + 1).toString(),
            'Invoice No.': invoiceNo,
            'Product Description': description,
            'Label ID': 'MEESHO-$baseOrder-PAGE-${pageIndex + 1}',
          });
        }
      }
    } finally {
      document.dispose();
    }
    return output;
  }
}
