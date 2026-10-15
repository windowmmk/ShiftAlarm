import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('空字串 Text 佔唔佔行高', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Text('', style: TextStyle(fontSize: 16)),
              Text('a', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
    final emptyBox =
        tester.getSize(find.text('', skipOffstage: false));
    final aBox = tester.getSize(find.text('a', skipOffstage: false));
    // ignore: avoid_print
    print('empty size=$emptyBox, a size=$aBox');
    // 空字串應該佔一行高（同 'a' 一樣高），唔係零
    expect(emptyBox.height, greaterThan(0));
    expect(emptyBox.height, equals(aBox.height));
  });
}
