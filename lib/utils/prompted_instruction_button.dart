import 'package:flutter/material.dart';
import 'package:nju_calendar_importer_flutter/pages/instruction_page.dart';

class PromptedInstructionButton extends StatelessWidget {
  const PromptedInstructionButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      child: Icon(Icons.question_mark_rounded),
      onPressed: () {
        Navigator.of(context).push(
          PageRouteBuilder<void>(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const InstructionPage(),
            transitionDuration: const Duration(milliseconds: 320),
            reverseTransitionDuration: const Duration(milliseconds: 200),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              final curve = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );

              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(curve),
                child: child,
              );
            },
          ),
        );
      },
    );
  }
}
