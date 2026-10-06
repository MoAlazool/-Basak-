import 'package:flutter/material.dart';

/// Colours and field styling shared by the sign-in and registration screens,
/// so the two feel like one flow.
class AuthStyles {
  static const teal = Color(0xFF1F6F8B);
  static const ink = Color(0xFF17384A);
  static const muted = Color(0xFF6B8494);
  static const label = Color(0xFF334B5A);
  static const danger = Color(0xFFB42318);
  static const line = Color(0xFFDCE7EE);
  static const fieldFill = Color(0xFFF7FAFC);

  static const labelStyle = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: label);
  static const inputStyle = TextStyle(fontSize: 16, color: ink);

  static InputDecoration field({required IconData icon, String? hint, String? helper, Widget? suffix}) {
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: color, width: width));
    return InputDecoration(
      prefixIcon: Icon(icon, size: 20, color: muted),
      suffixIcon: suffix,
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF9DB0BC), fontSize: 15),
      helperText: helper,
      helperStyle: const TextStyle(fontSize: 12, color: muted),
      helperMaxLines: 2,
      errorStyle: const TextStyle(fontSize: 12.5, color: danger),
      errorMaxLines: 2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      filled: true,
      fillColor: fieldFill,
      border: border(line),
      enabledBorder: border(line),
      focusedBorder: border(teal, 1.6),
      errorBorder: border(danger),
      focusedErrorBorder: border(danger, 1.6),
    );
  }

  /// A message the student must not miss: icon + text, announced to screen readers.
  static Widget errorBanner(String message, {Key? key}) => Semantics(
        liveRegion: true,
        child: Container(
          key: key,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: const Color(0xFFFFF1F0), borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.error_outline_rounded, size: 18, color: danger),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(color: danger, fontSize: 13.5, height: 1.45))),
          ]),
        ),
      );

  static ButtonStyle primaryButton() => ElevatedButton.styleFrom(
        backgroundColor: teal,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFF8FB3C2),
        disabledForegroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      );
}
