import 'dart:async';

import 'package:flutter/material.dart';

import '../storage/offline_cache.dart';
import '../ui/ui.dart';
import 'basak_ui.dart' show BasakUi;

/// Shows the [ConnectionStrip] for as long as it has something to say: amber
/// with the time of the saved data while the server cannot be reached
/// ([OfflineCache.offlineSince]), then green for [BasakMotion.backOnline]
/// once it answers again. Nothing at all while online.
///
/// Two ways to place it. Inside a page, under its header: leave [child] out,
/// and [padding] is added only while the strip is there. Above a whole page:
/// pass the page as [child], and the strip takes the top of the screen (the
/// page then starts under it, not under the status bar).
class ConnectionStripHost extends StatefulWidget {
  final Widget? child;

  /// Offline only: reads everything again.
  final VoidCallback? onRetry;

  /// Offline only: one more fact after the time.
  final String? note;

  /// Around the strip, only while it is shown.
  final EdgeInsetsGeometry padding;

  /// Off: nothing is shown (and [child] is passed through). The shell uses it
  /// on the tab whose page places its own strip.
  final bool enabled;

  const ConnectionStripHost({
    super.key,
    this.child,
    this.onRetry,
    this.note,
    this.padding = EdgeInsets.zero,
    this.enabled = true,
  });

  /// When the data on screen was saved: the time alone for today's
  /// ("8:15 ص"), the day before it otherwise ("3 أكتوبر 9:40 م").
  static String dataTime(DateTime savedAt, [DateTime? now]) {
    final at = savedAt.toLocal();
    final today = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final time = BasakUi.time12('${two(at.hour)}:${two(at.minute)}');
    return DateUtils.isSameDay(at, today) ? time : '${at.day} ${BasakUi.arabicMonths[at.month - 1]} $time';
  }

  @override
  State<ConnectionStripHost> createState() => _ConnectionStripHostState();
}

class _ConnectionStripHostState extends State<ConnectionStripHost> {
  DateTime? _since = OfflineCache.offlineSince.value;
  bool _backOnline = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    OfflineCache.offlineSince.addListener(_changed);
  }

  @override
  void dispose() {
    OfflineCache.offlineSince.removeListener(_changed);
    _hide?.cancel();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final since = OfflineCache.offlineSince.value;
    final reconnected = _since != null && since == null;
    _hide?.cancel();
    setState(() {
      _since = since;
      _backOnline = reconnected;
    });
    if (reconnected) {
      _hide = Timer(BasakMotion.backOnline, () {
        if (mounted) setState(() => _backOnline = false);
      });
    }
  }

  ConnectionStrip? get _strip {
    if (!widget.enabled) return null;
    final since = _since;
    if (since != null) {
      return ConnectionStrip(
        key: const ValueKey('connection-offline'),
        state: ConnectionStripState.offline,
        dataTime: ConnectionStripHost.dataTime(since),
        note: widget.note,
        onRetry: widget.onRetry,
      );
    }
    if (_backOnline) {
      return const ConnectionStrip(key: ValueKey('connection-back'), state: ConnectionStripState.backOnline);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final strip = _strip;
    final child = widget.child;

    final slot = AnimatedSize(
      duration: BasakMotion.fade,
      curve: BasakMotion.fadeCurve,
      alignment: AlignmentDirectional.topCenter,
      child: AnimatedSwitcher(
        duration: BasakMotion.fade,
        switchInCurve: BasakMotion.fadeCurve,
        // The strip that leaves makes way at once; only the new one fades in.
        layoutBuilder: (current, previous) => current ?? const SizedBox(width: double.infinity),
        child: strip == null
            ? const SizedBox(key: ValueKey('connection-none'), width: double.infinity)
            : Padding(key: strip.key, padding: widget.padding, child: strip),
      ),
    );
    if (child == null) return slot;

    return ColoredBox(
      color: context.colors.ground,
      child: Column(
        children: [
          if (strip != null)
            SafeArea(
              bottom: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: BasakSpace.maxContentWidth),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        BasakSpace.gutter, BasakSpace.s8, BasakSpace.gutter, 0),
                    child: slot,
                  ),
                ),
              ),
            ),
          Expanded(
            // Always the same shape, so the page under it keeps its state.
            child: MediaQuery.removePadding(context: context, removeTop: strip != null, child: child),
          ),
        ],
      ),
    );
  }
}
