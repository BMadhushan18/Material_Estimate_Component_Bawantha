import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth_service.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final res = await AuthService.signup(
        _firstNameCtrl.text.trim(),
        _lastNameCtrl.text.trim(),
        _emailCtrl.text.trim(),
        _phoneCtrl.text.trim(),
        _passCtrl.text,
      );
      if (res['statusCode'] == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signup successful. Please login.')),
        );
        Navigator.of(context).pop();
      } else {
        final body = res['body'];
        final msg = (body is Map && body['error'] != null)
            ? body['error']
            : (body['message'] ?? 'Signup failed');
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg.toString())));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Signup error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const SizedBox.shrink(),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset('images/signup.jpg', fit: BoxFit.cover),
          ),
          // Dark overlay for readability
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.4)),
          ),
          // Form content
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).scaffoldBackgroundColor.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Sign up',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _firstNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'First name',
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Enter first name'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _lastNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Last name',
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Enter last name' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Enter email' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Phone number',
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Enter phone number'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                        obscureText: true,
                        validator: (v) => (v == null || v.length < 6)
                            ? 'Enter at least 6 chars'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirmPassCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                        ),
                        obscureText: true,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Confirm password';
                          if (v != _passCtrl.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      _loading
                          ? const CircularProgressIndicator()
                          : ElevatedButton(
                              onPressed: _submit,
                              child: const Text('Create account'),
                            ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
