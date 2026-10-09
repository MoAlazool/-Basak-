import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/media/image_optimizer.dart';
import '../../../../core/media/picker_errors.dart';
import '../../../../core/network/network_errors.dart';
import '../../../../core/network/perf_trace.dart';
import '../../../../core/storage/offline_cache.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/widgets/connection_strip_host.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../home/presentation/supervisor_contact_sheet.dart';
import '../data/subscription_repository.dart';
import '../models/payment_method_model.dart';
import '../models/subscription_model.dart';
import 'purchase_flow.dart' show formatMoney;
import 'receipt_card.dart';
import 'subscription_screen.dart';

/// The image the student chose for a subscription's receipt: its file, the
/// attempt it belongs to (which names the stored file across retries) and its
/// preparation, started the moment it was chosen.
class _ReceiptDraft {
  final XFile file;
  final ReceiptAttempt attempt;
  final Future<Uint8List> prepared;

  _ReceiptDraft(this.file, this.attempt, this.prepared);
}

/// Paying for one subscription, as a page: the amount once, the company's
/// transfer details, and the receipt's picture. The selection is fixed here —
/// the student pays for this subscription or sends its receipt again.
///
/// The same page says how the sending goes (the three [ReceiptPhase]s, with
/// the part of the image that has really left the phone), what came of it,
/// why the company refused the last receipt, and when nothing more can be sent.
class PayScreen extends ConsumerStatefulWidget {
  final SubscriptionModel subscription;

  /// "العودة للرئيسية" after the receipt is sent: shows the Home tab.
  final VoidCallback? onGoHome;

  const PayScreen({super.key, required this.subscription, this.onGoHome});

