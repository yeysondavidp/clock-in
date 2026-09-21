import 'package:clock_in/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateService.compareVersions', () {
    test('detects newer versions', () {
      expect(UpdateService.compareVersions('1.0.1', '1.0.0'), greaterThan(0));
      expect(UpdateService.compareVersions('1.10.0', '1.9.9'), greaterThan(0));
      expect(UpdateService.compareVersions('2.0', '1.9.9'), greaterThan(0));
    });

    test('treats equal versions as equal', () {
      expect(UpdateService.compareVersions('1.0.0', '1.0.0'), 0);
      expect(UpdateService.compareVersions('v1.0.0', '1.0.0'), 0);
      expect(UpdateService.compareVersions('1.0', '1.0.0'), 0);
      expect(UpdateService.compareVersions('1.0.0+5', '1.0.0'), 0);
    });

    test('detects older versions', () {
      expect(UpdateService.compareVersions('1.0.0', '1.0.1'), lessThan(0));
      expect(UpdateService.compareVersions('V0.9.0', '1.0.0'), lessThan(0));
    });
  });
}
