import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../models/user_session.dart';
import '../models/contact.dart';
import '../widgets/app_header.dart';

class VerificationScreen extends StatefulWidget {
  final DirectoryContact contact;
  const VerificationScreen({super.key, required this.contact});
  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  @override
  Widget build(BuildContext context) {
    final c = widget.contact;
    final bool isPhoneVerified = c.verified == 1; 
    final bool isEmailVerified = false; // Placeholder
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Fone Book',
              onBack: () => Navigator.pop(context),
              showMenu: true,
              api: ApiClient(),
              store: SessionStore(),
              session: UserSession(phone: widget.contact.phone),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 25),
                child: Column(
                  children: [
                    const Text(
                      'Verification',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF232323), fontFamily: 'Poppins'),
                    ),
                    const SizedBox(height: 35),
                    
                    _buildVerifyTile(
                      label: 'Mobile No Verification',
                      isVerified: isPhoneVerified,
                      onTap: () {
                        // Navigate to Mobile OTP
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification service coming soon')));
                      },
                    ),
                    const SizedBox(height: 15),
                    
                    _buildVerifyTile(
                      label: 'Email Verification',
                      isVerified: isEmailVerified,
                      onTap: () {
                        if (c.email == null || c.email!.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('First enter the Email in profile.')),
                          );
                          return;
                        }
                        // Navigate to Email OTP
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification service coming soon')));
                      },
                    ),
                    const SizedBox(height: 15),
                    
                    _buildVerifyTile(
                      label: 'Landline Verification',
                      isVerified: false,
                      onTap: () {
                        // Navigate to Voice Verification
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification service coming soon')));
                      },
                    ),
                    
                    const SizedBox(height: 50),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Verified profiles get higher priority in search results and trust badges on their profile.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.4, fontFamily: 'Poppins'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerifyTile({required String label, required bool isVerified, required VoidCallback onTap}) {
    return InkWell(
      onTap: isVerified ? null : onTap,
      child: Container(
        height: 65,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 2))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF232323), fontFamily: 'Poppins'),
              ),
            ),
            if (isVerified)
              Image.asset('assets/images/verified.png', width: 22, height: 22)
            else
              const Icon(Icons.chevron_right, color: Color(0xFFD7B41A)),
          ],
        ),
      ),
    );
  }
}
