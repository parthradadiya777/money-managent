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
    value = value.trim();
    if (value.isEmpty) return '';
    final numeric = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$').firstMatch(value);
    if (numeric != null) return '${numeric.group(3)}-${numeric.group(2)!.padLeft(2, '0')}-${numeric.group(1)!.padLeft(2, '0')}';
    final iso = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$').firstMatch(value);
    if (iso != null) return '${iso.group(1)}-${iso.group(2)!.padLeft(2, '0')}-${iso.group(3)!.padLeft(2, '0')}';
    final parts = value.split(RegExp(r'\s+'));
    if (parts.length != 3) return value;
    const months = {'jan':'01','feb':'02','mar':'03','apr':'04','may':'05','jun':'06','jul':'07','aug':'08','sep':'09','oct':'10','nov':'11','dec':'12'};
    final month = months[parts[1].toLowerCase().substring(0, 3)];
    if (month == null) return value;
    return '${parts[2]}-$month-${parts[0].padLeft(2, '0')}';
  }

  static String _invoiceBlockForSku(String sku, String invoiceText) {
    final compact = invoiceText.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final current = compact.indexOf('(' + sku.toUpperCase() + ')');
    if (current < 0) return '';
    final nextSku = RegExp(r'\([A-Z0-9][A-Z0-9_&-]{4,}\)-', caseSensitive: false);
    int? nextStart;
    for (final match in nextSku.allMatches(compact)) {
      if (match.start > current) { nextStart = match.start; break; }
    }
    return compact.substring(current, nextStart ?? compact.length);
  }

  static int _quantityForSku(String sku, String invoiceText) {
    final block = _invoiceBlockForSku(sku, invoiceText);
    if (block.isEmpty) return 1;
    final match = RegExp(r'HSN:.*?(\d+)Rs', caseSensitive: false, dotAll: true).firstMatch(block);
    final fallback = RegExp(r'(\d+)Rs[0-9]', caseSensitive: false).firstMatch(block);
    final qty = int.tryParse(match?.group(1) ?? fallback?.group(1) ?? '');
    return qty == null || qty < 1 ? 1 : qty;
  }

  static String _firmFrom(String labelText, String invoiceText) {
    final lines = labelText.split(RegExp(r'\r?\n')).map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
    final sellerIndex = lines.indexWhere((v) => v.toLowerCase().contains('seller details'));
    if (sellerIndex >= 0) {
      for (var i = sellerIndex + 1; i < lines.length && i <= sellerIndex + 5; i++) {
        final line = lines[i];
        if (RegExp(r'^[A-Z]{2}\d{13}$', caseSensitive: false).hasMatch(line)) break;
        if (RegExp(r'[A-Za-z]').hasMatch(line) && !line.toLowerCase().contains('gstin') &&
            !line.toLowerCase().contains('phone') && !RegExp(r'^\d').hasMatch(line)) return line;
      }
    }
    for (final pattern in [
      RegExp(r'Bill\s*From\s*:?\s*([A-Z][A-Z0-9 &.,()/-]{2,})', caseSensitive: false),
      RegExp(r'Seller\s*Name\s*:?\s*([A-Z][A-Z0-9 &.,()/-]{2,})', caseSensitive: false),
    ]) {
      final found = _first(pattern, invoiceText);
      if (found.isNotEmpty) return found;
    }
    return '';
  }

  static List<Map<String, dynamic>> parse(Uint8List bytes) {
    if (bytes.isEmpty) throw const FormatException('The selected PDF is empty.');
    final document = PdfDocument(inputBytes: bytes);
    final output = <Map<String, dynamic>>[];
    try {
      final pageCount = document.pages.count;
      if (pageCount <= 0) throw const FormatException('The PDF does not contain readable pages.');
      final extractor = PdfTextExtractor(document);
      final pageTexts = <String>[];
      for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        try {
          pageTexts.add(extractor.extractText(startPageIndex: pageIndex, endPageIndex: pageIndex));
        } on RangeError { pageTexts.add(''); }
      }

      for (var pageIndex = 0; pageIndex < pageTexts.length; pageIndex++) {
        final labelText = pageTexts[pageIndex];
        final skuMatches = _skuPattern.allMatches(labelText).toList();
        if (!labelText.toLowerCase().contains("buyer's name and address") || skuMatches.isEmpty) continue;

        final invoiceText = pageIndex > 0 ? pageTexts[pageIndex - 1] : '';
        final combined = '\$invoiceText\n\$labelText';
        final orderId = _first(RegExp(r'Order\s*(?:Number|No\.?)\s*[:#]?\s*([A-Z0-9/-]+)', caseSensitive: false), combined);
        final rawDate = _first(
          RegExp(r'(?:Order\s*Date|Invoice\s*Date|Date)\s*[:#]?\s*(\d{1,2}[-/ ]\d{1,2}[-/ ]\d{4}|\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4}|\d{4}[-/]\d{1,2}[-/]\d{1,2})', caseSensitive: false),
          combined,
        );
        final orderDate = _dateToIso(rawDate);
        final invoiceNo = _first(RegExp(r'Invoice\s*(?:Number|No\.?)\s*[:#]?\s*([A-Z0-9/-]+)', caseSensitive: false), invoiceText);
        final firm = _firmFrom(labelText, invoiceText);
        final customerBlock = _first(
          RegExp(r"Buyer's Name And Address\s*([\s\S]*?)(?:If undelivered|Seller Details|Buyer Declaration)", caseSensitive: false),
          labelText,
        );
        final customerLines = customerBlock.split(RegExp(r'\r?\n')).map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
        final customer = customerLines.isEmpty ? '' : customerLines.first;
        final pin = _first(RegExp(r'\b[1-9][0-9]{5}\b'), customerBlock);
        final amount = _first(RegExp(r'AMOUNT TO BE PAID\s*Rs\.?\s*([0-9,]+(?:\.[0-9]+)?)', caseSensitive: false), labelText).replaceAll(',', '');
        final paymentMode = RegExp(r'\b(COD|PREPAID)\b', caseSensitive: false).firstMatch(labelText)?.group(1)?.toUpperCase() ?? '';
        final courier = labelText.split(RegExp(r'\r?\n')).map((v) => v.trim()).firstWhere((v) => v.toLowerCase().contains('logistics'), orElse: () => '');
        final pageNumber = pageIndex + 1;

        for (final match in skuMatches) {
          final sku = (match.group(1) ?? '').replaceAll(RegExp(r'\s+'), '').toUpperCase();
          final shipmentRef = (match.group(2) ?? '').trim();
          final resolvedOrderId = orderId.isNotEmpty ? orderId : shipmentRef;
          final size = RegExp(r'-(XS|S|M|L|XL|XXL|3XL|4XL)$', caseSensitive: false).firstMatch(sku)?.group(1)?.toUpperCase() ?? '';
          output.add({
            'Date': orderDate.isEmpty ? 'Not detected' : orderDate,
            'Platform': 'Myntra',
            'Firm / Account': firm.isEmpty ? 'Not detected' : firm,
            'Order ID': resolvedOrderId.isEmpty ? 'Not detected' : resolvedOrderId,
            'SKU / Product': sku,
            'Brand': 'JIPROSTORE',
            'Size': size,
            'Color': '',
            'Orders Qty': _quantityForSku(sku, invoiceText).toString(),
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
            'Label ID': 'MYNTRA-${resolvedOrderId.isEmpty ? shipmentRef : resolvedOrderId}-PAGE-\$pageNumber',
          });
        }
      }
    } finally { document.dispose(); }
    return output;
  }
}
