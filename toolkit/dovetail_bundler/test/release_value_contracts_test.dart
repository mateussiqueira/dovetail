import 'package:dovetail_bundler/dovetail_bundler.dart';
import 'package:test/test.dart';

void main() {
  StagedFile file(String source, String destination) =>
      StagedFile(source: source, destination: destination);

  test('staged files distinguish both source and destination in sets', () {
    final StagedFile original = file('source', 'destination');
    expect(
      <StagedFile>{original}.contains(file('source', 'destination')),
      true,
    );
    expect(original, isNot(file('other', 'destination')));
    expect(original, isNot(file('source', 'other')));
    expect(original, isNot(Object()));
    expect(original.toString(), 'StagedFile(source -> destination)');
  });

  BundleSpec spec(String identifier, List<String> languages) => BundleSpec(
    productName: 'Example',
    manufacturer: 'Example Publisher',
    identifier: identifier,
    version: AppVersion.parse('1.0.0'),
    mainBinaryName: 'example',
    appDirectory: 'stage',
    outputDirectory: 'out',
    installerLanguages: languages,
  );

  test('bundle specs reject repeated installer languages before rendering', () {
    expect(
      () => spec('io.example.client', <String>['English', 'English']),
      throwsA(
        isA<BundleFailure>().having(
          (BundleFailure failure) => failure.message,
          'message',
          contains('declared twice'),
        ),
      ),
    );
  });

  test('bundle specs reject identifiers without a reverse domain', () {
    expect(
      () => spec('client', <String>['English']),
      throwsA(
        isA<BundleFailure>().having(
          (BundleFailure failure) => failure.message,
          'message',
          contains('reverse-domain'),
        ),
      ),
    );
  });
}
