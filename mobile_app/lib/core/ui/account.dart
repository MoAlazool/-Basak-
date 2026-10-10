import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import 'basak_button.dart';
import 'basak_page.dart';
import 'facts.dart';
import 'status_chip.dart';
import 'tokens.dart';

/// What the inbox and the account page are made of (boards `Inbox`,
/// `InboxDetail`, `InboxEmpty`, `Profile`, `EditDetails`, `DeleteAccount`,
/// `Help`).

/// A glyph on its tone's tint: 40 with radius 12 in a row, 44 with radius 14
/// at the top of a sheet.
class ToneTile extends StatelessWidget {
  final IconData icon;
  final BasakTone tone;
  final double size;

  const ToneTile(this.icon, {super.key, this.tone = BasakTone.neutral, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: tone.tint(colors),
          borderRadius: BasakRadius.all(size > 40 ? BasakRadius.small : BasakRadius.tile),
        ),
        child: Icon(icon, size: size > 40 ? 21 : 19, color: tone.foreground(colors)),
      ),
    );
  }
}

/// The top of a pushed page whose title sits beside the back button
/// («التنبيهات»), with its quiet actions at the far end.
class PageTitleBar extends StatelessWidget {
  final String title;
  final List<Widget> actions;

  const PageTitleBar({super.key, required this.title, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Row(
      children: [
        BasakIconButton(
          icon: rtl ? LucideIcons.arrowRight : LucideIcons.arrowLeft,
          label: 'رجوع',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: BasakSpace.s12),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.sheetTitle),
          ),
        ),
        ...actions,
      ],
    );
  }
}

/// A word of teal text that acts («قراءة الكل», «تعديل»). Its target is 48.
class TextAction extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const TextAction({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BasakPressable(
      onTap: onTap,
      child: Center(
        widthFactor: 1,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s4),
          child: Text(
            label,
            maxLines: 1,
            style: context.text.bodySmall
                .copyWith(color: onTap == null ? colors.disabled : colors.teal, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// A quiet label over the block it names: a day of the inbox, «بياناتي»,
/// «التطبيق». With an action, the action's 48 target reaches [overhang] above
/// the label, so the page leaves that much less before the group.
class GroupSection extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;
  final Widget child;

  /// How far a group with an action starts above its label.
  static const double overhang = 14;

  const GroupSection({
    super.key,
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
    this.actionKey,
  });

  @override
  Widget build(BuildContext context) {
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s4),
          child: Semantics(
            header: true,
            child: Text(title, style: context.text.label.copyWith(color: context.colors.ink2)),
          ),
        ),
        const SizedBox(height: BasakSpace.s8),
        child,
      ],
    );
    if (actionLabel == null) return column;
    return Stack(
      children: [
        Padding(padding: const EdgeInsetsDirectional.only(top: overhang), child: column),
        PositionedDirectional(
          top: 0,
          end: 0,
          child: TextAction(key: actionKey, label: actionLabel!, onTap: onAction),
        ),
      ],
    );
  }
}

/// One alert of the inbox.
class AlertRow {
  final IconData icon;
  final BasakTone tone;
  final String title;
  final String body;

  /// Already formatted with `BasakUi.time12`.
  final String time;

  /// Unread: the title is set heavier and a teal dot sits under the time.
  final bool unread;
  final VoidCallback? onTap;
  final Key? key;

  const AlertRow({
    required this.icon,
    this.tone = BasakTone.neutral,
    required this.title,
    required this.body,
    required this.time,
    this.unread = false,
    this.onTap,
    this.key,
  });
}

/// The alerts of one day in one card, a hairline between them.
class AlertRows extends StatelessWidget {
  final List<AlertRow> rows;

  const AlertRows({super.key, required this.rows});

