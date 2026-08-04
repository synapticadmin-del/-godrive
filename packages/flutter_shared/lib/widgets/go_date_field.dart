import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';

/// What a date field is *for*.
///
/// The purpose drives the calendar's bounds and — the part that actually
/// fixes the reported problem — which grid the calendar opens on.
enum GoDatePurpose {
  /// Date of birth.
  ///
  /// Opens on the **year grid**. Material's default is [DatePickerMode.day],
  /// which drops a captain born in 1988 onto the current month and expects
  /// them to page backwards ~460 times. Landing on the year grid turns the
  /// same task into three taps: year, month, day.
  birthDate,

  /// Document expiry — national ID, driving licence, vehicle papers.
  /// Forward-looking, and usually within a few years.
  documentExpiry,

  /// A near-future date, e.g. scheduling a ride.
  nearFuture,
}

/// Youngest age we will accept for a captain. Egyptian private-hire rules put
/// the floor at 18; keeping it named makes the intent legible at the call site
/// instead of hiding a magic `18` inside a date subtraction.
const int kMinCaptainAge = 18;

/// Oldest birth year we bother offering. Beyond this the year grid becomes a
/// long scroll of dead options.
const int kMaxCaptainAge = 80;

/// Whole years elapsed between [birth] and [asOf], calendar-correct.
///
/// A plain `difference(...).inDays / 365` drifts by a day per leap year and
/// will happily call someone 18 the day before their birthday.
int goAgeInYears(DateTime birth, DateTime asOf) {
  var age = asOf.year - birth.year;
  final hadBirthdayThisYear = asOf.month > birth.month ||
      (asOf.month == birth.month && asOf.day >= birth.day);
  if (!hadBirthdayThisYear) age -= 1;
  return age;
}

/// `yyyy-MM-dd` — the wire format the API expects.
///
/// Deliberately not `DateFormat`: `intl`'s Arabic locale renders Arabic-Indic
/// numerals, and nothing else in this product does. A payload must never
/// depend on the display locale in any case.
String goFormatDateIso(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// `dd / MM / yyyy` — what the captain reads.
///
/// Western digits in both languages, matching every other number in the app
/// (fares, distances, plate numbers).
String goFormatDateDisplay(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')} / '
    '${date.month.toString().padLeft(2, '0')} / '
    '${date.year}';

/// Bounds for a given [purpose], resolved against [now].
///
/// Returned as a record so the call site cannot mix up the order of three
/// interchangeable `DateTime`s.
({DateTime first, DateTime last, DateTime initial}) goDateBounds(
  GoDatePurpose purpose, {
  DateTime? now,
  DateTime? current,
}) {
  final today = now ?? DateTime.now();
  // Normalise to midnight: a `firstDate` carrying a wall-clock time makes the
  // calendar disable today's cell for part of the day.
  final midnight = DateTime(today.year, today.month, today.day);

  switch (purpose) {
    case GoDatePurpose.birthDate:
      final last = DateTime(
        midnight.year - kMinCaptainAge,
        midnight.month,
        midnight.day,
      );
      final first = DateTime(
        midnight.year - kMaxCaptainAge,
        midnight.month,
        midnight.day,
      );
      // Open around the median working-captain age rather than at the boundary
      // — the year grid then opens mid-list, scrollable in both directions.
      final fallback = DateTime(midnight.year - 32, 1, 1);
      return (
        first: first,
        last: last,
        initial: _clamp(current ?? fallback, first, last),
      );

    case GoDatePurpose.documentExpiry:
      final last = DateTime(midnight.year + 15, midnight.month, midnight.day);
      return (
        first: midnight,
        last: last,
        initial: _clamp(
          current ?? midnight.add(const Duration(days: 365)),
          midnight,
          last,
        ),
      );

    case GoDatePurpose.nearFuture:
      final last = midnight.add(const Duration(days: 30));
      return (
        first: midnight,
        last: last,
        initial: _clamp(current ?? midnight, midnight, last),
      );
  }
}

DateTime _clamp(DateTime value, DateTime first, DateTime last) {
  if (value.isBefore(first)) return first;
  if (value.isAfter(last)) return last;
  return value;
}

/// Opens the Tempo calendar.
///
/// Wraps [showDatePicker] with three things the bare call was missing:
///
///  1. **Bounds and an opening grid that match the purpose** — see
///     [GoDatePurpose]. This is what makes birth-date entry usable.
///  2. **An explicit [Directionality]**, so the calendar cannot fall out of
///     RTL if it is ever pushed from a context above the app's directionality
///     wrapper.
///  3. **A text-scale ceiling.** `main.dart` honours the system text scale up
///     to 1.3×, which is right for the map chrome but overflows the calendar's
///     fixed-height day grid. The dialog is capped at 1.15× so a captain with
///     large system type still gets a usable picker instead of a clipped one.
///
/// Returns `null` if the captain dismissed the dialog.
Future<DateTime?> pickGoDate(
  BuildContext context, {
  required GoDatePurpose purpose,
  DateTime? current,
  String? helpText,
}) async {
  final bounds = goDateBounds(purpose, current: current);
  final isRtl = Directionality.of(context) == TextDirection.rtl;

  return showDatePicker(
    context: context,
    initialDate: bounds.initial,
    firstDate: bounds.first,
    lastDate: bounds.last,
    helpText: helpText,
    // Birth dates start on the year grid; forward-looking dates are close
    // enough to today that the day grid is already the fastest route.
    initialDatePickerMode: purpose == GoDatePurpose.birthDate
        ? DatePickerMode.year
        : DatePickerMode.day,
    // `calendar` (not `calendarOnly`) keeps the keyboard toggle available —
    // typing 15/03/1988 beats any amount of tapping for someone who knows the
    // date, and it is the accessible path.
    initialEntryMode: DatePickerEntryMode.calendar,
    builder: (dialogContext, child) {
      final media = MediaQuery.of(dialogContext);
      return Directionality(
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 1.0,
              maxScaleFactor: 1.15,
            ),
          ),
          child: child!,
        ),
      );
    },
  );
}

