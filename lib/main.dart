import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'screens/home/home_dashboard.dart';
import 'widgets/glass_container.dart';
import 'screens/admin/admin_dashboard.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/env.dart';
import 'core/debug_logger.dart';
import 'core/error_handler.dart';
import 'screens/debug/debug_screen.dart';
import 'repositories/auth_repository.dart';
import 'repositories/profiles_repository.dart';
import 'services/room_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize debugging first
  await logger.logAppStart();
  ErrorHandler().initialize();
  
  try {
    await dotenv.load(fileName: '.env');
    logger.info('Environment variables loaded', tag: 'Main');
    
    if (Env.isConfigured) {
      logger.info('Supabase configuration found, initializing...', tag: 'Main');
      await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);
      logger.info('Supabase initialized successfully', tag: 'Main');
      
      // Initialize RoomService to load rooms from Supabase
      logger.info('Initializing RoomService...', tag: 'Main');
      await RoomService.instance.initialize();
      logger.info('RoomService initialized successfully', tag: 'Main');
    } else {
      logger.warning('Supabase not configured - running in offline mode', tag: 'Main');
    }
    
    logger.info('App initialization complete', tag: 'Main');
    runApp(const MyApp());
  } catch (e, stackTrace) {
    logger.fatal('Failed to initialize app', 
      tag: 'Main',
      error: e,
      stackTrace: stackTrace
    );
    
    // Still run the app even if initialization fails
    runApp(const MyApp());
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  Future<void> _showTopSuccessBanner(String message) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: const Color(0xFF16A34A), // green
        elevation: 2,
        leading: const Icon(Icons.check_circle, color: Colors.white),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
            },
          ),
        ],
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
    await Future.delayed(const Duration(seconds: 5));
    messenger.hideCurrentMaterialBanner();
  }

  final _nameController = TextEditingController();
  final _courseController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _courseController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canRegister {
    final name = _nameController.text.trim();
    final course = _courseController.text.trim();
    final email = _emailController.text.trim();
    final pass = _passwordController.text;
    return name.isNotEmpty && course.isNotEmpty && email.isNotEmpty && pass.isNotEmpty;
  }

  InputDecoration _roundedInputDecoration({required String hint, required Widget icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
      prefixIcon: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: icon),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      filled: true,
      fillColor: Colors.white.withOpacity(0.18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.20), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.35), width: 1.2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF63C1E3), Color(0xFF1E2931)],
              ),
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
            child: Container(color: Colors.white.withOpacity(0)),
          ),
          SafeArea(
            top: true,
            bottom: false,
            child: Column(
              children: [
                const SizedBox(height: 70),
                Image.asset('assets/image/LogoWhite.png', width: 64, height: 64, semanticLabel: 'GABAY Logo'),
                const SizedBox(height: 20),
                const Text('GABAY: Smart Campus Navigation System', style: TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(height: 50),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: GlassContainer(
                      radius: 28,
                      padding: EdgeInsets.zero,
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          28,
                          20,
                          (MediaQuery.of(context).viewInsets.bottom > 0)
                              ? MediaQuery.of(context).viewInsets.bottom
                              : 0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Align(
                              alignment: Alignment.center,
                              child: Text(
                                'Register',
                                style: TextStyle(color: Colors.white, fontSize: 24, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(height: 60),
                            TextField(
                              style: const TextStyle(color: Colors.white),
                              cursorColor: Colors.white,
                              controller: _nameController,
                              onChanged: (_) => setState(() {}),
                              decoration: _roundedInputDecoration(
                                hint: 'Full name',
                                icon: SvgPicture.asset('assets/icon/account.svg', width: 22, height: 22, color: Colors.white),
                              ),
                            ),
                            const SizedBox(height: 30),
                            TextField(
                              style: const TextStyle(color: Colors.white),
                              cursorColor: Colors.white,
                              controller: _courseController,
                              onChanged: (_) => setState(() {}),
                              decoration: _roundedInputDecoration(
                                hint: 'Course',
                                icon: const Icon(Icons.school_outlined, color: Colors.white, size: 22),
                              ),
                            ),
                            const SizedBox(height: 30),
                            TextField(
                              style: const TextStyle(color: Colors.white),
                              cursorColor: Colors.white,
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              onChanged: (_) => setState(() {}),
                              decoration: _roundedInputDecoration(
                                hint: 'Email',
                                icon: SvgPicture.asset('assets/icon/email.svg', width: 16, height: 16, color: Colors.white),
                              ),
                            ),
                            const SizedBox(height: 30),
                            TextField(
                              style: const TextStyle(color: Colors.white),
                              cursorColor: Colors.white,
                              controller: _passwordController,
                              obscureText: true,
                              onChanged: (_) => setState(() {}),
                              decoration: _roundedInputDecoration(
                                hint: 'Password',
                                icon: SvgPicture.asset('assets/icon/password.svg', width: 22, height: 22, color: Colors.white),
                              ),
                            ),
                            const SizedBox(height: 40),
                            SizedBox(
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _canRegister
                                    ? () async {
                                        final name = _nameController.text.trim();
                                        final course = _courseController.text.trim();
                                        final email = _emailController.text.trim();
                                        final pass = _passwordController.text;
                                        try {
                                          // Prevent registering the fixed admin account from the app
                                          if (email.toLowerCase() == 'admin@seait.edu') {
                                            final messenger = ScaffoldMessenger.of(context);
                                            messenger.clearMaterialBanners();
                                            messenger.showMaterialBanner(
                                              const MaterialBanner(
                                                backgroundColor: Color(0xFFB91C1C), // red
                                                elevation: 2,
                                                leading: Icon(Icons.error_outline, color: Colors.white),
                                                content: Text(
                                                  'This admin account is managed by the school. Please use Login.',
                                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                                ),
                                                actions: [SizedBox.shrink()],
                                                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              ),
                                            );
                                            await Future.delayed(const Duration(seconds: 5));
                                            messenger.hideCurrentMaterialBanner();
                                            return;
                                          }
                                          final res = await AuthRepository.instance.signUp(email: email, password: pass);
                                          // If immediately authenticated (email confirmation disabled), upsert profile.
                                          if (Supabase.instance.client.auth.currentUser != null) {
                                            await ProfilesRepository.instance.upsertMyProfile(
                                              name: name.isNotEmpty ? name : 'User',
                                              email: email,
                                              course: course.isEmpty ? null : course,
                                            );
                                          }
                                          if (!mounted) return;
                                          Navigator.of(context).pop('registered'); // Immediately back to Login; Login will show banner
                                        } catch (e) {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Sign up failed: $e')),
                                          );
                                        }
                                      }
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF63C1E3),
                                  foregroundColor: Colors.white,
                                  shape: const StadiumBorder(),
                                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                ),
                                child: const Text('Register'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Have an account?', style: TextStyle(color: Colors.white70)),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const SignUpScreen(),
                                      ),
                                    );
                                  },
                                  child: const Text('Login', style: TextStyle(color: Colors.blue)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GABAY',
      builder: (context, child) {
        // Set custom error widget for better debugging
        ErrorWidget.builder = (FlutterErrorDetails details) {
          logger.logAppError(details);
          return GabayErrorWidget(details: details);
        };
        return child!;
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlue),
      ),
      home: const MyHomePage(title: 'GABAY'),
    );
  }
}

class GabayErrorWidget extends StatelessWidget {
  final FlutterErrorDetails details;

  const GabayErrorWidget({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E2931),
      appBar: AppBar(
        title: const Text('Error Occurred'),
        backgroundColor: const Color(0xFFB91C1C),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'An error occurred while running the app:',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              details.exception.toString(),
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            if (details.context != null)
              Text(
                details.context.toString(),
                style: const TextStyle(color: Colors.white70),
              ),
            const SizedBox(height: 16),
            const Text(
              'Stack Trace:',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  details.stack?.toString() ?? 'No stack trace available',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      // Restart the app
                      runApp(const MyApp());
                    },
                    child: const Text('Restart App'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DebugScreen(),
                        ),
                      );
                    },
                    child: const Text('View Logs'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF63C1E3),
      body: SafeArea(
        child: Center(
          child: Column(
            children: <Widget>[
              const Spacer(flex: 2),
              Image.asset(
                'assets/image/LogoWhite.png',
                width: 160,
                height: 160,
                semanticLabel: 'GABAY Logo',
              ),
              const SizedBox(height: 24),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  'GABAY: Smart Campus Navigation System',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const Spacer(flex: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 32.0),
                child: GlassContainer(
                  radius: 32,
                  padding: EdgeInsets.zero,
                  child: SizedBox(
                    width: 260,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SignUpScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        elevation: 0,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Get Started'),
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

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  bool rememberMe = true;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canLogin {
    final email = _emailController.text.trim();
    final pass = _passwordController.text.trim();
    return email.isNotEmpty && pass.isNotEmpty;
  }

  InputDecoration _roundedInputDecoration({required String hint, required Widget icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
      prefixIcon: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: icon),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      filled: true,
      fillColor: Colors.white.withOpacity(0.18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.20), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.35), width: 1.2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF63C1E3), Color(0xFF1E2931)],
              ),
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
            child: Container(color: Colors.white.withOpacity(0)),
          ),
          SafeArea(
            top: true,
            bottom: false,
            child: Column(
              children: [
                const SizedBox(height: 70),
                Image.asset('assets/image/LogoWhite.png', width: 64, height: 64, semanticLabel: 'GABAY Logo'),
                const SizedBox(height: 20),
                const Text(
                  'GABAY: Smart Campus Navigation System',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                const SizedBox(height: 50),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: GlassContainer(
                      radius: 28,
                      padding: EdgeInsets.zero,
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          28,
                          20,
                          (MediaQuery.of(context).viewInsets.bottom > 0)
                              ? MediaQuery.of(context).viewInsets.bottom
                              : 0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Align(
                              alignment: Alignment.center,
                              child: Text(
                                'Login!',
                                style: TextStyle(color: Colors.white, fontSize: 24, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(height: 60),
                            TextField(
                              style: const TextStyle(color: Colors.white),
                              cursorColor: Colors.white,
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              onChanged: (_) => setState(() {}),
                              decoration: _roundedInputDecoration(
                                hint: 'Email',
                                icon: SvgPicture.asset('assets/icon/email.svg', width: 16, height: 16, color: Colors.white),
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              style: const TextStyle(color: Colors.white),
                              cursorColor: Colors.white,
                              controller: _passwordController,
                              obscureText: true,
                              onChanged: (_) => setState(() {}),
                              decoration: _roundedInputDecoration(
                                hint: 'Password',
                                icon: SvgPicture.asset('assets/icon/password.svg', width: 22, height: 22, color: Colors.white),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Checkbox(
                                  value: rememberMe,
                                  onChanged: (v) => setState(() => rememberMe = v ?? false),
                                  visualDensity: VisualDensity.compact,
                                ),
                                const Text('Remember me', style: TextStyle(color: Colors.white)),
                                const Spacer(),
                                TextButton(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Forgot password tapped')),
                                    );
                                  },
                                  style: TextButton.styleFrom(foregroundColor: Colors.blue),
                                  child: const Text('Forgot password?'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _canLogin
                                    ? () async {
                                        final email = _emailController.text.trim();
                                        final pass = _passwordController.text.trim();
                                        try {
                                          await AuthRepository.instance.signIn(email: email, password: pass);
                                          await ProfilesRepository.instance.updateLastSignInNow();
                                          final profile = await ProfilesRepository.instance.getMyProfile();
                                          final isAdmin = await ProfilesRepository.instance.isCurrentUserAdmin();
                                          if (!mounted) return;
                                          if (isAdmin) {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => const AdminDashboard(),
                                              ),
                                            );
                                          } else {
                                            final name = (profile != null && (profile['name'] as String?)?.isNotEmpty == true)
                                                ? (profile['name'] as String)
                                                : (email.contains('@') && email.split('@').first.isNotEmpty
                                                    ? email.split('@').first
                                                    : 'Guest');
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => HomeDashboard(userName: name),
                                              ),
                                            );
                                          }
                                        } catch (e) {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Login failed: $e')),
                                          );
                                        }
                                      }
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF63C1E3),
                                  foregroundColor: Colors.white,
                                  shape: const StadiumBorder(),
                                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                ),
                                child: const Text('Login'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 44,
                              child: TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const HomeDashboard(userName: 'Guest'),
                                    ),
                                  );
                                },
                                child: const Text('Continue as Guest', style: TextStyle(color: Colors.white70)),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Don\'t have an account?', style: TextStyle(color: Colors.white70)),
                                TextButton(
                                  onPressed: () async {
                                    final result = await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const RegisterScreen(),
                                      ),
                                    );
                                    if (!mounted) return;
                                    if (result == 'registered') {
                                      final messenger = ScaffoldMessenger.of(context);
                                      messenger.clearMaterialBanners();
                                      messenger.showMaterialBanner(
                                        MaterialBanner(
                                          backgroundColor: const Color(0xFF16A34A),
                                          elevation: 2,
                                          leading: const Icon(Icons.check_circle, color: Colors.white),
                                          content: const Text(
                                            'Account created successfully. Please sign in.',
                                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                          ),
                                          actions: const [SizedBox.shrink()],
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        ),
                                      );
                                      await Future.delayed(const Duration(seconds: 5));
                                      messenger.hideCurrentMaterialBanner();
                                    }
                                  },
                                  style: TextButton.styleFrom(foregroundColor: Colors.blue),
                                  child: const Text('Register'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 40),
                            const Align(
                              alignment: Alignment.center,
                              child: Text(
                                'Powered by Gabay 2025',
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ),
                          ],
                        ), // end inner Column
                      ), // end SingleChildScrollView
                    ), // end GlassContainer
                  ), // end Padding
                ), // end Expanded
              ], // end Column children
            ), // end Column
          ), // end SafeArea
        ], // end Stack children
      ), // end Stack
    ); // end Scaffold
  }
}
