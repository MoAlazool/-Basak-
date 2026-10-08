import 'package:flutter/material.dart';

/// Placeholders shown only on a true first load, when nothing is saved yet.
/// Each one has the shape of the screen it stands in for, so nothing jumps
/// when the data arrives. (With saved data, the data itself is shown at once
/// and refreshed behind; see OfflineCache.readThrough.)

/// One grey block.
class Bone extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final Color color;

  const Bone({super.key, this.width, this.height = 12, this.radius = 8, this.color = const Color(0xFFE4EDF2)});

  const Bone.circle(double size, {super.key, this.color = const Color(0xFFE4EDF2)})
      : width = size,
        height = size,
        radius = 999;

  @override
  Widget build(BuildContext context) => Container(
      width: width, height: height, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)));
}

/// Makes the bones under it breathe, and tells screen readers the page is loading.
class Skeleton extends StatefulWidget {
  final Widget child;
  const Skeleton({super.key, required this.child});

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  // Still under `flutter test`: an endless animation would never settle.
  static const _animate = !bool.fromEnvironment('FLUTTER_TEST');
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900), lowerBound: .55, upperBound: 1);

  @override
  void initState() {
    super.initState();
    if (_animate) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'جاري التحميل',
        child: ExcludeSemantics(
          child: _animate && !MediaQuery.disableAnimationsOf(context)
              ? FadeTransition(opacity: _pulse, child: widget.child)
              : widget.child,
        ),
      );
}

/// A white rounded card, as the app's own cards.
class SkeletonCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;

  const SkeletonCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.radius = 20,
      this.color = Colors.white});

  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
      child: child);
}

/// "icon  label     value": the row most cards are made of.
class SkeletonRow extends StatelessWidget {
  final double label;
  final double value;
  const SkeletonRow({super.key, this.label = 70, this.value = 120});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          const Bone.circle(16),
          const SizedBox(width: 8),
          Bone(width: label, height: 10),
          const SizedBox(width: 16),
          Flexible(child: Bone(width: value, height: 12)),
        ]),
      );
}

/// A list of rows with an avatar or icon, a title and a line under it.
class SkeletonList extends StatelessWidget {
  final int rows;
  final bool avatars;
  const SkeletonList({super.key, this.rows = 4, this.avatars = true});

  @override
  Widget build(BuildContext context) => Skeleton(
        child: Column(children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SkeletonCard(
                padding: const EdgeInsets.all(14),
                radius: 18,
                child: Row(children: [
                  if (avatars) ...[const Bone.circle(40), const SizedBox(width: 12)],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Bone(width: 130.0 + (i.isEven ? 30 : 0), height: 13),
                      const SizedBox(height: 8),
                      Bone(width: 190.0 - (i.isEven ? 0 : 40), height: 10),
                    ]),
                  ),
                ]),
              ),
            ),
        ]),
      );
}

/// Student home: the blue subscription card, then the ride confirmation card.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    const onBlue = Color(0x33FFFFFF);
    return Skeleton(
      child: Column(children: [
        SkeletonCard(
          color: const Color(0xFF2F7FA3),
          radius: 26,
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Row(children: [
              Flexible(child: Bone(width: 150, height: 16, color: onBlue)),
              Spacer(),
              Bone(width: 80, height: 24, radius: 14, color: onBlue),
            ]),
            SizedBox(height: 14),
            Bone(width: 200, height: 11, color: onBlue),
            SizedBox(height: 18),
            Bone(height: 66, radius: 18, color: onBlue),
            SizedBox(height: 14),
            Bone(width: 220, height: 10, color: onBlue),
          ]),
        ),
        const SizedBox(height: 18),
        SkeletonCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Bone(width: 140, height: 14),
            SizedBox(height: 14),
            Bone(height: 48, radius: 14),
            SizedBox(height: 10),
            Bone(height: 48, radius: 14),
          ]),
        ),
      ]),
    );
  }
}

/// "اشتراكاتي": a title, a section label and subscription cards.
class SubscriptionsSkeleton extends StatelessWidget {
  final int cards;
  const SubscriptionsSkeleton({super.key, this.cards = 2});

  @override
  Widget build(BuildContext context) => Skeleton(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Bone(width: 130, height: 22),
            const SizedBox(height: 18),
            const Bone(width: 110, height: 13),
            const SizedBox(height: 10),
            for (var i = 0; i < cards; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SkeletonCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                    Row(children: [
                      Flexible(child: Bone(width: 110, height: 17)),
                      Spacer(),
                      Bone(width: 96, height: 24, radius: 14),
                    ]),
                    SizedBox(height: 12),
                    SkeletonRow(value: 90),
                    SkeletonRow(value: 140),
                    SkeletonRow(value: 80),
                    SkeletonRow(value: 110),
                    SizedBox(height: 6),
                    Align(alignment: AlignmentDirectional.centerEnd, child: Bone(width: 100, height: 12)),
                  ]),
                ),
              ),
          ]),
        ),
      );
}

