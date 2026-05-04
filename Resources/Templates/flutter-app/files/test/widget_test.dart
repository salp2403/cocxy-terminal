import 'package:flutter_test/flutter_test.dart';
import 'package:{{project_name}}/main.dart';

void main() {
  testWidgets('renders app title', (tester) async {
    await tester.pumpWidget(const CocxyApp());
    expect(find.text('{{app_title}}'), findsOneWidget);
  });
}
