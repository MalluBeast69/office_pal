import 'package:flutter/material.dart';

void showScreenSizeWarning(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => TweenAnimationBuilder(
      tween: Tween<double>(begin: 0.8, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.red, width: 3),
          ),
          backgroundColor: Colors.white,
          title: TweenAnimationBuilder(
            tween: ColorTween(begin: Colors.red.shade700, end: Colors.red),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeInOut,
            builder: (context, color, child) => Text(
              '⚠️ WARNING: SMALL SCREEN DETECTED ⚠️',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder(
                tween: Tween<double>(begin: 0.95, end: 1.05),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeInOut,
                builder: (context, scale, child) => Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      border: Border.all(color: Colors.red.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'IMPORTANT: These dashboards are DESIGNED FOR LARGER SCREENS (e.g., COMPUTERS)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.red,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'You WILL encounter:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              ...['VISUAL GLITCHES', 'LAYOUT ISSUES', 'POOR USER EXPERIENCE']
                  .map(
                (text) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        text,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                backgroundColor: Colors.red.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.red.shade300),
                ),
              ),
              child: const Text(
                'I Understand the Risks',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          actionsAlignment: MainAxisAlignment.center,
        ),
      ),
    ),
  );
}
