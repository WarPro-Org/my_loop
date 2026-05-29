/// Local signup screen — create account without federated login.
///
/// Allows users to sign up with just a display name and proceed to
/// avatar selection. Creates a local-only account via the API.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myloop/app/theme.dart';
import 'package:myloop/shared/widgets/big_button.dart';

/// Screen for users who prefer not to use Google/Apple sign-in.
///
/// Collects a display name and navigates to the avatar picker which
/// handles registration with the backend.
class LocalSignupScreen extends StatefulWidget {
  const LocalSignupScreen({super.key});

  @override
  State<LocalSignupScreen> createState() => _LocalSignupScreenState();
}

class _LocalSignupScreenState extends State<LocalSignupScreen> {
  final _nameController = TextEditingController();
  bool _isValid = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      final name = _nameController.text.trim();
      final valid = name.length >= 2 && name.length <= 20 && RegExp(r"^[a-zA-Z0-9 \-_']+$").hasMatch(name);
      if (valid != _isValid) setState(() => _isValid = valid);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              // Back button
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () => context.pop(),
              ),
              const SizedBox(height: 24),

              // Header
              const Text('🎮', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text(
                'Create your account',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Pick a name and start conquering territory!',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.grey),
              ),
              const SizedBox(height: 32),

              // Name field
              TextField(
                controller: _nameController,
                autofocus: true,
                maxLength: 20,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Your display name',
                  prefixIcon: const Icon(Icons.person_outline),
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.snow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.greyLight),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.greyLight, width: 2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'At least 2 characters. This is shown to other players.',
                style: TextStyle(fontSize: 12, color: AppColors.grey),
              ),

              const Spacer(),

              // Continue button
              AnimatedOpacity(
                opacity: _isValid ? 1.0 : 0.5,
                duration: const Duration(milliseconds: 200),
                child: BigButton(
                  label: 'CONTINUE',
                  onPressed: _isValid ? _continue : () {},
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _continue() {
    final name = _nameController.text.trim();
    context.push('/avatar', extra: {'name': name});
  }
}
