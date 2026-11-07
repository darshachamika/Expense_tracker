abstract final class FlowFormat {
  static const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  static const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static String money(int minor, {bool cents = false}) {
    final absolute = minor.abs();
    final whole = (absolute ~/ 100).toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    final fraction = absolute % 100;
    return '${minor < 0 ? '-' : ''}Rs. $whole${cents || fraction != 0 ? '.${fraction.toString().padLeft(2, '0')}' : ''}';
  }
  static String month(DateTime value) => '${months[value.month - 1]} ${value.year}';
  static String shortDate(DateTime value) => '${months[value.month - 1].substring(0, 3)} ${value.day}';
  static String greeting(DateTime now) => now.hour < 12 ? 'Good morning' : now.hour < 17 ? 'Good afternoon' : 'Good evening';
  static String dateGroup(DateTime value, DateTime now) {
    final date = DateTime(value.year, value.month, value.day);
    final today = DateTime(now.year, now.month, now.day);
    final prefix = date == today ? 'Today, ' : date == DateTime(today.year, today.month, today.day - 1) ? 'Yesterday, ' : '';
    return '$prefix${shortDate(value)}, ${value.year}';
  }
}
