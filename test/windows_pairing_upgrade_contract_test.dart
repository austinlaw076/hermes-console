import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Windows pairing upgrade contract', () {
    late String script;

    setUpAll(() {
      script = File('scripts/hermes-pair.ps1').readAsStringSync();
    });

    test('repairs legacy installs instead of trapping users in a retry loop', () {
      expect(script, contains('function Invoke-VerifiedSetupRepair'));
      expect(
        script,
        contains(r'$setupUrl = "$RepoRaw/hermes-mobile-setup.ps1"'),
      );
      expect(
        script,
        contains(
          'Invoke-VerifiedSetupRepair "This installation predates verified pairing."',
        ),
      );
      expect(
        script,
        isNot(contains('throw "This installation predates verified pairing.')),
      );
    });

    test('repairs missing credentials and malformed pairing metadata', () {
      expect(
        script,
        contains('Invoke-VerifiedSetupRepair "No valid API token was found."'),
      );
      expect(
        script,
        contains(
          'Invoke-VerifiedSetupRepair "The saved pairing record is unreadable."',
        ),
      );
      expect(
        script,
        contains(
          'Invoke-VerifiedSetupRepair "The saved pairing record is outdated."',
        ),
      );
    });

    test('checks the downloaded installer identity before executing it', () {
      expect(
        script,
        contains(
          r'$setupSource.StartsWith("# Hermes Console - native Windows setup")',
        ),
      );
      expect(
        script,
        contains(
          r"$setupSource -notmatch '(?m)^function Get-PairingConfiguration'",
        ),
      );
      expect(script, contains(r'^\$PairingFile = Join-Path \$ServicesDir'));
      expect(script, contains('[ScriptBlock]::Create(\$setupSource)'));
    });
  });
}
