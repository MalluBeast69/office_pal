import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScreenSizeWarningDialog extends StatelessWidget {
  final String role;

  const ScreenSizeWarningDialog({
    super.key,
    required this.role,
  });

  static Future<void> showWarningIfNeeded(
      BuildContext context, String role) async {
    final prefs = await SharedPreferences.getInstance();
    final dontShowAgain = prefs.getBool('dontShowScreenWarning_$role') ?? false;

    if (dontShowAgain) return;

    if (context.mounted && MediaQuery.of(context).size.width < 1024) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => ScreenSizeWarningDialog(role: role),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange[700]),
          const SizedBox(width: 8),
          const Text('Screen Size Warning'),
        ],
      ),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This interface is designed for larger screens.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'While you can use it on your current device, you may experience some visual glitches. For the best experience, we recommend using a larger screen (e.g., computer monitor).',
          ),
        ],
      ),
      actions: [
        StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DontShowAgainCheckbox(role: role),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DontShowAgainCheckbox extends StatefulWidget {
  final String role;

  const _DontShowAgainCheckbox({required this.role});

  @override
  State<_DontShowAgainCheckbox> createState() => _DontShowAgainCheckboxState();
}

class _DontShowAgainCheckboxState extends State<_DontShowAgainCheckbox> {
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      title: const Text(
        "Don't show this again",
        style: TextStyle(fontSize: 14),
      ),
      value: _dontShowAgain,
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: (bool? value) async {
        if (value == true) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('dontShowScreenWarning_${widget.role}', true);
        }
        setState(() {
          _dontShowAgain = value ?? false;
        });
      },
    );
  }
}
