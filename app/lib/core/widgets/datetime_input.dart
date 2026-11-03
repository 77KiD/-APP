import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:group_trip/core/theme/semantic_colors.dart';
import 'package:intl/intl.dart';

/// 日期/時間輸入欄位。點擊彈出標準 picker，也可以直接打數字自動格式化。
class DateTimeInputField extends StatefulWidget {
  const DateTimeInputField({
    required this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.isDate = true,
    this.validator,
    this.onTap,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? helper;
  final bool isDate;
  final String? Function(String?)? validator;
  final VoidCallback? onTap;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<DateTimeInputField> createState() => _DateTimeInputFieldState();
}

class _DateTimeInputFieldState extends State<DateTimeInputField> {
  final _formatter = _DateTimeFormatter();
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_validate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_validate);
    super.dispose();
  }

  void _validate() {
    if (widget.validator != null) {
      setState(() {
        _error = widget.validator!(widget.controller.text);
      });
    }
  }

  Future<void> _openPicker() async {
    widget.onTap?.call();
    
    if (widget.isDate) {
      await _openDatePicker();
    } else {
      await _openTimePicker();
    }
  }

  Future<void> _openDatePicker() async {
    final colors = context.colors;
    final initial = _parseCurrentDate() ?? DateTime.now();
    
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      locale: const Locale('zh', 'TW'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: colors.primary,
              onPrimary: colors.onAccent,
              surface: colors.surface,
              onSurface: colors.text,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      widget.controller.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  Future<void> _openTimePicker() async {
    final colors = context.colors;
    final initial = _parseCurrentTime() ?? TimeOfDay.now();
    
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: colors.primary,
              onPrimary: colors.onAccent,
              surface: colors.surface,
              onSurface: colors.text,
            ),
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              alwaysUse24HourFormat: true,
            ),
            child: child!,
          ),
        );
      },
    );
    
    if (picked != null) {
      widget.controller.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    }
  }

  DateTime? _parseCurrentDate() {
    final text = widget.controller.text.trim();
    if (text.isEmpty) return null;
    try {
      return DateFormat('yyyy-MM-dd').parseStrict(text);
    } catch (_) {
      return null;
    }
  }

  TimeOfDay? _parseCurrentTime() {
    final text = widget.controller.text.trim();
    if (text.isEmpty) return null;
    final parts = text.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: widget.helper,
        errorText: _error,
        suffixIcon: IconButton(
          icon: Icon(widget.isDate ? Icons.calendar_today : Icons.access_time),
          onPressed: _openPicker,
        ),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        _formatter.configure(isDate: widget.isDate),
      ],
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      onTap: _openPicker,
      readOnly: false,
    );
  }
}

/// 自動格式化：20260315 → 2026/03/15，或 1830 → 18:30
class _DateTimeFormatter extends TextInputFormatter {
  bool _isDate = true;

  TextInputFormatter configure({required bool isDate}) {
    _isDate = isDate;
    return this;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    
    if (text.isEmpty) return newValue;

    String formatted;
    int cursorOffset;

    if (_isDate) {
      // 日期：YYYYMMDD → YYYY-MM-DD
      if (text.length <= 4) {
        formatted = text;
        cursorOffset = text.length;
      } else if (text.length <= 6) {
        formatted = '${text.substring(0, 4)}-${text.substring(4)}';
        cursorOffset = formatted.length;
      } else {
        final digits = text.substring(0, 8);
        formatted = '${digits.substring(0, 4)}-${digits.substring(4, 6)}-${digits.substring(6)}';
        cursorOffset = formatted.length;
      }
    } else {
      // 時間：HHMM → HH:mm
      if (text.length <= 2) {
        formatted = text;
        cursorOffset = text.length;
      } else {
        final digits = text.substring(0, 4);
        formatted = '${digits.substring(0, 2)}:${digits.substring(2)}';
        cursorOffset = formatted.length;
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
  }
}

/// 日期驗證
class DateValidator {
  const DateValidator({
    this.required = false,
    this.notInFuture = false,
    this.minDate,
    this.maxDate,
    this.maxDaysAfter,
  });

  final bool required;
  final bool notInFuture;
  final String? minDate;
  final String? maxDate;
  final (String?, int)? maxDaysAfter;

  String? call(String? value) {
    final text = value?.trim() ?? '';
    
    if (text.isEmpty) {
      return required ? '請輸入日期' : null;
    }

    final parsed = _parseDate(text);
    if (parsed == null) {
      return '請用 YYYY-MM-DD 輸入日期';
    }

    if (notInFuture && parsed.isAfter(DateTime.now())) {
      return '日期不能是未來';
    }

    if (minDate != null) {
      final min = _parseDate(minDate!);
      if (min != null && parsed.isBefore(min)) {
        return '結束日期不能早於開始日期';
      }
    }

    if (maxDate != null) {
      final max = _parseDate(maxDate!);
      if (max != null && parsed.isAfter(max)) {
        return '日期超出範圍';
      }
    }

    if (maxDaysAfter != null) {
      final (refDate, maxDays) = maxDaysAfter!;
      if (refDate != null) {
        final ref = _parseDate(refDate);
        if (ref != null) {
          final diff = parsed.difference(ref).inDays;
          if (diff > maxDays) {
            return '旅程最長 $maxDays 天';
          }
        }
      }
    }

    return null;
  }

  DateTime? _parseDate(String text) {
    try {
      return DateFormat('yyyy-MM-dd').parseStrict(text);
    } catch (_) {
      return null;
    }
  }
}

/// 時間驗證
class TimeValidator {
  const TimeValidator({this.required = false});

  final bool required;

  String? call(String? value) {
    final text = value?.trim() ?? '';
    
    if (text.isEmpty) {
      return required ? '請輸入時間' : null;
    }

    final parts = text.split(':');
    if (parts.length != 2) {
      return '請用 HH:mm 輸入時間';
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    
    if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return '請用 HH:mm 輸入時間';
    }

    return null;
  }
}
