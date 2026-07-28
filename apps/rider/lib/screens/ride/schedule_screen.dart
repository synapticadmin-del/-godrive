import 'package:flutter/material.dart';
import 'package:flutter_shared/flutter_shared.dart';

/// Schedule a ride for a later time — date + time picker + summary.
class ScheduleScreen extends StatefulWidget {
  final VoidCallback onConfirm;
  const ScheduleScreen({super.key, required this.onConfirm});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  DateTime _selectedDate = DateTime.now().add(const Duration(hours: 2));
  TimeOfDay _selectedTime = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 2)));

  Future<void> _pickDate() async {
    final strings = AppStrings.of(context);
    final now = DateTime.now();
    final max = now.add(const Duration(days: 30));
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: now,
      lastDate: max,
      helpText: strings.schedulePickDateHelp,
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final strings = AppStrings.of(context);
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      helpText: strings.schedulePickTimeHelp,
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  String get _formattedDateTime {
    final dt = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day,
        _selectedTime.hour, _selectedTime.minute);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
           '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          strings.scheduleTitle,
          style: AppTokens.font(fontWeight: FontWeight.w700),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTokens.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                border: Border.all(color: AppTokens.primary.withOpacity(0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline, color: AppTokens.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    strings.scheduleInfoNote,
                    style: AppTokens.font(fontSize: 13, color: AppTokens.primary),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            // Date picker
            Text(
              strings.scheduleDateLabel,
              style: AppTokens.font(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: go.muted,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: go.panel,
                  borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                  border: Border.all(color: go.border),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today, color: AppTokens.primary, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                      style: AppTokens.font(fontSize: 16, color: go.text),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: go.muted, size: 20),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            // Time picker
            Text(
              strings.scheduleTimeLabel,
              style: AppTokens.font(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: go.muted,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickTime,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: go.panel,
                  borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                  border: Border.all(color: go.border),
                ),
                child: Row(children: [
                  const Icon(Icons.access_time, color: AppTokens.primary, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}',
                      style: AppTokens.font(fontSize: 16, color: go.text),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: go.muted, size: 20),
                ]),
              ),
            ),
            const Spacer(),
            // Summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: go.panel,
                borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                border: Border.all(color: go.border),
              ),
              child: Row(children: [
                const Icon(Icons.schedule, color: AppTokens.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings.scheduleSummaryLine(_formattedDateTime),
                    style: AppTokens.font(fontSize: 13, color: go.text),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            // Confirm
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: widget.onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTokens.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  ),
                ),
                child: Text(
                  strings.scheduleConfirmAction,
                  style: AppTokens.font(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
