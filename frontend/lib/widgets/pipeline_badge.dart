import 'package:flutter/cupertino.dart';

const _stages = [
  'nueva', 'asignada', 'en_proceso',
  'cotizaciones_enviadas', 'presentada',
  'ganada', 'perdida', 'rechazada', 'desierta',
];

(Color, Color, String) _stageStyle(String stage) {
  switch (stage) {
    case 'nueva':                  return (const Color(0xFFF1F4F9), const Color(0xFF6B7280), 'Nueva');
    case 'asignada':               return (const Color(0xFFEFF6FF), const Color(0xFF2563EB), 'Asignada');
    case 'en_proceso':             return (const Color(0xFFFFFBEB), const Color(0xFFD97706), 'En proceso');
    case 'cotizaciones_enviadas':  return (const Color(0xFFF5F3FF), const Color(0xFF7C3AED), 'Cotizaciones');
    case 'presentada':             return (const Color(0xFFECFEFF), const Color(0xFF0891B2), 'Presentada');
    case 'ganada':                 return (const Color(0xFFECFDF5), const Color(0xFF059669), 'Ganada');
    case 'perdida':                return (const Color(0xFFFEF2F2), const Color(0xFFDC2626), 'Perdida');
    case 'rechazada':              return (const Color(0xFFFFF7ED), const Color(0xFFEA580C), 'Rechazada');
    case 'desierta':               return (const Color(0xFFF9FAFB), const Color(0xFF9CA3AF), 'Desierta');
    default:                       return (const Color(0xFFF1F4F9), const Color(0xFF6B7280), stage);
  }
}

/// Compact colored pill for a pipeline stage.
class PipelineBadge extends StatelessWidget {
  final String stage;
  final bool small;

  const PipelineBadge({super.key, required this.stage, this.small = false});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = _stageStyle(stage);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 7 : 9,
        vertical:   small ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize:   small ? 11 : 12,
          fontWeight: FontWeight.w600,
          color:      fg,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

/// Horizontal scrollable stage stepper for the detail screen.
class PipelineStepper extends StatelessWidget {
  final String currentStage;
  final bool canEdit;
  final ValueChanged<String>? onStageSelected;

  const PipelineStepper({
    super.key,
    required this.currentStage,
    this.canEdit = false,
    this.onStageSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _stages.length,
        separatorBuilder: (context, i) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final s = _stages[i];
          final (bg, fg, label) = _stageStyle(s);
          final isCurrent = s == currentStage;

          return GestureDetector(
            onTap: canEdit && !isCurrent ? () => onStageSelected?.call(s) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isCurrent ? fg : bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: fg.withValues(alpha: isCurrent ? 1.0 : 0.25),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize:   12,
                  fontWeight: FontWeight.w600,
                  color:      isCurrent ? const Color(0xFFFFFFFF) : fg,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
