import 'package:flutter_test/flutter_test.dart';
import 'package:zhixu_prototype/core/git_service.dart';

class RetryGit extends GitService {
  bool rejectNetwork = false;
  bool failSave = false;
  final calls = <(List<String>, Map<String, String>, String?)>[];
  @override
  Future<String> remoteURL(
    String root,
    String remote, {
    bool push = false,
  }) async => 'https://example.invalid/team/repo.git';
  @override
  Future<GitReply> run(
    String root,
    List<String> args, {
    Map<String, String> env = const {},
    String? input,
    bool check = true,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    calls.add((args, env, input));
    if (args.first == 'fetch' && rejectNetwork) {
      throw GitFailure(FailureKind.authentication, 'Rejected');
    }
    if (args.first == 'config') return const GitReply(0, 'manager\n', '');
    if (args.first == 'credential' && failSave) {
      throw GitFailure(FailureKind.other, 'Cannot save');
    }
    return const GitReply(0, '', '');
  }
}

void main() {
  HttpsCredential credential() => HttpsCredential(
    Uri.parse('https://example.invalid/team/repo.git'),
    'demo',
    'fixture-only',
  );
  test(
    'successful retry approves through helper stdin, never argv or config file',
    () async {
      final git = RetryGit();
      await git.network('/repo', 'origin', 'fetch', credential: credential());
      expect(git.calls.first.$1, ['fetch', '--', 'origin']);
      expect(
        git.calls.first.$2['GIT_CONFIG_KEY_0'],
        'http.https://example.invalid/team/repo.git.extraHeader',
      );
      expect(git.calls.first.$2['GIT_CONFIG_VALUE_2'], 'false');
      expect(git.calls.last.$1, ['credential', 'approve']);
      expect(git.calls.last.$3, contains('password=fixture-only\n'));
      expect(
        git.calls.expand((c) => c.$1).join(' '),
        isNot(contains('fixture-only')),
      );
    },
  );
  test(
    'rejected login never approves or erases existing stored credentials',
    () async {
      final git = RetryGit()..rejectNetwork = true;
      await expectLater(
        git.network('/repo', 'origin', 'fetch', credential: credential()),
        throwsA(isA<GitFailure>()),
      );
      expect(git.calls.length, 1);
      expect(git.calls.first.$2['GIT_CONFIG_VALUE_1'], '');
    },
  );
  test(
    'credential save failure does not report successful push as failed',
    () async {
      final git = RetryGit()..failSave = true;
      expect(
        await git.network('/repo', 'origin', 'fetch', credential: credential()),
        contains('操作成功'),
      );
    },
  );
  test('credentials cannot be reused after a remote changes', () async {
    final git = RetryGit();
    final other = HttpsCredential(
      Uri.parse('https://other.invalid/repo.git'),
      'demo',
      'fixture',
    );
    await expectLater(
      git.network('/repo', 'origin', 'fetch', credential: other),
      throwsA(isA<GitFailure>()),
    );
    expect(git.calls, isEmpty);
  });
}
