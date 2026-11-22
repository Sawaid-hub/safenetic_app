import 'package:flutter/material.dart';

class SignOutRow extends StatelessWidget {
  final VoidCallback onSignOut;
  final VoidCallback onQuickSOS;

  const SignOutRow({
    super.key,
    required this.onSignOut,
    required this.onQuickSOS,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onSignOut,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: const Color(0xFFFF5252).withAlpha(100)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout, color: Color(0xFFFF5252), size: 18),
                  SizedBox(width: 8),
                  Text('Sign Out',
                      style: TextStyle(
                          color: Color(0xFFFF5252),
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: onQuickSOS,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFF5252),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Quick SOS',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
