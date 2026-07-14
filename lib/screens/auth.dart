import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:s_chat/widgets/user_image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _firebase = FirebaseAuth.instance;
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
      await _firebase.signInWithEmailAndPassword(
        email: _enteredEmail,
        password: _enteredPass,
      );
    } on FirebaseAuthException catch (error) {
      _messageBar(error.message ?? 'Authentication Failed.');
      setState(() {
        _isAuthing = false;
      });
    }
  }

  void _signup() async {
    _saveForm();
    if (!_isAuthing) {
      return;
    }
    try {
      final userCredentials = await _firebase.createUserWithEmailAndPassword(
        email: _enteredEmail,
        password: _enteredPass,
      );
      final imagePath = '${userCredentials.user!.uid}.jpg';
      await _supabase.storage
          .from('user_images')
          .upload(
            imagePath,
            _selectedImage!,
            fileOptions: const FileOptions(upsert: true),
          );
      final String imageUrl = _supabase.storage
          .from('user_images')
          .getPublicUrl(imagePath);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredentials.user!.uid)
          .set({
            'username': _enteredName,
            'email': _enteredEmail,
            'image_url': imageUrl,
          });
    } on FirebaseAuthException catch (error) {
      // if(error.code == 'email-already-in-use')...
      _messageBar(error.message ?? 'Authentication Failed.');
      setState(() {
        _isAuthing = false;
      });
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
