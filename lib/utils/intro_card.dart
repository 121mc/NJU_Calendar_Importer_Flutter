import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../pages/privacy_policy_page.dart';

class IntroCard extends StatefulWidget {
  const IntroCard({super.key});

  @override
  State<IntroCard> createState() => _IntroCardState();
}

class _IntroCardState extends State<IntroCard> {
  late final TapGestureRecognizer _tapToWebsite;
  late final TapGestureRecognizer _tapToPrivacyPolicy;
  static const TextStyle linkStyle = TextStyle(
    color: Colors.blue,
    decoration: TextDecoration.underline,
    decorationColor: Colors.blue,
  );
  static const TextStyle privacyStyle = TextStyle(
      fontWeight: FontWeight.bold,
      color: Colors.deepPurple,
      decoration: TextDecoration.underline,
      decorationColor: Colors.deepPurple,
      fontSize: 20);

  static const TextStyle stressStyle =
      TextStyle(fontWeight: FontWeight.bold, fontSize: 18);

  @override
  void initState() {
    super.initState();
    _tapToWebsite = TapGestureRecognizer()..onTap = _launchWebUrl;
    _tapToPrivacyPolicy = TapGestureRecognizer()..onTap = _openPrivacyPolicy;
  }

  @override
  void dispose() {
    _tapToWebsite.dispose();
    _tapToPrivacyPolicy.dispose();
    super.dispose();
  }

  Future<void> _launchWebUrl() async {
    final Uri url =
        Uri.parse('https://github.com/121mc/NJU_Calendar_Importer_Flutter');

    if (!await canLaunchUrl(url)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开链接：${url.toString()}')),
      );
      return;
    }
    await launchUrl(url, mode: LaunchMode.externalApplication); // fixed typo
  }

  void _openPrivacyPolicy() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
        child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('1. 本项目旨在提供一个课表导入手机日历解决方案，供有需求的同学参考使用。'),
        const Text('2. 本项目完全免费开源，且不包含任何广告或内购；使用过程中也不会将课表数据上传到开发者自建服务器。'),
        const Text('3. 本应用仅在你主动使用相关功能时访问官方系统，并在获得授权后申请日历权限。'),
        const Text('4. 本项目是个人开发项目，与位于江苏省南京市的任何大学均无关。'),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                  text: "5.该项目由_121_mc,FrozenDashing以及其他贡献者开发，项目链接："),
              TextSpan(
                text: "https://github.com/121mc/NJU_Calendar_Importer_Flutter",
                style: linkStyle,
                recognizer: _tapToWebsite,
              ),
            ],
          ),
        ),
        SizedBox(
          height: 10,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text.rich(
                textAlign: TextAlign.right,
                TextSpan(children: [
                  const TextSpan(text: '在使用本应用之前请先查看', style: stressStyle),
                ]),
              ),
              Text.rich(
                  textAlign: TextAlign.right,
                  TextSpan(
                    text: '隐私政策',
                    style: privacyStyle,
                    recognizer: _tapToPrivacyPolicy,
                  ))
            ],
          ),
        )
      ]),
    ));
  }
}
