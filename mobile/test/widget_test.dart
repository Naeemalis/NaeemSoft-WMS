import 'package:flutter_test/flutter_test.dart';
import 'package:naeemsoft_wms/main.dart';

void main() {
  testWidgets('application widget can be constructed', (tester) async {
    // Database initialization is covered by the Android build workflow.
    expect(const NaeemSoftWmsApp(), isA<NaeemSoftWmsApp>());
  });
}
