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

/// Normalizes a phone number by stripping formatting characters (spaces, dashes, parentheses, dots)
/// and standardizing prefixes.
String normalizePhoneNumber(String phone) {
  if (phone.trim().isEmpty) return '';
  String cleaned = phone.replaceAll(RegExp(r'[\(\)\-\s\.\/]'), '').trim();
  if (cleaned.startsWith('00')) {
    cleaned = '+${cleaned.substring(2)}';
  } else if (cleaned.startsWith('0') && cleaned.length > 10) {
    cleaned = cleaned.substring(1);
  }
  return cleaned;
}

/// Returns the canonical comparison key for duplicate detection across formatting differences
/// (e.g., "+91 9876543210", "9876543210", "+919876543210", "09876543210").
String getCanonicalPhoneKey(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length >= 10) {
    return digits.substring(digits.length - 10);
  }
  return digits;
}

/// Checks if two phone numbers represent the same contact number despite formatting differences.
bool arePhoneNumbersEquivalent(String phone1, String phone2) {
  final k1 = getCanonicalPhoneKey(phone1);
  final k2 = getCanonicalPhoneKey(phone2);
  if (k1.isEmpty || k2.isEmpty) return false;
  return k1 == k2;
}

