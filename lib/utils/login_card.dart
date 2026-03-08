import 'package:flutter/material.dart';

import '../models/school_type.dart';

class LoginCard extends StatelessWidget {
  const LoginCard({
    super.key,
    required this.usernameHintController,
    required this.schoolType,
    required this.onSchoolTypeChanged,
    required this.loggingIn,
    required this.onOpenWebLogin,
  });

  final TextEditingController usernameHintController;
  final SchoolType schoolType;
  final ValueChanged<SchoolType> onSchoolTypeChanged;
  final bool loggingIn;
  final VoidCallback onOpenWebLogin;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '网页登录统一认证',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 22),
            const Text(
              ' 账号备注:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w400,
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: 330,
                child: TextField(
                  controller: usernameHintController,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SegmentedButton<SchoolType>(
              segments: const [
                ButtonSegment(
                  value: SchoolType.undergrad,
                  label: Text('本科生'),
                  icon: Icon(Icons.school),
                ),
                ButtonSegment(
                  value: SchoolType.graduate,
                  label: Text('研究生'),
                  icon: Icon(Icons.auto_stories),
                ),
              ],
              selected: {schoolType},
              onSelectionChanged: (value) {
                onSchoolTypeChanged(value.first);
              },
            ),
            FilledButton.icon(
              onPressed: loggingIn ? null : onOpenWebLogin,
              icon: loggingIn
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.language),
              label: const Text('打开官方登录页'),
            ),
            const SizedBox(height: 8),
            Text(
              '说明：\n账号备注可选,只用于本地显示。\n真正登录将在官方网页中完成。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              '点击后会在应用内打开官方登录页面。\n完成统一认证后自动返回。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
