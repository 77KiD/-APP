import 'package:flutter/material.dart';
import 'package:group_trip/core/theme/app_colors.dart';

class LabeledField extends StatelessWidget {
  const LabeledField({
    required this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.autofillHints,
    this.onSubmitted,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? helper;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      autocorrect: !obscure,
      enableSuggestions: !obscure,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
      ),
    );
  }
}

class FormErrorText extends StatelessWidget {
  const FormErrorText(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null || message!.isEmpty) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          message!,
          key: const Key('form-error'),
          style: const TextStyle(color: AppColors.error, fontSize: 16),
        ),
      ),
    );
  }
}

class FormColumn extends StatelessWidget {
  const FormColumn({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            children[i],
          ],
        ],
      ),
    );
  }
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.headlineSmall),
    );
  }
}