  static Future<void> open(BuildContext context, SubscriptionModel subscription, {VoidCallback? onGoHome}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => PayScreen(subscription: subscription, onGoHome: onGoHome)));

  /// A receipt may be sent five times for one subscription.
  static const maxAttempts = 5;

  /// Stands in for the phone's camera and photo library.
  @visibleForTesting
  static Future<XFile?> Function(ImageSource source)? debugPickImage;

  @override
  ConsumerState<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends ConsumerState<PayScreen> {
  _ReceiptDraft? _draft;

  /// Where the receipt being sent is (null: nothing is being sent).
  ReceiptPhase? _phase;

  /// The part of the image that has left the phone, when it can be known.
  double? _progress;

  /// The method the student picked (null: the one offered first).
  String? _methodId;

  /// After a refusal the method is a single row; "تغيير" opens the choice again.
  bool _changingMethod = false;

  bool get _sending => _phase != null && _phase != ReceiptPhase.done;

  void _toast(String message, {BasakToastKind kind = BasakToastKind.success}) =>
      BasakToast.show(context, message, kind: kind);

  void _copy(String value) {
    Clipboard.setData(ClipboardData(text: value));
    _toast('تم النسخ');
  }

  void _stay() => _toast('ابقَ في هذه الصفحة حتى يكتمل الإرسال.', kind: BasakToastKind.info);

  Future<void> _pick(ImageSource source) async {
    if (_sending) return;
    final subscriptionId = widget.subscription.id;
    try {
      // Asked for at the stored size, so the phone's own encoder shrinks it
      // (camera photos are 12 MP and more) and little is left to do in Dart.
      final picked = await (PayScreen.debugPickImage?.call(source) ??
          ImagePicker().pickImage(
              source: source,
              imageQuality: ImageOptimizer.pickQuality,
              maxWidth: ImageOptimizer.pickMaxSide,
              maxHeight: ImageOptimizer.pickMaxSide));
      if (picked == null || !mounted) return;
      // Made ready now, in the background, not when "send" is tapped. A file
      // that cannot be read is told when it is sent.
      final prepared = ImageOptimizer.prepareReceipt(picked.path)..ignore();
      setState(() => _draft = _ReceiptDraft(picked, ReceiptAttempt.start(subscriptionId), prepared));
    } catch (e) {
      if (mounted) _toast(pickerErrorMessage(e), kind: BasakToastKind.failure);
    }
  }

  void _remove() {
    // While the image is still being made ready this simply drops it; once it
    // is on its way it can no longer be taken back.
    if (_phase != null && _phase != ReceiptPhase.preparing) return;
    setState(() {
      _draft = null;
      _phase = null;
      _progress = null;
    });
  }

  Future<void> _submit({required String? methodId, required bool needsMethod}) async {
    final draft = _draft;
    if (draft == null || _phase != null) return;
    if (needsMethod && methodId == null) {
      _toast('اختر وسيلة الدفع التي حوّلت بها أولاً.', kind: BasakToastKind.info);
      return;
    }

    // Shown in the same frame as the tap.
    setState(() {
      _phase = ReceiptPhase.preparing;
      _progress = null;
    });
    try {
      PerfTrace.reset();
      // Only the optimised image is uploaded; the original stays on the phone.
      final bytes = await PerfTrace.time('receipt.prepare (left after the tap)', () => draft.prepared);
      // Removed while it was being made ready.
      if (!mounted || _draft != draft) return;

      await PerfTrace.time(
          'receipt.send',
          () => ref.read(receiptSubmitterProvider).submit(
                attempt: draft.attempt,
                bytes: bytes,
                paymentMethodId: methodId,
                onPhase: (phase) {
                  if (mounted) setState(() => _phase = phase);
                },
                onProgress: (sent, total) {
                  final progress = total <= 0 ? null : sent / total;
                  // A repaint per percent is plenty.
                  if (mounted && (progress == null || _progress == null || progress - _progress! >= 0.01)) {
                    setState(() => _progress = progress);
                  }
                },
              ));
      PerfTrace.dump('receipt upload, ${bytes.length ~/ 1024} kB');
      if (!mounted) return;
      setState(() {
        _phase = ReceiptPhase.done;
        _progress = 1;
      });
    } catch (e) {
      if (mounted) {
        // The image stays chosen: sending again replaces the same file.
        setState(() {
          _phase = null;
          _progress = null;
        });
        _toast(errorMessage(e), kind: BasakToastKind.failure);
      }
    }
  }

  void _contact(SubscriptionModel sub) {
    final phone = (sub.supervisorPhone ?? '').trim();
    if (phone.isEmpty) return;
    SupervisorContactSheet.show(context,
        name: (sub.supervisorName ?? '').trim(), phone: phone, lineName: sub.lineName);
  }

  void _showRejected(List<ReceiptModel> receipts) {
    final rejected = receipts.where((r) => r.isRejected).toList();
    BasakSheet.show<void>(
      context,
      title: 'الإيصالات المرفوضة',
      builder: (context) => InfoRows(
        sunken: true,
        rows: [
          for (final r in rejected)
            InfoRow(
              label: 'المحاولة ${r.attemptNumber}',
              caption: ReceiptCard.day(r.createdAt),
              value: (r.rejectionReason ?? '').trim().isEmpty ? '—' : r.rejectionReason!.trim(),
            ),
        ],
      ),
    );
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    widget.onGoHome?.call();
  }

  static String _methodCaption(PaymentMethodModel m) => switch (m.type) {
        'instapay' => 'InstaPay',
        'vodafone_cash' => 'محفظة ${m.displayName}',
        _ => (m.bankName ?? '').trim().isEmpty ? 'تحويل بنكي' : 'تحويل بنكي · ${m.bankName!.trim()}',
      };

  /// What to do before transferring: the whole amount at once, then whatever
  /// the company itself asks for.
  static List<String> _beforeTransfer(PaymentMethodModel? m) => [
        'حوّل المبلغ كاملاً في عملية واحدة.',
        for (final line in (m?.instructions ?? '').split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];

  @override
  Widget build(BuildContext context) {
    final sub = ref.watch(allSubscriptionsProvider).valueOrNull?.where((s) => s.id == widget.subscription.id).firstOrNull ??
        widget.subscription;
    final receiptsAsync = ref.watch(subscriptionReceiptsProvider(sub.id));
    final receipts = receiptsAsync.valueOrNull ?? const <ReceiptModel>[];
    final latest = receipts.isEmpty ? null : receipts.first;
    final methodsAsync = sub.companyId == null ? null : ref.watch(paymentMethodsProvider(sub.companyId!));
    final methods = methodsAsync?.valueOrNull ?? const <PaymentMethodModel>[];

    final Widget page;
    if (_phase == ReceiptPhase.done || (sub.isPendingReview && !_sending)) {
      page = _done(sub);
    } else {
      page = ValueListenableBuilder<DateTime?>(
        valueListenable: OfflineCache.offlineSince,
        builder: (context, offlineSince, _) => _form(
          sub: sub,
          receipts: receipts,
          latest: latest,
          methods: methods,
          methodsLoading: methodsAsync != null && methodsAsync.isLoading && !methodsAsync.hasValue,
          methodsFailed: methodsAsync != null && methodsAsync.hasError && !methodsAsync.hasValue,
          receiptsLoading: receiptsAsync.isLoading && !receiptsAsync.hasValue,
          offline: offlineSince != null,
        ),
      );
    }

    return PopScope(
      // The system's back must not lose an upload in progress.
      canPop: !_sending,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stay();
      },
      child: Scaffold(backgroundColor: context.colors.ground, body: page),
    );
  }

  /// "استلمنا إيصالك": the only place that says what happens next.
  Widget _done(SubscriptionModel sub) {
    final company = (sub.companyName ?? '').trim();
    return BasakPage(
      dock: _BottomActions(children: [
        BasakButton(key: const Key('pay-done-home'), label: 'العودة للرئيسية', onPressed: _goHome),
        SheetLink(label: 'عرض الطلب', onTap: () => Navigator.of(context).maybePop()),
      ]),
      children: [
        SizedBox(
          height: (MediaQuery.sizeOf(context).height * .62).clamp(320.0, 620.0),
          child: Center(
            child: ResultBody(
              key: const Key('receipt-phase-done'),
              title: 'استلمنا إيصالك',
              message: 'تراجعه ${company.isEmpty ? 'إدارة الشركة' : company}، وسيصلك إشعار عند تفعيل اشتراكك.',
            ),
          ),
        ),
      ],
    );
  }

  Widget _form({
    required SubscriptionModel sub,
    required List<ReceiptModel> receipts,
    required ReceiptModel? latest,
    required List<PaymentMethodModel> methods,
    required bool methodsLoading,
    required bool methodsFailed,
    required bool receiptsLoading,
    required bool offline,
  }) {
    final colors = context.colors;
    final text = context.text;
    final attempts = receipts.length;
    final rejected = sub.isRejected || latest?.isRejected == true;
    final exhausted = attempts >= PayScreen.maxAttempts && !_sending;
    final noMethods = methods.isEmpty && !methodsLoading && !methodsFailed;
    // The method the student last said they used, otherwise the first offered.
    final selected = methods.where((m) => m.id == _methodId).firstOrNull ??
        methods.where((m) => m.id == latest?.paymentMethodId).firstOrNull ??
        methods.firstOrNull;
    final draft = _draft;
    final phase = draft == null ? null : _phase;
    final money = formatMoney(sub.price);
    final quiet = text.label.copyWith(color: colors.ink2, fontWeight: FontWeight.w400);

    final amount = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('المبلغ المطلوب · ${sub.periodName}',
            key: const Key('amount-label'),
            style: text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400)),
        const SizedBox(height: BasakSpace.s2),
        Row(
          children: [
            Expanded(
              child: MoneyText(money, key: const Key('amount-value'), style: text.amount, unitSize: 16),
            ),
            if (!_sending) ...[
              const SizedBox(width: BasakSpace.s12),
              BasakButton(
                key: const Key('amount-copy'),
                label: 'نسخ المبلغ',
                icon: LucideIcons.copy,
                variant: BasakButtonVariant.surface,
                size: BasakButtonSize.small,
                expand: false,
                onPressed: () => _copy(sub.price.toStringAsFixed(0)),
              ),
            ],
          ],
        ),
      ],
    );

    final rejection = !rejected
        ? null
        : RejectionCard(
            attempt: attempts >= 1 && attempts < PayScreen.maxAttempts
                ? 'المحاولة ${attempts + 1} من ${PayScreen.maxAttempts}'
                : null,
            reason: (latest?.rejectionReason ?? '').trim().isEmpty
                ? 'راجع سبب الرفض مع إدارة الشركة ثم ارفع إيصالاً جديداً.'
                : latest!.rejectionReason!.trim(),
          );

    final chosenMethod = selected == null
        ? null
        : BuilderRow(
            state: BuilderRowState.chosen,
            step: 1,
            title: 'طريقة الدفع',
            value: _sending || selected.payTo.isEmpty
                ? selected.displayName
                : '${selected.displayName} · ${selected.payTo}',
            onChange: _sending ? null : () => setState(() => _changingMethod = true),
          );

    Widget pickButton(String label, IconData icon, ImageSource source, BasakButtonVariant variant) => BasakButton(
          key: Key(source == ImageSource.camera ? 'receipt-camera' : 'receipt-gallery'),
          label: label,
          icon: icon,
          variant: variant,
          size: BasakButtonSize.small,
          onPressed: () => _pick(source),
        );

    /// The picture: the dashed zone that asks for it, the picture once chosen,
    /// or the picture on its way.
    Widget upload({String? zoneTitle, required String requirement, required BasakButtonVariant buttons}) {
      if (receiptsLoading) {
        return const Skeleton(child: SkeletonCard(child: Bone(height: 96, radius: BasakRadius.small)));
      }
      if (draft == null) {
        return UploadZone(
          title: zoneTitle,
          requirement: requirement,
          actions: [
            pickButton('الكاميرا', LucideIcons.camera, ImageSource.camera, buttons),
            pickButton('من الصور', LucideIcons.image, ImageSource.gallery, buttons),
          ],
        );
      }
      final preview = ReceiptPreviewFrame(
        child: Image.file(
          File(draft.file.path),
          key: const Key('receipt-preview'),
          fit: BoxFit.cover,
          // Decoded at the size it is shown, not at the photo's own.
          cacheWidth:
              (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round().clamp(200, 1400),
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.expand(),
        ),
      );
      final remove = BasakButton(
        key: const Key('receipt-remove'),
        label: 'إزالة الصورة',
        icon: LucideIcons.trash2,
        variant: BasakButtonVariant.danger,
        size: BasakButtonSize.small,
        expand: false,
        onPressed: phase == null || phase == ReceiptPhase.preparing ? _remove : null,
      );
      return BasakCard(
        padding: const EdgeInsetsDirectional.all(BasakSpace.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            preview,
            if (phase == null)
              Align(alignment: AlignmentDirectional.centerEnd, child: remove)
            else ...[
              const SizedBox(height: BasakSpace.s16),
              SendProgress(
                key: Key('receipt-phase-${phase.name}'),
                title: switch (phase) {
                  ReceiptPhase.preparing => 'جارٍ تجهيز الصورة',
                  ReceiptPhase.uploading => 'جارٍ رفع الصورة',
                  _ => 'جارٍ إرسال الإيصال',
                },
                // Only the upload has a measurable part; the other steps just run.
                sent: switch (phase) {
                  ReceiptPhase.preparing => null,
                  ReceiptPhase.uploading => _progress ?? 0,
                  _ => 1,
                },
                steps: const ['التجهيز', 'الرفع', 'الإرسال'],
                current: switch (phase) {
                  ReceiptPhase.preparing => 0,
                  ReceiptPhase.uploading => 1,
                  _ => 2,
                },
              ),
            ],
          ],
        ),
      );
    }

    final afterUpload = <Widget>[
      if (_sending)
        Text('ابقَ في هذه الصفحة حتى يكتمل الإرسال.', style: quiet)
      else ...[
        if (offline && draft != null) Text('الإرسال يحتاج اتصالاً بالإنترنت. صورتك محفوظة هنا.', style: quiet),
        if (!rejected && attempts > 0 && attempts < PayScreen.maxAttempts)
          Text('المتبقي ${PayScreen.maxAttempts - attempts} من ${PayScreen.maxAttempts} محاولات',
              textAlign: TextAlign.center, style: text.label.copyWith(color: colors.ink3, fontWeight: FontWeight.w400)),
      ],
    ];

    Widget section(List<Widget> children) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: BasakSpace.s12),
              children[i],
            ],
          ],
        );

    final send = BasakDock(
      child: BasakButton(
        key: const Key('receipt-send'),
        label: 'إرسال للمراجعة',
        loading: _sending,
        loadingLabel: 'جارٍ الإرسال…',
        onPressed: _sending
            ? () {}
            : draft == null || offline
                ? null
                : () => _submit(methodId: selected?.id, needsMethod: methods.isNotEmpty),
      ),
    );

    final back = BasakBackHeader(onBack: _sending ? _stay : null);
    final titledBack = BasakBackHeader(title: 'الدفع', inlineTitle: true, onBack: _sending ? _stay : null);
    final hasPhone = (sub.supervisorPhone ?? '').trim().isNotEmpty;
    final contact = !hasPhone
        ? null
        : BasakButton(
            key: const Key('pay-contact'),
            label: 'تواصل مع الشركة',
            icon: LucideIcons.phone,
            variant: exhausted ? BasakButtonVariant.primary : BasakButtonVariant.secondary,
            onPressed: () => _contact(sub),
          );

    // ── Five receipts were refused: nothing more can be sent.
    if (exhausted && !receiptsLoading) {
      final reason = (latest?.rejectionReason ?? '').trim();
      return BasakPage(
        header: titledBack,
        dock: _BottomActions(children: [
          if (contact != null) contact,
          if (receipts.any((r) => r.isRejected))
            BasakButton(
              key: const Key('pay-rejected-list'),
              label: 'عرض الإيصالات المرفوضة',
              variant: BasakButtonVariant.quiet,
              size: BasakButtonSize.medium,
              onPressed: () => _showRejected(receipts),
            ),
        ]),
        children: [
          BasakCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ToneGlyph(LucideIcons.ban),
                const SizedBox(height: BasakSpace.s14),
                Text('اكتملت المحاولات الخمس', style: text.sheetTitle),
                const SizedBox(height: BasakSpace.s10),
                Text('رُفضت الإيصالات الخمسة لهذا الاشتراك، ولا يمكن رفع إيصال آخر. تواصل مع إدارة الشركة لمساعدتك.',
                    style: text.body.copyWith(color: colors.ink2)),
              ],
            ),
          ),
          InfoRows(rows: [
            if (reason.isNotEmpty) InfoRow(label: 'آخر سبب للرفض', value: reason),
            InfoRow(
                label: 'المبلغ المطلوب',
                value: money,
                labelKey: const Key('amount-label'),
                valueKey: const Key('amount-value')),
          ]),
        ],
      );
    }

    // ── The company has not said where to transfer yet.
    if (noMethods) {
      return BasakPage(
        header: titledBack,
        dock: draft != null ? send : (contact == null ? null : _BottomActions(children: [contact])),
        children: [
          const ConnectionStripHost(),
          BasakCard(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: BasakSpace.s18, vertical: BasakSpace.s16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المبلغ المطلوب',
                    key: const Key('amount-label'), style: text.caption.copyWith(color: colors.ink3)),
                MoneyText(money, key: const Key('amount-value'), style: text.display, unitSize: 14),
              ],
            ),
          ),
          if (rejection != null) rejection,
          const NoticeCard(
            key: Key('payment-notes'),
            message: 'لم تضف الشركة بيانات التحويل بعد. تواصل مع إدارة الشركة للحصول عليها، ثم ارفع إيصالك هنا.',
          ),
          upload(
            zoneTitle: 'ارفع الإيصال',
            requirement: 'صورة واضحة فيها رقم العملية والتاريخ',
            buttons: BasakButtonVariant.tonal,
          ),
          ...afterUpload,
        ],
      );
    }

    // ── Pay and upload; after a refusal, the reason first.
    final collapsed = chosenMethod != null && (_sending || (rejected && !_changingMethod));
    return BasakPage(
      header: back,
      spacing: BasakSpace.s24,
      dock: send,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [const ConnectionStripHost(padding: EdgeInsetsDirectional.only(bottom: BasakSpace.s12)), amount],
        ),
        if (rejection != null && !_sending) rejection,
        if (collapsed)
          chosenMethod
        else if (methodsLoading)
          const Skeleton(
            child: SkeletonCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Bone(width: 150, height: 16),
                  SizedBox(height: BasakSpace.s18),
                  Bone(height: 12),
                  SizedBox(height: BasakSpace.s14),
                  Bone(width: 180, height: 12),
                ],
              ),
            ),
          )
        else if (methodsFailed)
          InlineError(
            message: 'تعذّر تحميل بيانات التحويل',
            onRetry: () => ref.invalidate(paymentMethodsProvider(sub.companyId!)),
          )
        else
          section([
            SectionHead(rejected ? 'طريقة الدفع' : '1 · حوّل المبلغ'),
            if (methods.length > 1 || selected == null)
              BasakChips<PaymentMethodModel>(
                options: methods,
                value: selected,
                onChanged: (m) => setState(() => _methodId = m.id),
                label: (m) => m.displayName,
              ),
            if (selected != null)
              KeyedSubtree(
                key: const Key('payment-methods'),
                child: PayeeCard(
                  name: (selected.accountHolder ?? '').trim().isNotEmpty
                      ? selected.accountHolder!.trim()
                      : ((sub.companyName ?? '').trim().isNotEmpty ? sub.companyName!.trim() : selected.displayName),
                  method: _methodCaption(selected),
                  fields: [
                    if (selected.payTo.isNotEmpty)
                      CopyField(
                        label: switch (selected.type) {
                          'instapay' => 'عنوان InstaPay',
                          'vodafone_cash' => 'رقم المحفظة',
                          _ => 'رقم الحساب',
                        },
                        value: selected.payTo,
                        onCopy: () => _copy(selected.payTo),
                      ),
                    if (selected.type == 'bank' && (selected.iban ?? '').trim().isNotEmpty)
                      CopyField(label: 'IBAN', value: selected.iban!.trim(), onCopy: () => _copy(selected.iban!.trim())),
                  ],
                ),
              ),
            Disclosure(
              key: const Key('payment-notes'),
              icon: LucideIcons.info,
              title: 'قبل التحويل',
              child: NumberedList(items: _beforeTransfer(selected)),
            ),
          ]),
        section([
          SectionHead(rejected && !_sending ? 'ارفع إيصالاً جديداً' : '2 · ارفع الإيصال'),
          upload(
            requirement: rejected ? 'صورة واضحة برقم العملية والتاريخ' : 'صورة واضحة فيها رقم العملية والتاريخ',
            buttons: BasakButtonVariant.surface,
          ),
          ...afterUpload,
        ]),
      ],
    );
  }
}

/// The exits of a page that has no dock: one button, and a quiet way out under it.
class _BottomActions extends StatelessWidget {
  final List<Widget> children;

  const _BottomActions({required this.children});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final safe = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
          BasakSpace.gutter, BasakSpace.s8, BasakSpace.gutter, safe > 0 ? safe + BasakSpace.s8 : BasakSpace.s20),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: BasakSpace.maxContentWidth - 2 * BasakSpace.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: BasakSpace.s2),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
