import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftalarm/ui/widgets/duo_book_page_view.dart';

void main() {
  group('DuoPageController 單元測試', () {
    test('初始頁碼與預設狀態正確', () {
      final ctrl = DuoPageController(initialPage: 10);
      expect(ctrl.page, 10);
      expect(ctrl.hasClients, false);
    });

    test('未附加到 Widget 時 jumpToPage 直接更新頁碼並觸發通知', () {
      final ctrl = DuoPageController(initialPage: 5);
      bool notified = false;
      ctrl.addListener(() => notified = true);

      ctrl.jumpToPage(12);
      expect(ctrl.page, 12);
      expect(notified, true);
    });
  });

  group('DuoBookPageView 組件測試', () {
    testWidgets('靜態狀態下正確渲染當前頁內容', (tester) async {
      final ctrl = DuoPageController(initialPage: 100);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DuoBookPageView(
              controller: ctrl,
              itemBuilder: (context, page) {
                return Center(
                  child: Text('Page: $page', textDirection: TextDirection.ltr),
                );
              },
            ),
          ),
        ),
      );

      expect(ctrl.hasClients, true);
      expect(find.text('Page: 100'), findsOneWidget);
    });

    testWidgets('jumpToPage 立即切換頁面', (tester) async {
      final ctrl = DuoPageController(initialPage: 1);
      int? changedPage;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DuoBookPageView(
              controller: ctrl,
              onPageChanged: (p) => changedPage = p,
              itemBuilder: (context, page) {
                return Center(
                  child: Text('Page: $page', textDirection: TextDirection.ltr),
                );
              },
            ),
          ),
        ),
      );

      ctrl.jumpToPage(5);
      await tester.pumpAndSettle();

      expect(ctrl.page, 5);
      expect(changedPage, 5);
      expect(find.text('Page: 5'), findsOneWidget);
    });

    testWidgets('animateToPage 正向翻頁播放 3D 掀開並透出下一頁', (tester) async {
      final ctrl = DuoPageController(initialPage: 1);
      int? changedPage;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DuoBookPageView(
              controller: ctrl,
              onPageChanged: (p) => changedPage = p,
              itemBuilder: (context, page) {
                return Center(
                  child: Text('Page: $page', textDirection: TextDirection.ltr),
                );
              },
            ),
          ),
        ),
      );

      // 觸發向後翻頁
      ctrl.animateToPage(2, duration: const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // 動畫進行中，同時掛載 Page 1（頂層翻動）與 Page 2（底層透出）
      expect(find.text('Page: 1'), findsOneWidget);
      expect(find.text('Page: 2'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(ctrl.page, 2);
      expect(changedPage, 2);
      expect(find.text('Page: 2'), findsOneWidget);
      expect(find.text('Page: 1'), findsNothing);
    });

    testWidgets('animateToPage 逆向翻頁上一頁由外部翻入覆蓋', (tester) async {
      final ctrl = DuoPageController(initialPage: 2);
      int? changedPage;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DuoBookPageView(
              controller: ctrl,
              onPageChanged: (p) => changedPage = p,
              itemBuilder: (context, page) {
                return Center(
                  child: Text('Page: $page', textDirection: TextDirection.ltr),
                );
              },
            ),
          ),
        ),
      );

      // 觸發向前翻頁
      ctrl.animateToPage(1, duration: const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // 動畫進行中，Page 1 由外部向內旋轉覆蓋在 Page 2 上
      expect(find.text('Page: 1'), findsOneWidget);
      expect(find.text('Page: 2'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(ctrl.page, 1);
      expect(changedPage, 1);
      expect(find.text('Page: 1'), findsOneWidget);
      expect(find.text('Page: 2'), findsNothing);
    });

    testWidgets('手勢向左滑動觸發向前翻頁', (tester) async {
      final ctrl = DuoPageController(initialPage: 1);
      int? changedPage;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: DuoBookPageView(
                controller: ctrl,
                onPageChanged: (p) => changedPage = p,
                itemBuilder: (context, page) {
                  return Center(
                    child: Text('Page: $page', textDirection: TextDirection.ltr),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // 向左大幅滑動超過 35% 門檻
      await tester.drag(find.byType(DuoBookPageView), const Offset(-200, 0));
      await tester.pumpAndSettle();

      expect(ctrl.page, 2);
      expect(changedPage, 2);
      expect(find.text('Page: 2'), findsOneWidget);
    });
  });
}
