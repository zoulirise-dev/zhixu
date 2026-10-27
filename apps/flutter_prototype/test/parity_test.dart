import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zhixu_prototype/core/completion.dart';
import 'package:zhixu_prototype/core/line_diff.dart';
import 'package:zhixu_prototype/core/syntax.dart';

void main() {
  test('additional languages include named config files, keywords and highlighting', () {
    final files = {
      'main.dart': 'dart',
      'main.kt': 'kotlin',
      'App.cs': 'csharp',
      'main.cc': 'cpp',
      'main.rb': 'ruby',
      'main.lua': 'lua',
      'script.ps1': 'powershell',
      'Dockerfile': 'dockerfile',
      'Makefile': 'makefile',
      'CMakeLists.txt': 'cmake',
      '.env.local': 'yaml',
      'query.gql': 'graphql',
    };
    for (final entry in files.entries) {
      expect(sourceLanguage(entry.key), entry.value);
      final word = vocabularies[entry.value]!.split(' ').first;
      expect(completeCode('', word.substring(0, 2), entry.value), isNotEmpty);
      expect(syntaxTokens(word, entry.value), isNotEmpty);
    }
  });
  test(
    'aligned comparison preserves both texts with repeated and inserted lines',
    () {
      expect(compareLines('a\nb\nc\n', 'a\nnew\nb\nc\n'), [
        (' ', 'a'),
        ('+', 'new'),
        (' ', 'b'),
        (' ', 'c'),
      ]);
      final random = Random(42);
      for (var n = 0; n < 500; n++) {
        final old = List.generate(
          random.nextInt(25),
          (_) => '${random.nextInt(6)}',
        );
        final next = List.generate(
          random.nextInt(25),
          (_) => '${random.nextInt(6)}',
        );
        final diff = compareLines(old.join('\n'), next.join('\n'));
        expect(diff.where((r) => r.$1 != '+').map((r) => r.$2).toList(), old);
        expect(diff.where((r) => r.$1 != '-').map((r) => r.$2).toList(), next);
      }
    },
  );
  test('native completion vocabulary, snippets and cursor position', () {
    expect(sourceLanguage('view.vue'), 'html');
    expect(sourceLanguage('main.py'), 'python');
    expect(completeCode('', 'so', 'java').first.$1, 'sout');
    expect(completeCode('', 'so', 'python'), isEmpty);
    expect(completeCode('', 'SE', 'sql').map((s) => s.$1), contains('SELECT'));
    final snippet = completeCode('', 'fu', 'javascript').first;
    final insertion = insertSnippet(snippet.$2, '    ');
    expect(insertion.$1, 'function name() {\n        \n    }');
    expect(insertion.$2, 'function name('.length);
  });
  test('all native language grammars compile and recognize tokens', () {
    for (final language in syntaxRules.keys) {
      final tokens = syntaxTokens(
        '/* comment */\nconst answer = 42;\n<div class="value">Hello</div>\n# heading\nSELECT name FROM records;\n@@ -1 +1 @@\n+new line\n-old line\n',
        language,
      ).toList();
      expect(tokens, isNotEmpty, reason: language);
      for (final token in tokens) {
        expect(token.$2, greaterThan(token.$1));
      }
    }
    expect(syntaxTokens('const x = 42;', 'plain'), isEmpty);
    const embedded =
        '<script>const n = 42;</script><style>.a { color: red; }</style>';
    final embeddedTokens = syntaxTokens(embedded, 'html').toList();
    expect(
      embeddedTokens.any(
        (t) => embedded.substring(t.$1, t.$2) == '42' && t.$3 == 'number',
      ),
      isTrue,
    );
    for (var i = 1; i < embeddedTokens.length; i++) {
      expect(
        embeddedTokens[i].$1,
        greaterThanOrEqualTo(embeddedTokens[i - 1].$2),
      );
    }
  });
}
