import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:test/test.dart';

String manifestWith(String? pubDate) =>
    '{"version":"2.1.0",'
    '${pubDate == null ? '' : '"pub_date":"$pubDate",'}'
    '"platforms":{"darwin-universal":'
    '{"url":"https://cdn.example.com/a.tar.gz","signature":"x"}}}';

void main() {
  group('pub_date', () {
    test('a real date should come through', () {
      expect(
        ManifestParser.parse(manifestWith('2026-09-01T12:30:00Z')).publishedAt,
        DateTime.utc(2026, 9, 1, 12, 30),
      );
    });

    test('no pub_date at all should stay null', () {
      expect(ManifestParser.parse(manifestWith(null)).publishedAt, isNull);
    });

    test('a date that is not a date should be refused, not read as absent', () {
      expect(
        () => ManifestParser.parse(manifestWith('not-a-date-at-all')),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.remedy,
            'remedy',
            contains('silently removed'),
          ),
        ),
        reason:
            'tryParse returned null and null meant no date, so a typo removed '
            'the publication time without a word',
      );
    });

    test('an out-of-range field should be refused, not rolled forward', () {
      expect(
        () => ManifestParser.parse(manifestWith('2026-13-45T99:99:99Z')),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.remedy,
            'remedy',
            contains('months away'),
          ),
        ),
        reason:
            'measured: this used to be accepted and became 2027-02-18, a '
            'plausible date almost half a year from the one written',
      );
    });

    test('a month of 13 alone should still be refused', () {
      expect(
        () => ManifestParser.parse(manifestWith('2026-13-01T00:00:00Z')),
        throwsA(isA<UpdateFailure>()),
      );
    });

    test('a day past the end of the month should be refused', () {
      expect(
        () => ManifestParser.parse(manifestWith('2026-02-30T00:00:00Z')),
        throwsA(isA<UpdateFailure>()),
      );
    });

    test('a leap day that exists should be accepted', () {
      expect(
        ManifestParser.parse(manifestWith('2028-02-29T00:00:00Z')).publishedAt,
        DateTime.utc(2028, 2, 29),
      );
    });

    test('a date-only value should be accepted', () {
      expect(
        ManifestParser.parse(manifestWith('2026-09-01')).publishedAt,
        isNotNull,
      );
    });
  });
}
