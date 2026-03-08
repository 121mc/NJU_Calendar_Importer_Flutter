import 'package:flutter/material.dart';

class PromptedInstructionButton extends StatelessWidget {
  const PromptedInstructionButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      child: Icon(Icons.question_mark_rounded),
      onPressed: () => showInstructionAlert(context),
    );
  }

  void showInstructionAlert(BuildContext context) {
    showDialog(
        context: context, builder: (BuildContext context) => AlertDialog());
  }
}
