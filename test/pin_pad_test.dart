import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makhbazak/features/pin/pin_pad.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

Future<void> _tapDigits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.text(digit));
    await tester.pump();
  }
}

void main() {
  testWidgets('اكتمال 4 أرقام يستدعي onCompleted بالرمز', (tester) async {
    final entered = <String>[];
    await tester.pumpWidget(_host(PinPad(onCompleted: entered.add)));

    await _tapDigits(tester, '1234');

    expect(entered, ['1234']);
  });

  testWidgets('تفرغ اللوحة بعد الاكتمال فيمكن إدخال رمز ثانٍ', (tester) async {
    final entered = <String>[];
    await tester.pumpWidget(_host(PinPad(onCompleted: entered.add)));

    await _tapDigits(tester, '1234');
    await _tapDigits(tester, '9876');

    expect(entered, ['1234', '9876']);
  });

  testWidgets('زر المسح يحذف آخر رقم', (tester) async {
    final entered = <String>[];
    await tester.pumpWidget(_host(PinPad(onCompleted: entered.add)));

    await _tapDigits(tester, '12');
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    await _tapDigits(tester, '934');

    expect(entered, ['1934']);
  });

  testWidgets('اللوحة المعطلة لا تستقبل أرقاماً', (tester) async {
    final entered = <String>[];
    await tester.pumpWidget(_host(PinPad(onCompleted: entered.add, enabled: false)));

    await _tapDigits(tester, '1234');

    expect(entered, isEmpty);
  });
}
