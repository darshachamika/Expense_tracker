import 'dart:io';

void main() {
  final root = Directory.current;
  final pubspec = File('${root.path}/pubspec.yaml');
  final mainFile = File('${root.path}/lib/main.dart');
  if (!pubspec.existsSync() || !mainFile.existsSync()) {
    stderr.writeln('Run this command from the expense_tracker project folder.');
    exitCode = 1;
    return;
  }
  final package = RegExp(r'^name:\s*([a-zA-Z0-9_]+)', multiLine: true)
      .firstMatch(pubspec.readAsStringSync())?.group(1);
  if (package == null) {
    stderr.writeln('Could not read the package name from pubspec.yaml.');
    exitCode = 1;
    return;
  }

  final widgetTest = File('${root.path}/test/widget_test.dart');
  if (widgetTest.existsSync() &&
      RegExp(r'\bMyApp\s*\(').hasMatch(widgetTest.readAsStringSync())) {
    if (!RegExp(r'class\s+FirebaseErrorApp\b').hasMatch(mainFile.readAsStringSync())) {
      stderr.writeln('FirebaseErrorApp was not found in lib/main.dart. Share the current main.dart and widget_test.dart.');
      exitCode = 1;
      return;
    }
    widgetTest.writeAsStringSync('''import 'package:flutter_test/flutter_test.dart';
import 'package:$package/main.dart';

void main() {
  testWidgets('Firebase setup failure shows recovery instructions', (tester) async {
    await tester.pumpWidget(const FirebaseErrorApp());

    expect(find.textContaining('Firebase setup could not finish.'), findsOneWidget);
    expect(find.textContaining('Check the terminal output'), findsOneWidget);
  });
}
''');
    stdout.writeln('Replaced the obsolete MyApp counter test with a Firebase recovery screen test.');
  }

  final billTest = File('${root.path}/test/bill_actions_test.dart');
  if (billTest.existsSync()) {
    var source = billTest.readAsStringSync();
    const explanation = '// Firestore SDK interfaces are implemented here only as test doubles.';
    if (!source.contains(explanation)) {
      source = source.replaceAllMapped(
        RegExp(r'^class (_Collection|_Document|_Snapshot)\b', multiLine: true),
        (match) => '$explanation\n// ignore: subtype_of_sealed_class\n${match.group(0)}',
      );
      billTest.writeAsStringSync(source);
      stdout.writeln('Documented the three Firestore test doubles with local analyzer exceptions.');
    }
  }

  final advisorData = File('${root.path}/lib/services/advisor_data_service.dart');
  if (advisorData.existsSync()) {
    final source = advisorData.readAsStringSync();
    final updated = source.replaceAll(
      RegExp(r'\(sum,\s*contribution\)\s*=>\s*sum\s*\+\s*contribution\.amountMinor'),
      '(total, contribution) => total + contribution.amountMinor',
    );
    if (updated != source) {
      advisorData.writeAsStringSync(updated);
      stdout.writeln('Renamed the contribution accumulator to total.');
    }
  }

  const codes = 'unnecessary_import,prefer_initializing_formals,'
      'curly_braces_in_flow_control_structures,avoid_relative_lib_imports';
  final result = Process.runSync(
    Platform.resolvedExecutable,
    ['fix', '--apply', '--code=$codes'],
    workingDirectory: root.path,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  exitCode = result.exitCode;
  if (result.exitCode == 0) {
    stdout.writeln('Cleanup finished. Run flutter analyze, then flutter test.');
  }
}
