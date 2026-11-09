import 'package:intl/intl.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _compact = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 1);

String inr(num v) => _inr.format(v);
String inrCompact(num v) => v.abs() < 100000 ? _inr.format(v) : _compact.format(v);
String pct(num v, [int digits = 0]) => '${(v * 100).toStringAsFixed(digits)}%';

String relativeTime(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return DateFormat('d MMM yyyy').format(t);
}

String dateTime(DateTime? t) => t == null ? '' : DateFormat('d MMM yyyy, h:mm a').format(t);
