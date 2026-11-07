import 'package:flutter/material.dart';

bool librarySearchMatches(String value, String query) {
  final text = value.toLowerCase();
  var offset = 0;
  for (final rune in query.trim().toLowerCase().runes) {
    final character = String.fromCharCode(rune);
    final found = text.indexOf(character, offset);
    if (found < 0) return false;
    offset = found + character.length;
  }
  return true;
}

class LibrarySearch extends StatelessWidget {
  const LibrarySearch({
    super.key,
    required this.onChanged,
    required this.hint,
    this.controller,
  });
  final ValueChanged<String> onChanged;
  final String hint;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFF6E7C8F)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          filled: true,
          fillColor: colors.surface,
          prefixIcon: Icon(Icons.search, color: colors.primary),
          hintText: hint,
          hintStyle: TextStyle(color: colors.onSurface.withValues(alpha: .7)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: colors.primary, width: 2),
          ),
        ),
      ),
    );
  }
}
