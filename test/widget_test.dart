import 'package:flutter_test/flutter_test.dart';
import 'package:naeemsoft_wms/main.dart';

void main() {
  testWidgets('shows the Arabic WMS foundation dashboard', (tester) async {
    await tester.pumpWidget(const NaeemSoftWmsApp());

    expect(find.text('نظام إدارة المخازن والمخزون'), findsOneWidget);
    expect(find.text('مرحلة التأسيس'), findsOneWidget);
    expect(find.text('إدارة المخزون'), findsOneWidget);
  });
}
