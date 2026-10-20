import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks for a number. Returns null when cancelled or invalid.
Future<double?> showNumberDialog(
  BuildContext context, {
  required String title,
  required double initial,
  String? suffix,
  int decimals = 0,
  double min = 0,
  double max = 100000,
}) =>
    showDialog<double>(
      context: context,
      builder: (_) => _NumberDialog(
        title: title,
        initial: initial,
        suffix: suffix,
        decimals: decimals,
        min: min,
        max: max,
      ),
    );

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({
    required this.title,
    required this.initial,
    required this.suffix,
    required this.decimals,
    required this.min,
    required this.max,
  });

  final String title;
  final double initial;
  final String? suffix;
  final int decimals;
  final double min;
  final double max;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final _ctrl = TextEditingController(
    text: widget.initial.toStringAsFixed(widget.decimals),
  )..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.toStringAsFixed(widget.decimals).length,
    );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double? _parse() {
    final v = double.tryParse(_ctrl.text.replaceAll(',', '.').trim());
    if (v == null || v < widget.min || v > widget.max) return null;
    return v;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          style: const TextStyle(fontSize: 28),
          decoration: InputDecoration(suffixText: widget.suffix),
          onSubmitted: (_) => Navigator.pop(context, _parse()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, _parse()),
            child: const Text('OK'),
          ),
        ],
      );
}

/// A value with big − / + buttons; tapping the value lets the user type it.
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.suffix,
    this.step = 1,
    this.min = 0,
    this.max = 1000,
    this.decimals = 0,
  });

  final String label;

  /// Value in display units.
  final double value;
  final ValueChanged<double> onChanged;
  final String suffix;
  final double step;
  final double min;
  final double max;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    double clamp(double v) => v.clamp(min, max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'Less $label',
              iconSize: 28,
              onPressed: value <= min ? null : () => onChanged(clamp(value - step)),
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final v = await showNumberDialog(
                    context,
                    title: label,
                    initial: value,
                    suffix: suffix,
                    decimals: decimals,
                    min: min,
                    max: max,
                  );
                  if (v != null) onChanged(v);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${value.toStringAsFixed(decimals)} $suffix',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'More $label',
              iconSize: 28,
              onPressed: value >= max ? null : () => onChanged(clamp(value + step)),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}
