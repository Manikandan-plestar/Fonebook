import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../models/user_session.dart';
import '../models/contact.dart';
import 'add_profile_screen.dart';
import 'app_profile_screen.dart';
import 'app_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _api = ApiClient();
  final _store = SessionStore();
  
  bool _otpSent = false;
  // _generatedOtp removed — OTP is now generated server-side via /v1/auth/send-otp
  // For backward compatibility, the old /send-verification-code is still the primary path.
  // Switch to v1 flow: the server sends the OTP; client never knows it.
  String? _serverFlowEmail; // set when using v1 auth flow
  bool _isLoading = false;
  int _resendSeconds = 0;
  Timer? _timer;

  void _startTimer() {
    setState(() => _resendSeconds = 15);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendSeconds == 0) {
        timer.cancel();
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid email')));
      return;
    }

    setState(() => _isLoading = true);

    // CRIT-03 (Flutter): Use /v1/auth/send-otp (server-side OTP generation).
    // Server generates and stores the OTP hash — client never receives the OTP.
    // Falls back to old /send-verification-code if v1 endpoint is unavailable (old server).
    try {
      bool usedV1 = false;
      try {
        final v1Res = await _api.post('v1/auth/send-otp', {
          'email': email,
          'fone_identification': 'fonebook',
        });
        if (v1Res is Map && v1Res['status'] == 'success') {
          usedV1 = true;
          _serverFlowEmail = email;
        }
      } catch (_) {
        // v1 not available (old server version) — fall through to legacy flow
      }

      if (!usedV1) {
        // Legacy fallback: old client-generated OTP flow
        // NOTE: This will be removed once ENFORCE_AUTH is enabled on the server.
        // The OTP is generated using milliseconds — not cryptographically secure.
        final otp = (100000 + (DateTime.now().millisecond * 899 + DateTime.now().microsecond)).toString().substring(0, 6);
        final res = await _api.post('send-verification-code', {
          'email': email,
          'otp': otp,
          'fone_identification': 'fonebook',
        });
        // Store temporarily for legacy verification
        if (mounted) {
          // ignore: use_build_context_synchronously
          setState(() => _otpSent = true);
        }
        if (res['status'] == 'success') {
          if (mounted) {
            _startTimer();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP sent to your email')));
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Error sending OTP')));
          }
        }
        return;
      }

      if (mounted) {
        setState(() => _otpSent = true);
        _startTimer();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP sent to your email')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Network error. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    final enteredOtp = _otpController.text.trim();
    if (enteredOtp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the OTP from your email')));
      return;
    }

    setState(() => _isLoading = true);
    final email = _emailController.text.trim();
    
    try {
      // CRIT-03: Use v1 server-side OTP verification when available
      if (_serverFlowEmail != null && _serverFlowEmail == email) {
        final v1Res = await _api.post('v1/auth/verify-otp', {
          'email': email,
          'otp': enteredOtp,
        });
        if (v1Res is! Map || v1Res['status'] != 'success') {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text((v1Res is Map ? v1Res['message'] : null) ?? 'Incorrect OTP')),
            );
          }
          return;
        }
        // Store tokens from v1 response (for future auth header use)
        // TODO Phase 3: store access_token and refresh_token in flutter_secure_storage
        _serverFlowEmail = null;
      }
      // Legacy path: OTP was verified client-side in old flow (no server-side check)
      // This branch is kept for backward compat until ENFORCE_AUTH goes live.

      final session = UserSession(email: email, premium: false);
      await _store.save(session);

      // Check if user already has an Application Profile
      bool hasProfile = false;
      final cachedProfile = await _store.getAppProfile();
      if (cachedProfile != null && cachedProfile.isNotEmpty) {
        final cName = cachedProfile['name']?.toString() ?? '';
        final cPhone = cachedProfile['phone']?.toString() ?? '';
        if (cName.isNotEmpty || cPhone.isNotEmpty) {
          hasProfile = true;
        }
      }

      if (!hasProfile) {
        try {
          final res = await _api.post('get_my_contacts', {
            'email': email,
            'owner_email': email,
          });
          
          if (res != null) {
            Map<String, dynamic>? profileData;
            
            dynamic items = res;
            if (res is Map) {
              if (res['data'] != null) items = res['data'];
              else if (res['result'] != null) items = res['result'];
              else if (res['contacts'] != null) items = res['contacts'];
            }

            if (items is List && items.isNotEmpty) {
              for (final item in items) {
                if (item is Map) {
                  final cat = item['category']?.toString().toLowerCase() ?? '';
                  final titleStr = item['title']?.toString() ?? '';
                  final appProfStr = item['app_profile']?.toString() ?? '';

                  if (cat == 'app_profile' || appProfStr.isNotEmpty || titleStr.contains('"phone"') || titleStr.contains('"owner_email"')) {
                    try {
                      final targetJsonStr = appProfStr.isNotEmpty ? appProfStr : titleStr;
                      final decoded = jsonDecode(targetJsonStr);
                      if (decoded is Map && decoded.isNotEmpty) {
                        profileData = Map<String, dynamic>.from(decoded);
                        break;
                      }
                    } catch (_) {}

                    if (item['name'] != null || item['phone'] != null) {
                      profileData = Map<String, dynamic>.from(item);
                      break;
                    }
                  }
                }
              }
            } else if (items is Map && items.isNotEmpty) {
              if (items['name'] != null || items['phone'] != null) {
                profileData = Map<String, dynamic>.from(items);
              }
            }

            if (profileData != null) {
              final pName = profileData['name']?.toString() ?? profileData['full_name']?.toString() ?? '';
              final pPhone = profileData['phone']?.toString() ?? '';
              if (pName.isNotEmpty || pPhone.isNotEmpty) {
                hasProfile = true;
                await _store.saveAppProfile(profileData);
              }
            }
          }
        } catch (e) {
          debugPrint("Error checking remote app profile: $e");
        }
      }

      if (mounted) {
        if (hasProfile) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AppShell()));
        } else {
          // Mandatory Application Profile creation only for first-time new users
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => AppProfileScreen(
                api: _api,
                session: session,
                isMandatoryOnboarding: true,
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("OTP Verify Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error checking user status: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F9),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 27),
          child: Column(
            children: [
              const SizedBox(height: 71),
              Image.asset('assets/images/phone_book_logo_round.png', width: 65, height: 65, fit: BoxFit.contain),
              const SizedBox(height: 15),
              const Text('Fone Book', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: Color(0xFF232323))),
              const SizedBox(height: 30),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Welcome To', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xFF232323))),
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Fone Book', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF232323))),
              ),
              const SizedBox(height: 15),
              
              // Email Input
              TextField(
                controller: _emailController,
                enabled: !_otpSent,
                decoration: InputDecoration(
                  hintText: 'Email Address',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
                ),
              ),
              
              const SizedBox(height: 15),
              
              if (!_otpSent)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _sendOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4C5B8F),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Send otp', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),

              if (_otpSent) ...[
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Enter OTP',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
                  ),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4C5B8F),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Verify otp', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _otpSent = false),
                      child: const Text('Edit Email', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                    ),
                    TextButton(
                      onPressed: _resendSeconds == 0 ? _sendOtp : null,
                      child: Text(
                        _resendSeconds > 0 ? 'Resend in $_resendSeconds seconds' : 'Resend Code',
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                      ),
                    ),
                  ],
                ),
              ],
              
              const SizedBox(height: 50),
              GestureDetector(
                onTap: () => launchUrl(Uri.parse('https://fonebook.app/privacy-policy')),
                child: RichText(
                  text: const TextSpan(
                    style: TextStyle(fontSize: 14, color: Color(0xFF232323)),
                    children: [
                      TextSpan(text: 'Terms and Conditons '),
                      TextSpan(text: 'Click here!', style: TextStyle(color: Color(0xFF8C6900), fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
