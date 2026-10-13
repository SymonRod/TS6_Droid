/// Error text for the UI: drops the "AnyhowException(...)" / "Exception:" wrappers.
String cleanError(Object? e) {
  var s = '$e'.trim();
  final m = RegExp(r'^AnyhowException\(([\s\S]*)\)$').firstMatch(s);
  if (m != null) s = m.group(1)!.trim();
  s = s.replaceFirst(RegExp(r'^(AnyhowException|Exception|Error):\s*'), '');
  return s;
}