/// A tappable, theme-aware date field.
///
/// Replaces the hand-rolled `InkWell` + `InputDecorator` + `showDatePicker`
/// trio that was duplicated per screen — each copy drifting slightly in
/// padding, hint colour, and whether it showed an icon at all.
class GoDateField extends StatelessWidget {
  const GoDateField({
    super.key,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    required this.purpose,
    this.icon,
    this.helperText,
    this.errorText,
    this.helpText,
    this.enabled = true,
  });

  final String label;

  /// Shown in place of a value, and as the picker's fallback title.
  final String hint;

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final GoDatePurpose purpose;

  /// Leading glyph. Defaults to a calendar for expiry, a cake for birth dates.
  final IconData? icon;

  /// Supporting line under the field — the computed age, for instance.
  final String? helperText;

  /// Validation message. Rendered by [InputDecorator], so it also recolours
  /// the border.
  final String? errorText;

  /// Title inside the calendar dialog.
  final String? helpText;

  final bool enabled;

  IconData get _resolvedIcon {
    if (icon != null) return icon!;
    return purpose == GoDatePurpose.birthDate
        ? Icons.cake_outlined
        : Icons.event_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final hasValue = value != null;

    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      onTap: enabled
          ? () async {
              final picked = await pickGoDate(
                context,
                purpose: purpose,
                current: value,
                helpText: helpText ?? label,
              );
              if (picked != null) onChanged(picked);
            }
          : null,
      child: InputDecorator(
        isEmpty: false,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          helperStyle: AppTokens.font(fontSize: 12, color: go.muted),
          errorText: errorText,
          errorStyle: AppTokens.font(fontSize: 12, color: AppTokens.danger),
          prefixIcon: Icon(
            _resolvedIcon,
            // Muted until the field is filled: the icon should not read as
            // more important than the value it labels.
            color: hasValue ? go.action : go.muted,
            size: 20,
          ),
          // A chevron signals "this opens something", which a bare text field
          // does not. Without it captains tapped the label and gave up.
          suffixIcon: enabled
              ? Icon(Icons.expand_more_rounded, color: go.muted, size: 22)
              : null,
          filled: true,
          fillColor: enabled ? go.surface : go.surface.withOpacity(0.5),
          labelStyle: AppTokens.font(fontSize: 14, color: go.muted),
          floatingLabelStyle: AppTokens.font(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: go.action,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceMd,
            vertical: AppTokens.spaceSm,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            borderSide: BorderSide(color: go.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            borderSide: BorderSide(color: go.border),
          ),
        ),
        child: Text(
          hasValue ? goFormatDateDisplay(value!) : hint,
          style: AppTokens.font(
            fontSize: 15,
            // Weight, not just colour, separates a real value from a
            // placeholder — colour alone fails for colour-blind captains.
            fontWeight: hasValue ? FontWeight.w700 : FontWeight.w400,
            color: hasValue ? go.text : go.muted,
          ),
        ),
      ),
    );
  }

  /// Convenience factory for the birth-date case, which carries extra rules:
  /// it shows the captain's computed age and refuses under-[kMinCaptainAge]s.
  static Widget birthDate({
    Key? key,
    required BuildContext context,
    required DateTime? value,
    required ValueChanged<DateTime> onChanged,
    bool enabled = true,
  }) {
    final strings = AppStrings.of(context);
    final age = value == null ? null : goAgeInYears(value, DateTime.now());
    final tooYoung = age != null && age < kMinCaptainAge;

    return GoDateField(
      key: key,
      label: strings.docBirthDateLabel,
      hint: strings.docBirthDateHint,
      helpText: strings.docBirthDateLabel,
      value: value,
      onChanged: onChanged,
      purpose: GoDatePurpose.birthDate,
      enabled: enabled,
      icon: Icons.cake_outlined,
      // Echoing the age back is the cheapest possible guard against a
      // mis-tapped year — 1998 vs 1988 is invisible in a date, obvious in an
      // age.
      helperText: age == null ? null : strings.docBirthDateAge(age),
      errorText: tooYoung ? strings.docBirthDateTooYoung : null,
    );
  }
}