/// The steps of a new subscription: the progress card, a heading and choices.
class PurchaseFlowSkeleton extends StatelessWidget {
  const PurchaseFlowSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Skeleton(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SkeletonCard(
            child: Column(children: [
              Row(children: const [
                Flexible(child: Bone(width: 90, height: 10)),
                Spacer(),
                Flexible(child: Bone(width: 80, height: 10)),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                for (var i = 0; i < 5; i++) ...[
                  const Bone.circle(30),
                  if (i < 4) const Expanded(child: Bone(height: 2, radius: 1)),
                ],
              ]),
            ]),
          ),
          const SizedBox(height: 20),
          const Bone(width: 170, height: 22),
          const SizedBox(height: 8),
          const Bone(width: 210, height: 11),
          const SizedBox(height: 22),
          const Bone(width: 150, height: 14),
          const SizedBox(height: 12),
          for (var i = 0; i < 2; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SkeletonCard(
                radius: 18,
                child: Row(children: [
                  const Bone.circle(44),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                      Bone(width: 120, height: 14),
                      SizedBox(height: 8),
                      Bone(width: 150, height: 10),
                    ]),
                  ),
                ]),
              ),
            ),
        ]),
      );
}

/// The student card: title, the white card with the name, the code and rows.
class StudentCardSkeleton extends StatelessWidget {
  const StudentCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Skeleton(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Bone(width: 140, height: 22),
            const SizedBox(height: 10),
            const Bone(width: 190, height: 11),
            const SizedBox(height: 16),
            SkeletonCard(
              radius: 26,
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Bone.circle(50),
                  const SizedBox(width: 11),
                  Flexible(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                      Bone(width: 130, height: 15),
                      SizedBox(height: 8),
                      Bone(width: 160, height: 10),
                    ]),
                  ),
                ]),
                const SizedBox(height: 14),
                LayoutBuilder(builder: (context, box) {
                  final side = (box.maxWidth - 22).clamp(150.0, 280.0);
                  return Bone(width: side, height: side, radius: 18);
                }),
                const SizedBox(height: 12),
                const Bone(width: 110, height: 28, radius: 18),
                const SizedBox(height: 16),
                const SkeletonRow(value: 150),
                const SkeletonRow(value: 90),
                const SkeletonRow(value: 80),
              ]),
            ),
          ]),
        ),
      );
}

/// The account page's profile card.
class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Skeleton(
        child: Column(children: const [
          Bone.circle(88),
          SizedBox(height: 14),
          Bone(width: 150, height: 16),
          SizedBox(height: 8),
          Bone(width: 110, height: 11),
          SizedBox(height: 20),
          SkeletonRow(label: 60, value: 170),
          SkeletonRow(label: 50, value: 120),
          SkeletonRow(label: 90, value: 150),
          SkeletonRow(label: 80, value: 100),
          SizedBox(height: 10),
          Bone(height: 44, radius: 14),
        ]),
      );
}

/// Supervisor home: the summary strip, then one card per line.
class SupervisorHomeSkeleton extends StatelessWidget {
  const SupervisorHomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Skeleton(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: const [
            Bone.circle(46),
            SizedBox(width: 12),
            Expanded(child: Bone(height: 16)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: SkeletonCard(
                  padding: const EdgeInsets.all(12),
                  radius: 18,
                  child: Column(children: const [
                    Bone(width: 44, height: 22),
                    SizedBox(height: 8),
                    Bone(width: 60, height: 10),
                  ]),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 16),
          const SkeletonList(rows: 3, avatars: false),
        ]),
      );
}

/// A trip's manifest or a line's rider counts: a header, then rows per station.
class StationRowsSkeleton extends StatelessWidget {
  final int rows;
  const StationRowsSkeleton({super.key, this.rows = 5});

  @override
  Widget build(BuildContext context) => Skeleton(
        child: Column(children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SkeletonCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                radius: 18,
                child: Row(children: [
                  const Bone.circle(14),
                  const SizedBox(width: 10),
                  Flexible(child: Bone(width: 110.0 + (i % 3) * 20, height: 13)),
                  const Spacer(),
                  const Bone(width: 44, height: 22, radius: 12),
                ]),
              ),
            ),
        ]),
      );
}

/// The supervisor's month: the big ring card, then a bar per week.
class MonthlySkeleton extends StatelessWidget {
  const MonthlySkeleton({super.key});

  @override
  Widget build(BuildContext context) => Skeleton(
        child: Column(children: [
          SkeletonCard(
            radius: 24,
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                  Bone(width: 120, height: 14),
                  SizedBox(height: 12),
                  Bone(width: 80, height: 26),
                  SizedBox(height: 12),
                  Bone(width: 150, height: 10),
                ]),
              ),
              const Bone.circle(92),
            ]),
          ),
          const SizedBox(height: 14),
          SkeletonCard(
            child: Column(children: [
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    const Bone(width: 70, height: 10),
                    const SizedBox(width: 12),
                    Expanded(child: Bone(height: 8, radius: 4, width: double.infinity)),
                  ]),
                ),
            ]),
          ),
        ]),
      );
}