  @override
  Widget build(BuildContext context) => BasakCard(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: context.colors.hairline),
              _row(context, rows[i]),
            ],
          ],
        ),
      );

  Widget _row(BuildContext context, AlertRow row) {
    final colors = context.colors;
    final text = context.text;
    return BasakPressable(
      key: row.key,
      onTap: row.onTap,
      semanticLabel: row.unread ? 'غير مقروء' : null,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ToneTile(row.icon, tone: row.tone),
            const SizedBox(width: BasakSpace.s12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.body.copyWith(fontWeight: row.unread ? FontWeight.w600 : FontWeight.w400),
                  ),
                  if (row.body.isNotEmpty)
                    Text(
                      row.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400),
                    ),
                ],
              ),
            ),
            const SizedBox(width: BasakSpace.s12),
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(row.time, style: text.caption.copyWith(color: colors.ink3)),
                  if (row.unread) ...[
                    const SizedBox(height: BasakSpace.s8),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: colors.teal, shape: BoxShape.circle),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A card that states one thing and offers the one way to act on it:
/// «الإشعارات متوقفة» with «فتح إعدادات الهاتف».
class ActionNotice extends StatelessWidget {
  final IconData icon;
  final BasakTone tone;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  const ActionNotice({
    super.key,
    required this.icon,
    this.tone = BasakTone.warning,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return BasakCard(
      padding: const EdgeInsetsDirectional.all(BasakSpace.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ToneTile(icon, tone: tone),
              const SizedBox(width: BasakSpace.s12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.rowTitle),
                    Text(message, style: text.bodySmall.copyWith(color: context.colors.ink2)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: BasakSpace.s14),
          BasakButton(
            label: actionLabel,
            onPressed: onAction,
            variant: BasakButtonVariant.tonal,
            size: BasakButtonSize.small,
          ),
        ],
      ),
    );
  }
}

