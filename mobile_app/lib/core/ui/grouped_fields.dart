import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_icons.dart';
import 'basak_button.dart';
import 'basak_page.dart';
import 'tokens.dart';

/// Fields grouped in one white card, a hairline between them: the entry
/// screens' form. Children are [GroupedField]s and [GroupedValue]s.
class GroupedFields extends StatelessWidget {
  final List<Widget> children;

  const GroupedFields({super.key, required this.children});

  @override
  Widget build(BuildContext context) => BasakCard(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: context.colors.hairline),
              children[i],
            ],
          ],
        ),
      );
}

TextStyle _valueStyle(BuildContext context) =>
    context.text.rowTitle.copyWith(fontWeight: FontWeight.w400, height: 24 / 16);

TextStyle _labelStyle(BuildContext context, Color color) =>
    context.text.caption.copyWith(fontWeight: FontWeight.w500, color: color);

/// One typed field of a [GroupedFields] card: the label over the value. The
/// label turns teal while the field has focus and red while it has an error;
/// the error text takes the place of the helper, it never stacks under it.
class GroupedField extends StatefulWidget {
  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;
  final String? helper;
  final String? error;
  final Widget? trailing;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool enabled;
  final int? maxLength;

  /// Phone numbers and codes: typed left to right, still aligned to the start edge.
  final bool ltr;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const GroupedField({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.hint,
    this.helper,
    this.error,
    this.trailing,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.enabled = true,
    this.maxLength,
    this.ltr = false,
    this.inputFormatters,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<GroupedField> createState() => _GroupedFieldState();
}

class _GroupedFieldState extends State<GroupedField> {
  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(GroupedField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownNode)?.removeListener(_onFocus);
      _node.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _ownNode?.dispose();
    super.dispose();
  }

  void _onFocus() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasError = widget.error != null;
    final labelColor = hasError ? colors.danger : (_node.hasFocus ? colors.teal : colors.ink3);
    final note = widget.error ?? widget.helper;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 66),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label, style: _labelStyle(context, labelColor)),
                  TextField(
                    controller: widget.controller,
                    focusNode: _node,
                    enabled: widget.enabled,
                    obscureText: widget.obscureText,
                    keyboardType: widget.keyboardType,
                    textInputAction: widget.textInputAction,
                    inputFormatters: widget.inputFormatters,
                    autofillHints: widget.autofillHints,
                    maxLength: widget.maxLength,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                    textDirection: widget.ltr ? TextDirection.ltr : null,
                    // The start edge of the screen, whichever way the value reads.
                    textAlign: widget.ltr && rtl ? TextAlign.end : TextAlign.start,
                    style: _valueStyle(context).copyWith(color: widget.enabled ? colors.ink : colors.ink3),
                    cursorColor: colors.teal,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      counterText: '',
                      hintText: widget.hint,
                      // The hint keeps to the start edge too, whatever it is written in.
                      hintTextDirection: widget.ltr ? TextDirection.ltr : null,
                      hintStyle: _valueStyle(context).copyWith(color: colors.disabled),
                    ),
                  ),
                  if (note != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: BasakSpace.s2),
                      child: Text(note,
                          style: context.text.caption.copyWith(color: hasError ? colors.danger : colors.ink3)),
                    ),
                ],
              ),
            ),
            if (widget.trailing != null) ...[
              const SizedBox(width: BasakSpace.s10),
              widget.trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A row of a [GroupedFields] card whose value is picked, not typed: it opens
/// a sheet (university, college). [locked] shows a value that cannot change.
class GroupedValue extends StatelessWidget {
  final String label;
  final String? value;
  final String? placeholder;
  final String? error;
  final VoidCallback? onTap;
  final bool locked;

  /// The row opens a sheet under it: a chevron pointing down, not onward.
  final bool opensSheet;

  const GroupedValue({
    super.key,
    required this.label,
    this.value,
    this.placeholder,
    this.error,
    this.onTap,
    this.locked = false,
    this.opensSheet = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final hasError = error != null;
    return BasakPressable(
      onTap: locked ? null : onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 66),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: _labelStyle(context, hasError ? colors.danger : colors.ink3)),
                    Text(
                      value ?? placeholder ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _valueStyle(context)
                          .copyWith(color: value == null ? colors.disabled : (locked ? colors.ink2 : colors.ink)),
                    ),
                    if (hasError)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(top: BasakSpace.s2),
                        child: Text(error!, style: context.text.caption.copyWith(color: colors.danger)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: BasakSpace.s10),
              Icon(
                locked
                    ? LucideIcons.lock
                    : opensSheet
                        ? LucideIcons.chevronDown
                        : (rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight),
                size: locked || opensSheet ? 18 : 20,
                color: colors.ink3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A failure that stays inside the section it belongs to, with its retry.
class InlineError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  const InlineError({super.key, required this.message, this.onRetry, this.retryLabel = 'إعادة المحاولة'});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BasakCard(
      radius: BasakRadius.control,
      padding: const EdgeInsetsDirectional.fromSTEB(BasakSpace.s16, BasakSpace.s2, BasakSpace.s4, BasakSpace.s2),
      child: Row(
        children: [
          Icon(LucideIcons.triangleAlert, size: 18, color: colors.danger),
          const SizedBox(width: BasakSpace.s12),
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s10),
              child: Text(message, style: context.text.bodySmall),
            ),
          ),
          if (onRetry != null)
            BasakButton(
              label: retryLabel,
              onPressed: onRetry,
              variant: BasakButtonVariant.quiet,
              size: BasakButtonSize.small,
              expand: false,
            ),
        ],
      ),
    );
  }
}
