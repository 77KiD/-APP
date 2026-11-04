import 'package:flutter/material.dart';
import 'package:group_trip/app/app_scope.dart';
import 'package:group_trip/core/widgets/datetime_input.dart';
import 'package:group_trip/core/widgets/form_widgets.dart';
import 'package:group_trip/l10n/app_strings.dart';

enum _AuthMode { guest, signIn, signUp }

class UnauthenticatedPage extends StatefulWidget {
  const UnauthenticatedPage({this.preferGuest = false, super.key});

  /// 網頁版先顯示訪客加入（ADR 0012 第 4 點），仍可改用 email 登入。
  final bool preferGuest;

  @override
  State<UnauthenticatedPage> createState() => _UnauthenticatedPageState();
}

class _UnauthenticatedPageState extends State<UnauthenticatedPage> {
  late _AuthMode _mode = widget.preferGuest
      ? _AuthMode.guest
      : _AuthMode.signIn;

  @override
  Widget build(BuildContext context) {
    return switch (_mode) {
      _AuthMode.guest => GuestSignUpPage(
        onSignIn: () => setState(() => _mode = _AuthMode.signIn),
      ),
      _AuthMode.signUp => SignUpPage(
        onSignIn: () => setState(() => _mode = _AuthMode.signIn),
      ),
      _AuthMode.signIn => SignInPage(
        onSignUp: () => setState(() => _mode = _AuthMode.signUp),
      ),
    };
  }
}

/// 網頁訪客：不用 email 與密碼，填顯示名稱與生日就能加入旅程。
/// 帳號只存在這個瀏覽器，清掉瀏覽器資料就找不回來。
class GuestSignUpPage extends StatefulWidget {
  const GuestSignUpPage({required this.onSignIn, super.key});

  final VoidCallback onSignIn;

  @override
  State<GuestSignUpPage> createState() => _GuestSignUpPageState();
}

class _GuestSignUpPageState extends State<GuestSignUpPage> {
  final _name = TextEditingController();
  final _birthday = TextEditingController();
  bool _consent = false;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _birthday.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final deps = AppScope.of(context);
    final today = await deps.clock.now();
    final outcome = await deps.auth.signUpGuest(
      displayName: _name.text,
      birthday: _birthday.text,
      birthdayConsent: _consent,
      today: today,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = outcome.failure?.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FormColumn(
        children: [
          const PageHeading(AppStrings.guestTitle),
          Text(
            AppStrings.guestIntro,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          Text(
            AppStrings.birthdayPurpose,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          LabeledField(
            label: AppStrings.displayName,
            controller: _name,
            autofillHints: const [AutofillHints.name],
          ),
          DateTimeInputField(
            label: AppStrings.birthday,
            controller: _birthday,
            hint: AppStrings.dateHint,
            helper: AppStrings.dateHelper,
            isDate: true,
            validator: const DateValidator(
              required: true,
              notInFuture: true,
            ).call,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _consent,
            onChanged: (value) => setState(() => _consent = value ?? false),
            title: const Text(AppStrings.birthdayConsent),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          FormErrorText(_error),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: const Text(AppStrings.submitGuest),
          ),
          TextButton(
            onPressed: widget.onSignIn,
            child: const Text(AppStrings.guestHasAccount),
          ),
        ],
      ),
    );
  }
}

class SignInPage extends StatefulWidget {
  const SignInPage({required this.onSignUp, super.key});

  final VoidCallback onSignUp;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final deps = AppScope.of(context);
    final outcome = await deps.auth.signIn(
      email: _email.text,
      password: _password.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = outcome.failure?.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FormColumn(
        children: [
          const PageHeading(AppStrings.signInTitle),
          LabeledField(
            label: AppStrings.email,
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
          ),
          LabeledField(
            label: AppStrings.password,
            controller: _password,
            obscure: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
          ),
          FormErrorText(_error),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: const Text(AppStrings.submitSignIn),
          ),
          TextButton(
            onPressed: widget.onSignUp,
            child: const Text(AppStrings.goToSignUp),
          ),
        ],
      ),
    );
  }
}

class SignUpPage extends StatefulWidget {
  const SignUpPage({required this.onSignIn, super.key});

  final VoidCallback onSignIn;

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _birthday = TextEditingController();
  bool _consent = false;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _birthday.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final deps = AppScope.of(context);
    final today = await deps.clock.now();
    final outcome = await deps.auth.signUp(
      email: _email.text,
      password: _password.text,
      displayName: _name.text,
      birthday: _birthday.text,
      birthdayConsent: _consent,
      today: today,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = outcome.failure?.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FormColumn(
        children: [
          const PageHeading(AppStrings.signUpTitle),
          Text(
            AppStrings.birthdayPurpose,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          LabeledField(
            label: AppStrings.email,
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
          ),
          LabeledField(
            label: AppStrings.password,
            controller: _password,
            obscure: true,
            helper: AppStrings.weakPassword,
            autofillHints: const [AutofillHints.newPassword],
          ),
          LabeledField(
            label: AppStrings.displayName,
            controller: _name,
            autofillHints: const [AutofillHints.name],
          ),
          DateTimeInputField(
            label: AppStrings.birthday,
            controller: _birthday,
            hint: AppStrings.dateHint,
            helper: AppStrings.dateHelper,
            isDate: true,
            validator: const DateValidator(
              required: true,
              notInFuture: true,
            ).call,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _consent,
            onChanged: (value) => setState(() => _consent = value ?? false),
            title: const Text(AppStrings.birthdayConsent),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          FormErrorText(_error),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: const Text(AppStrings.submitSignUp),
          ),
          TextButton(
            onPressed: widget.onSignIn,
            child: const Text(AppStrings.goToSignIn),
          ),
        ],
      ),
    );
  }
}