/// A search box on the ground: white, 48 high.
class SearchBox extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  const SearchBox({super.key, required this.hint, required this.onChanged, this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = context.text.body;
    return Container(
      constraints: const BoxConstraints(minHeight: BasakSpace.tapTarget),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BasakRadius.all(BasakRadius.small),
        boxShadow: BasakShadow.card,
      ),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 18, color: colors.ink3),
          const SizedBox(width: BasakSpace.s10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: style,
              cursorColor: colors.teal,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s12),
                hintText: hint,
                hintStyle: style.copyWith(color: colors.ink3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Who is signed in: the photo with its camera control, the name and the
/// phone number.
class IdentityCard extends StatelessWidget {
  final String name;
  final String phone;
  final ImageProvider? photo;
  final VoidCallback? onChangePhoto;
  final Key? photoKey;

  /// A new photo is on its way: a spinner over the photo, the control waits.
  final bool busy;

  /// At the end of the card: the supervisor's `StatusChip`.
  final Widget? trailing;

  const IdentityCard({
    super.key,
    required this.name,
    required this.phone,
    this.photo,
    this.onChangePhoto,
    this.photoKey,
    this.busy = false,
    this.trailing,
  });

  static const double _photo = 64;

  /// The camera control hangs over the photo's end and bottom edges; the box
  /// around the photo is this much larger so the whole 48 target can be hit.
  static const double _overEnd = 20;
  static const double _overBottom = 14;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return BasakCard(
      radius: BasakRadius.sheet,
      padding: EdgeInsetsDirectional.fromSTEB(
          BasakSpace.s20, BasakSpace.s20, BasakSpace.s20, onChangePhoto == null ? BasakSpace.s20 : BasakSpace.s6),
      child: Row(
        children: [
          if (onChangePhoto == null) ...[
            PhotoRing(name: name, image: photo, size: _photo),
            const SizedBox(width: BasakSpace.s16),
          ] else
            SizedBox(
              width: _photo + _overEnd,
              height: _photo + _overBottom,
              child: Stack(
                children: [
                  PositionedDirectional(top: 0, start: 0, child: PhotoRing(name: name, image: photo, size: _photo)),
                  if (busy)
                    PositionedDirectional(
                      top: 0,
                      start: 0,
                      child: Container(
                        width: _photo,
                        height: _photo,
                        padding: const EdgeInsetsDirectional.all(BasakSpace.s20),
                        decoration:
                            BoxDecoration(color: colors.surface.withValues(alpha: .6), shape: BoxShape.circle),
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.teal),
                      ),
                    ),
                  PositionedDirectional(
                    bottom: 0,
                    end: 0,
                    child: BasakPressable(
                      key: photoKey,
                      onTap: busy ? null : onChangePhoto,
                      semanticLabel: 'تغيير الصورة',
                      child: Center(
                        // The white ring that lifts it off the photo.
                        child: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: colors.surface, shape: BoxShape.circle),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(color: colors.ink, shape: BoxShape.circle),
                            child: Icon(LucideIcons.camera, size: 14, color: colors.onInk),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(bottom: onChangePhoto == null ? 0 : _overBottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.sheetTitle),
                  if (phone.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                        phone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        // Read left to right, still at the start edge.
                        textAlign: Directionality.of(context) == TextDirection.rtl ? TextAlign.end : TextAlign.start,
                        style: text.bodySmall.copyWith(color: colors.ink2),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: BasakSpace.s10), trailing!],
        ],
      ),
    );
  }
}

/// One line of a [SettingRows] card.
///
/// Without a tap it states a fact: a quiet label and its value. With a tap
/// (or a [trailing] control) it is something to do: the label reads as the
/// value does and a glyph closes the row.
class SettingRow {
  final String label;
  final String? value;

  /// A value that is not there yet («لم يُضف بعد»): drawn quieter.
  final bool muted;

  /// A small lock after the value: it cannot be changed here.
  final bool locked;

  /// Emails, codes and numbers read left to right.
  final bool ltrValue;
  final VoidCallback? onTap;

  /// The tap leaves the app (the phone's settings): an "open outside" glyph
  /// instead of the chevron.
  final bool external;

  /// A control at the end of the row instead of a glyph (a switch).
  final Widget? trailing;

  /// A small picture before the value, part of the fact it states (the
  /// company's mark beside its name).
  final Widget? mark;
  final Key? key;

  const SettingRow({
    required this.label,
    this.value,
    this.muted = false,
    this.locked = false,
    this.ltrValue = false,
    this.onTap,
    this.external = false,
    this.trailing,
    this.mark,
    this.key,
  });
}

/// Rows 52 high in one white card, a hairline between them: the account
/// page's «بياناتي» and «التطبيق».
class SettingRows extends StatelessWidget {
  final List<SettingRow> rows;

  const SettingRows({super.key, required this.rows});

  @override
  Widget build(BuildContext context) => BasakCard(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: context.colors.hairline),
              _row(context, rows[i]),
            ],
          ],
        ),
      );

  Widget _row(BuildContext context, SettingRow row) {
    final colors = context.colors;
    final text = context.text;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final acts = row.onTap != null || row.trailing != null;

    final TextStyle valueStyle = acts
        ? text.bodySmall.copyWith(color: colors.ink3)
        : row.muted
            ? text.body.copyWith(color: colors.ink3)
            : text.body.copyWith(fontWeight: FontWeight.w500);

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s8),
        child: Row(
          children: [
            // The label keeps its words; a long value wraps beside it.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * (row.value == null ? .6 : .4)),
              child: Text(
                row.label,
                style:
                    acts ? text.body.copyWith(fontWeight: FontWeight.w500) : text.bodySmall.copyWith(color: colors.ink2),
              ),
            ),
            const SizedBox(width: BasakSpace.s12),
            Expanded(
              child: row.value == null
                  ? const SizedBox.shrink()
                  : Text(
                      row.value!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: row.ltrValue ? TextDirection.ltr : null,
                      // A left-to-right value still sits at the row's end edge.
                      textAlign: row.ltrValue && rtl ? TextAlign.start : TextAlign.end,
                      style: valueStyle,
                    ),
            ),
            if (row.mark != null) ...[const SizedBox(width: BasakSpace.s8), row.mark!],
            if (row.locked) ...[
              const SizedBox(width: BasakSpace.s6),
              Icon(LucideIcons.lock, size: 14, color: colors.ink3, semanticLabel: 'لا يمكن تغييرها'),
            ],
            if (row.trailing != null) ...[
              const SizedBox(width: BasakSpace.s10),
              row.trailing!,
            ] else if (row.onTap != null) ...[
              const SizedBox(width: BasakSpace.s6),
              Icon(
                row.external
                    ? LucideIcons.externalLink
                    : (rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight),
                size: row.external ? 16 : 18,
                color: colors.ink3,
              ),
            ],
          ],
        ),
      ),
    );

    return row.onTap == null
        ? KeyedSubtree(key: row.key, child: content)
        : BasakPressable(key: row.key, onTap: row.onTap, child: content);
  }
}

