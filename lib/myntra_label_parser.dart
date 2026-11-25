import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class MyntraLabelParser {
  static final RegExp _skuPattern = RegExp(
    r'\[\s*([A-Z0-9][A-Z0-9_&\s-]*?)\s*\*\s*([^\]]+)\]',
    caseSensitive: false,
  );

  static String _first(RegExp pattern, String text, [int group = 1]) =>
      pattern.firstMatch(text)?.group(group)?.trim() ?? '';

  static String _dateToIso(String value) {
    final parts = value.trim().split(RegExp(r'\s+'));
    if (parts.length != 3) return value;
    const months = {
      'jan':'01','feb':'02','mar':'03','apr':'04','may':'05','jun':'06',
      'jul':'07','aug':'08','sep':'09','oct':'10','nov':'11','dec':'12',
    };
    final month = months[parts[1].toLowerCase().substring(0, 3)];
    if (month == null) return value;
    return parts[2] + '-' + month + '-' + parts[0].padLeft(2, '0');
  }

  static String _invoiceBlockForSku(String sku, String invoiceText) {
    final compact = invoiceText.replaceAll(RegExp(r'\s+'), '');
    final current = compact.indexOf('(' + sku + ')');
    if (current < 0) return '';
    final nextSku = RegExp(r'\([A-Z0-9][A-Z0-9_&-]{4,}\)-', caseSensitive: false);
    int? nextStart;
    for (final match in nextSku.allMatches(compact)) {
      if (match.start > current) {
        nextStart = match.start;
        break;
      }
    }
    return compact.substring(current, nextStart ?? compact.length);
  }

  static int _quantityForSku(String sku, String invoiceText) {
    final block = _invoiceBlockForSku(sku, invoiceText);
    if (block.isEmpty) return 1;
    final match = RegExp(r'HSN:.*?(\d+)Rs', caseSensitive: false, dotAll: true)
        .firstMatch(block);
    final fallback = RegExp(r'(\d+)Rs[0-9]', caseSensitive: false).firstMatch(block);
    final qty = int.tryParse(match?.group(1) ?? fallback?.group(1) ?? '');
    return qty == null || qty < 1 ? 1 : qty;
  }

  static String _brandFor(String sku, String invoiceText) {
    final compactInvoice = invoiceText.replaceAll(RegExp(r'\s+'), '');
    final skuInInvoice = RegExp(
      r'\(' + RegExp.escape(sku) + r'\)-([A-Za-z][A-Za-z&.-]{1,50}?)Women\b',
      caseSensitive: false,
    ).firstMatch(compactInvoice);
    if (skuInInvoice != null) return skuInInvoice.group(1)!.trim();
    final prefix = sku.split('-').first.toUpperCase().replaceAll('&', '_');
    if (prefix == 'SA') return 'Sangria';
    if (prefix == 'AL' || prefix == 'ALN' || prefix == 'AL2') return 'All About You';
    if (prefix == 'H_N' || prefix == 'HA') return 'HERE&NOW';
    if (prefix == 'LOOK') return 'JiproStore';
    return prefix.isEmpty ? 'Unassigned' : prefix;
  }

  static String _firmFrom(String labelText, String invoiceText) {
    final fromSeller = _first(
      RegExp(
        r'Seller Details[\s\S]*?\n\s*([A-Z][A-Z0-9 &.-]{2,})\s*\n\s*\d{2}[A-Z0-9]{13}',
        caseSensitive: false,
      ),
      labelText,
    );
    if (fromSeller.isNotEmpty) return fromSeller;
    return _first(
      RegExp(r'Bill From:\s*([A-Z][A-Z0-9 &.-]{2,})', caseSensitive: false),
      invoiceText,
    );
  }

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
      final pageTexts = <String>[];
      for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        try {
          pageTexts.add(extractor.extractText(
            startPageIndex: pageIndex,
            endPageIndex: pageIndex,
          ));
        } on RangeError {
          pageTexts.add('');
        }
      }

      for (var pageIndex = 0; pageIndex < pageTexts.length; pageIndex++) {
        final labelText = pageTexts[pageIndex];
        final skuMatches = _skuPattern.allMatches(labelText).toList();
        if (!labelText.toLowerCase().contains("buyer's name and address") ||
            skuMatches.isEmpty) {
          continue;
        }

        // Read the invoice immediately before the label for details only.
        // Only the shipping-label page is counted as an order.
        final invoiceText = pageIndex > 0 ? pageTexts[pageIndex - 1] : '';
        final orderId = _first(
          RegExp(r'Order Number:\s*([0-9-]+)', caseSensitive: false),
          invoiceText,
        );
        final orderDate = _dateToIso(_first(
          RegExp(r'Order Date:\s*(\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4})', caseSensitive: false),
          invoiceText,
        ));
        final invoiceNo = _first(
          RegExp(r'Invoice Number:\s*([A-Z0-9-]+)', caseSensitive: false),
          invoiceText,
        );
        final firm = _firmFrom(labelText, invoiceText);
        final customerBlock = _first(
          RegExp(
            r"Buyer's Name And Address\s*([\s\S]*?)(?:If undelivered|Seller Details|Buyer Declaration)",
            caseSensitive: false,
          ),
          labelText,
        );
        final customerLines = customerBlock
            .split(RegExp(r'\r?\n'))
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toList();
        final customer = customerLines.isEmpty ? '' : customerLines.first;
        final pin = _first(RegExp(r'\b[1-9][0-9]{5}\b'), customerBlock);
        final amount = _first(
          RegExp(r'AMOUNT TO BE PAID\s*Rs\.?\s*([0-9,]+(?:\.[0-9]+)?)', caseSensitive: false),
          labelText,
        ).replaceAll(',', '');
        final paymentMode = RegExp(r'\b(COD|PREPAID)\b', caseSensitive: false)
            .firstMatch(labelText)?.group(1)?.toUpperCase() ?? '';
        final courier = labelText.split(RegExp(r'\r?\n')).map((v) => v.trim())
            .firstWhere((v) => v.toLowerCase().contains('logistics'), orElse: () => '');
        final pageNumber = pageIndex + 1;
        final labelRef = orderId.isNotEmpty
            ? orderId
            : (skuMatches.first.group(2) ?? 'PAGE-' + pageNumber.toString()).trim();

        for (final match in skuMatches) {
          final sku = (match.group(1) ?? '')
              .replaceAll(RegExp(r'\s+'), '')
              .toUpperCase();
          final brand = _brandFor(sku, invoiceText);
          final invoiceQty = _quantityForSku(sku, invoiceText);
          final shipmentRef = (match.group(2) ?? '').trim();
          final size = RegExp(r'-(XS|S|M|L|XL|XXL|3XL|4XL)$', caseSensitive: false)
              .firstMatch(sku)?.group(1)?.toUpperCase() ?? '';
          output.add({
            'Date': orderDate,
            'Platform': 'Myntra',
            'Firm / Account': firm,
            'Order ID': orderId,
            'SKU / Product': sku,
            'Brand': brand,
            'Size': size,
            'Color': '',
            'Orders Qty': invoiceQty.toString(),
            'Gross Order Value': amount,
            'Delivered Qty': '',
            'Delivered Sales': '',
            'Commission / Fees': '',
            'Shipping Fees': '',
            'Other Deductions': '',
            'Courier': courier,
            'AWB / Tracking No.': shipmentRef,
            'Customer': customer,
            'Pincode': pin,
            'Payment Mode': paymentMode,
            'Source PDF': 'Myntra PDF',
            'PDF Page': pageNumber.toString(),
            'Invoice No.': invoiceNo,
            'Label ID': 'MYNTRA-' + labelRef + '-PAGE-' + pageNumber.toString(),
          });
        }
      }
    } finally {
      document.dispose();
    }
    return output;
  }
}
