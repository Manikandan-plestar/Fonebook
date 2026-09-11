/// String utilities for formatting and transformations across the app.
extension StringTitleCase on String {
  /// Capitalizes the first letter of each word separated by spaces.
  /// Example: "john doe" -> "John Doe", "software developer" -> "Software Developer"
  String toTitleCase() {
    if (trim().isEmpty) return this;
    return split(' ').map((word) {
      if (word.isEmpty) return word;
      if (word.length == 1) return word.toUpperCase();
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    }).join(' ');
  }
}

/// Helper function to convert any nullable or dynamic string to Title Case.
String toTitleCase(String? text) {
  if (text == null || text.isEmpty) return '';
  return text.toTitleCase();
}
