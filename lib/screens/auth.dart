import 'dart:io';
import 'package:flutter/material.dart';
import 'package:s_chat/widgets/user/user_image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _supabase = Supabase.instance.client;

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  bool _isLogin = true, _isAuthing = false;
  String _enteredEmail = '', _enteredPass = '', _enteredName = '';
  File? _selectedImage;

  void _saveForm() {
    if (!_form.currentState!.validate()) {
      return;
    }
    _form.currentState!.save();
    if (!_isLogin && _selectedImage == null) {
      _messageBar('Please, take or select an image...');
      return;
    }
    setState(() {
      _isAuthing = true;
    });
  }

  void _login() async {
    _saveForm();
    if (!_isAuthing) {
      return;
    }
    try {
      await _supabase.auth.signInWithPassword(
        email: _enteredEmail,
        password: _enteredPass,
      );
    } on AuthException catch (error) {
      _messageBar(error.message);
      setState(() {
        _isAuthing = false;
      });
    }
  }

  void _signup() async {
    _saveForm();
    if (!_isAuthing) return;

    // ⚠️ Capture messenger BEFORE any await — the widget may be disposed after
    // signUp() triggers onAuthStateChange and navigates to ChatScreen.
    final messenger = ScaffoldMessenger.of(context);

    void showError(String msg) {
      debugPrint('[Signup Error] $msg');
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(content: Text(msg)));
      if (mounted) setState(() => _isAuthing = false);
    }

    try {
      debugPrint('[Signup] 1/4 Creating auth user...');
      final AuthResponse userCredentials = await _supabase.auth.signUp(
        email: _enteredEmail,
        password: _enteredPass,
        data: {'username': _enteredName},
      );

      final user = userCredentials.user;
      if (user == null) throw const AuthException('User registration failed.');
      debugPrint('[Signup] ✅ User created: ${user.id}');

      String imageUrl = '';
      if (_selectedImage != null) {
        final imagePath = '${user.id}.jpg';
        debugPrint('[Signup] 2/4 Uploading → user_images/$imagePath');
        await _supabase.storage.from('user_images').upload(
          imagePath,
          _selectedImage!,
          fileOptions: const FileOptions(upsert: true),
        );
        final rawUrl =
            _supabase.storage.from('user_images').getPublicUrl(imagePath);
        imageUrl = '$rawUrl?t=${DateTime.now().millisecondsSinceEpoch}';
        debugPrint('[Signup] ✅ Image uploaded: $imageUrl');

        debugPrint('[Signup] 3/4 Updating user metadata...');
        await _supabase.auth.updateUser(
          UserAttributes(
            data: {'username': _enteredName, 'image_url': imageUrl},
          ),
        );
        debugPrint('[Signup] ✅ Metadata updated');
      }

      debugPrint('[Signup] 4/4 Upserting to users table...');
      await _supabase.from('users').upsert({
        'id': user.id,
        'username': _enteredName,
        'email': _enteredEmail,
        'image_url': imageUrl,
      });
      debugPrint('[Signup] ✅ Signup fully complete');
    } on AuthException catch (error) {
      showError(error.message);
    } catch (error) {
      showError('Error: $error');
    }
  }

  void _messageBar(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Center(child: Image.asset('assets/img/s_chat.png', width: 200)),
              const SizedBox(height: 20),
              Card(
                margin: const EdgeInsets.all(20),
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: _isAuthing
                      ? CircularProgressIndicator()
                      : Form(
                          key: _form,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!_isLogin)
                                UserImagePicker(
                                  onSelectImage: (image) {
                                    _selectedImage = image;
                                  },
                                ),
                              if (!_isLogin)
                                TextFormField(
                                  decoration: const InputDecoration(
                                    label: Text('User Name'),
                                  ),
                                  keyboardType: TextInputType.name,
                                  validator: (name) {
                                    if (name == null ||
                                        name.trim().isEmpty ||
                                        name.trim().length < 2) {
                                      return 'User name should be more then 2 characters.';
                                    }
                                    return null;
                                  },
                                  onSaved: (name) {
                                    _enteredName = name!;
                                  },
                                ),
                              TextFormField(
                                decoration: const InputDecoration(
                                  label: Text('Email'),
                                ),
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                textCapitalization: TextCapitalization.none,
                                validator: (email) {
                                  if (email == null ||
                                      email.trim().isEmpty ||
                                      email.length < 7 ||
                                      !email.contains('@')) {
                                    return 'Please enter a valid email address.';
                                  }
                                  return null;
                                },
                                onSaved: (email) {
                                  _enteredEmail = email!.trim();
                                },
                              ),
                              TextFormField(
                                decoration: const InputDecoration(
                                  label: Text('Password'),
                                ),
                                keyboardType: TextInputType.visiblePassword,
                                obscureText: true,
                                validator: (pass) {
                                  if (pass == null || pass.trim().isEmpty) {
                                    if (pass!.trim().length < 8) {
                                      return 'Password should be 8 characters long at least.';
                                    }
                                    return 'Please enter password!';
                                  }
                                  return null;
                                },
                                onSaved: (pass) {
                                  _enteredPass = pass!.trim();
                                },
                              ),
                              const SizedBox(height: 18),
                              ElevatedButton(
                                onPressed: _isLogin ? _login : _signup,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                ),
                                child: Text(_isLogin ? 'Login' : 'Signup'),
                              ),
                              TextButton(
                                onPressed: () => setState(() {
                                  _isLogin = !_isLogin;
                                }),
                                child: Text(
                                  _isLogin
                                      ? "Create an account"
                                      : "I already have an account. login",
                                  style: Theme.of(context).textTheme.bodyMedium!
                                      .copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.secondary.withAlpha(200),
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