/// The last line of the account page: a quiet red link and the app's version.
class QuietFooter extends StatelessWidget {
  final String actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  /// "1.0.6". Hidden while unknown.
  final String? version;

  const QuietFooter({super.key, required this.actionLabel, required this.onAction, this.actionKey, this.version});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final quiet = text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        BasakPressable(
          key: actionKey,
          onTap: onAction,
          child: Center(
            widthFactor: 1,
            child: Text(actionLabel, style: text.label.copyWith(color: colors.danger)),
          ),
        ),
        if (version != null && version!.isNotEmpty) ...[
          const SizedBox(width: BasakSpace.s14),
          ExcludeSemantics(child: Text('·', style: quiet)),
          const SizedBox(width: BasakSpace.s14),
          Text(version!, textDirection: TextDirection.ltr, style: quiet),
        ],
      ],
    );
  }
}

TextStyle _fieldLabel(BuildContext context, {bool error = false}) =>
    context.text.label.copyWith(color: error ? context.colors.danger : context.colors.ink2);

TextStyle _fieldValue(BuildContext context) => context.text.rowTitle.copyWith(fontWeight: FontWeight.w400);

/// A typed field of a sheet: its label over a 54 box, sunken at rest, white
/// with a teal ring while it is being typed in. The error takes the place
/// under the box.
class SheetField extends StatefulWidget {
  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? error;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? maxLength;

  /// Emails and numbers: typed left to right, still at the start edge.
  final bool ltr;
  final bool autocorrect;
  final ValueChanged<String>? onChanged;

  const SheetField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.error,
    this.keyboardType,
    this.textInputAction,
    this.maxLength,
    this.ltr = false,
    this.autocorrect = true,
    this.onChanged,
  });

  @override
  State<SheetField> createState() => _SheetFieldState();
}

class _SheetFieldState extends State<SheetField> {
  final _node = FocusNode();

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  @override
  void dispose() {
    _node
      ..removeListener(_onFocus)
      ..dispose();
    super.dispose();
  }

  void _onFocus() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final hasError = widget.error != null;
    final focused = _node.hasFocus;
    final ring = hasError ? colors.danger : (focused ? colors.teal : null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: _fieldLabel(context, error: hasError)),
        const SizedBox(height: BasakSpace.s6),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _node.requestFocus,
          child: AnimatedContainer(
            duration: BasakMotion.fade,
            constraints: const BoxConstraints(minHeight: 54),
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16),
            decoration: BoxDecoration(
              color: focused || hasError ? colors.surface : colors.sunken,
              borderRadius: BasakRadius.all(BasakRadius.control),
              border: Border.all(color: ring ?? Colors.transparent, width: 2),
            ),
            child: TextField(
              controller: widget.controller,
              focusNode: _node,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              maxLength: widget.maxLength,
              autocorrect: widget.autocorrect,
              onChanged: widget.onChanged,
              textDirection: widget.ltr ? TextDirection.ltr : null,
              textAlign: widget.ltr && rtl ? TextAlign.end : TextAlign.start,
              style: _fieldValue(context),
              cursorColor: colors.teal,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                // 24 of text, 12 above and below, 2 of ring: the 54 of the box.
                contentPadding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s12),
                counterText: '',
                hintText: widget.hint,
                hintTextDirection: widget.ltr ? TextDirection.ltr : null,
                hintStyle: _fieldValue(context).copyWith(color: colors.ink3),
              ),
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: BasakSpace.s4, start: BasakSpace.s4),
            child: Text(widget.error!, style: context.text.caption.copyWith(color: colors.danger)),
          ),
      ],
    );
  }
}

/// A field of a sheet whose value is picked, not typed (a date): the same
/// label and box as [SheetField], a glyph at the end, and a way to clear it.
class SheetValueField extends StatelessWidget {
  final String label;
  final String? value;
  final String placeholder;
  final IconData icon;
  final VoidCallback? onTap;

  /// Shown only while there is a value.
  final VoidCallback? onClear;

