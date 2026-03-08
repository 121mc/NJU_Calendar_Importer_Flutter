import 'package:flutter/material.dart';

class InstructionPage extends StatelessWidget {
  const InstructionPage({super.key});

  static const TextStyle headingStyle =
      TextStyle(fontSize: 22, fontWeight: FontWeight.w700);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text("使用方法")),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: SingleChildScrollView(
            child: Column(children: [
              _customCard("第一步：选择身份并打开登录页", "01.jpg"),
              SizedBox(
                height: 16,
              ),
              _customCard("第二步：在弹出页面中登录", "02.jpg"),
              SizedBox(
                height: 16,
              ),
              _customCard("第三步：拉取本学期课表", "03.jpg"),
              SizedBox(
                height: 16,
              ),
              _customCard("第四步：加载现有默认日历", "04.jpg"),
              SizedBox(
                height: 16,
              ),
              _customCard("第五步：写入系统日历", "05.jpg"),
              SizedBox(
                height: 16,
              ),
              _customCard("可选：退出登陆状态", "06.jpg"),
            ]),
          ),
        ));
  }

  Card _customCard(String heading, String imageId) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              heading,
              style: headingStyle,
            ),
            SizedBox(
              height: 8,
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color.fromARGB(255, 18, 68, 94),
                  width: 2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset("assets/images/$imageId"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
