/// A local date and millisecond timestamp shared by all diagnostic logs.
String logTimestamp(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  final millis = value.millisecond.toString().padLeft(3, '0');
  return '${value.year.toString().padLeft(4, '0')}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}.$millis';
}