  const SheetValueField({
    super.key,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.icon,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _fieldLabel(context)),
        const SizedBox(height: BasakSpace.s6),
        Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsetsDirectional.only(start: BasakSpace.s16, end: BasakSpace.s4),
          decoration: BoxDecoration(color: colors.sunken, borderRadius: BasakRadius.all(BasakRadius.control)),
          child: Row(
            children: [
              Expanded(
                child: BasakPressable(
                  onTap: onTap,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          value ?? placeholder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _fieldValue(context).copyWith(color: value == null ? colors.ink3 : colors.ink),
                        ),
                      ),
                      if (value == null || onClear == null) ...[
                        Icon(icon, size: 18, color: colors.ink3),
                        const SizedBox(width: BasakSpace.s12),
                      ],
                    ],
                  ),
                ),
              ),
              if (value != null && onClear != null)
                BasakPressable(
                  onTap: onClear,
                  semanticLabel: 'حذف',
                  child: Icon(LucideIcons.x, size: 18, color: colors.ink3),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One line of a [LinkRows] block.
class LinkRow {
  /// A glyph in a neutral tile.
  final IconData? icon;

  /// A person: their photo, or the first letter of this name, in a circle.
  final String? person;
  final ImageProvider? photo;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Key? key;

  const LinkRow({this.icon, this.person, this.photo, required this.title, this.subtitle, this.onTap, this.key})
      : assert(icon != null || person != null);
}

/// People and places to turn to, inside a sheet: a ground-coloured block of
/// rows 64 high, each with a chevron.
class LinkRows extends StatelessWidget {
  final List<LinkRow> rows;

  const LinkRows({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return BasakCard(
      color: colors.ground,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: colors.hairline),
            BasakPressable(
              key: rows[i].key,
              onTap: rows[i].onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(vertical: BasakSpace.s10),
                  child: Row(
                    children: [
                      if (rows[i].person != null)
                        PhotoRing(name: rows[i].person!, image: rows[i].photo, size: 40)
                      else
                        ToneTile(rows[i].icon!),
                      const SizedBox(width: BasakSpace.s12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rows[i].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.body.copyWith(fontWeight: FontWeight.w500),
                            ),
                            if (rows[i].subtitle != null)
                              Text(
                                rows[i].subtitle!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: BasakSpace.s8),
                      Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 18, color: colors.ink3),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A question that cannot be undone, asked in the middle of the screen: a
/// glyph, the question, what follows from a yes, and two words to answer with.
abstract final class BasakDialog {
  /// True when the user chose [confirmLabel].
  static Future<bool> confirm(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = 'إلغاء',
    BasakTone tone = BasakTone.danger,
  }) async =>
      await showDialog<bool>(
        context: context,
        barrierColor: context.colors.scrim,
        builder: (context) => BasakDialogFrame(
          icon: icon,
          title: title,
          message: message,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
          tone: tone,
          onAnswer: (yes) => Navigator.of(context).pop(yes),
        ),
      ) ??
      false;
}

/// What the dialog looks like, apart from how it is opened.
class BasakDialogFrame extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final BasakTone tone;
  final ValueChanged<bool> onAnswer;

  const BasakDialogFrame({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onAnswer,
    this.cancelLabel = 'إلغاء',
    this.tone = BasakTone.danger,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    Widget answer(String label, Color color, bool value) => BasakPressable(
          onTap: () => onAnswer(value),
          child: Center(
            widthFactor: 1,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s16),
              child: Text(label, style: text.body.copyWith(color: color, fontWeight: FontWeight.w500)),
            ),
          ),
        );

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: basakMaxTextScale,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: BasakSpace.s28, vertical: BasakSpace.s24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: BasakSpace.maxContentWidth - 2 * BasakSpace.s28),
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(22, 22, 22, BasakSpace.s12),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BasakRadius.all(BasakRadius.sheet),
              boxShadow: BasakShadow.floating,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: tone.tint(colors), borderRadius: BasakRadius.all(22)),
                      child: Icon(icon, size: 28, color: tone.foreground(colors)),
                    ),
                  ),
                  const SizedBox(height: BasakSpace.s14),
                  Semantics(header: true, child: Text(title, style: text.sheetTitle)),
                  const SizedBox(height: BasakSpace.s10),
                  Text(message, style: text.body.copyWith(color: colors.ink2)),
                  const SizedBox(height: BasakSpace.s16),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Wrap(
                      spacing: BasakSpace.s8,
                      children: [
                        answer(cancelLabel, colors.ink, false),
                        answer(confirmLabel, tone.foreground(colors), true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
