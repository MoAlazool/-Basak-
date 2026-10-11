import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_errors.dart';
import '../../../core/ui/ui.dart';
import 'offers_repository.dart';

/// «إظهار العروض» on the account page, or null where offers do not exist for
/// this phone (an older server, or nothing known yet): no row.
SettingRow? offersSettingRow(WidgetRef ref) {
  final offers = ref.watch(offersProvider).valueOrNull;
  if (offers == null || !offers.available) return null;
  return const SettingRow(
    key: Key('profile-offers'),
    label: OffersSwitch.label,
    trailing: OffersSwitch(),
  );
}

/// The student's own switch for offers. It moves at once; if the server
/// cannot be told, it goes back and the reason is said.
class OffersSwitch extends ConsumerStatefulWidget {
  const OffersSwitch({super.key});

  static const label = 'إظهار العروض';

  @override
  ConsumerState<OffersSwitch> createState() => _OffersSwitchState();
}

class _OffersSwitchState extends ConsumerState<OffersSwitch> {
  /// What the student just chose, until the server's answer is on screen.
  bool? _chosen;

  Future<void> _set(bool shown) async {
    if (_chosen != null) return;
    setState(() => _chosen = shown);
    try {
      await ref.read(offersRepoProvider).setHidden(!shown);
      // Home's strip follows: gone, or back with the offers read again.
      ref.invalidate(offersProvider);
      await ref.read(offersProvider.future);
    } catch (error) {
      if (mounted) BasakToast.show(context, errorMessage(error), kind: BasakToastKind.failure);
    }
    if (mounted) setState(() => _chosen = null);
  }

  @override
  Widget build(BuildContext context) {
    final hidden = ref.watch(offersProvider).valueOrNull?.hidden ?? false;
    return BasakSwitch(
      key: const Key('offers-switch'),
      label: OffersSwitch.label,
      value: _chosen ?? !hidden,
      onChanged: _chosen != null ? null : _set,
    );
  }
}
