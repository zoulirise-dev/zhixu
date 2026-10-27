import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zhixu_prototype/core/git_service.dart';

void main() {
  test(
    'image snapshots preserve binary bytes across worktree, index and history',
    () async {
      final dir = await Directory.systemTemp.createTemp('zhixu-image-test-');
      addTearDown(() => dir.delete(recursive: true));
      final git = GitService(
        environment: {
          'GIT_CONFIG_NOSYSTEM': '1',
          'GIT_CONFIG_GLOBAL': '${dir.path}/no-config',
        },
      );
      final root = dir.path;
      await git.run(root, ['init', '-b', 'main']);
      await git.saveAuthor(root, 'Test', 'test@example.invalid');
      await git.run(root, ['config', 'commit.gpgsign', 'false']);
      final file = File('$root/image.png');
      final original = [137, 80, 78, 71, 0, 255, 254, 129];
      await file.writeAsBytes(original);
      await git.run(root, ['add', 'image.png']);
      await git.run(root, ['commit', '-m', 'image']);
      expect(await git.imageAt(root, 'image.png', 'HEAD'), original);
      expect(await git.imageAt(root, 'image.png', 'HEAD^1'), isNull);
      await file.writeAsBytes([0, 255, 128, 3]);
      await git.run(root, ['add', 'image.png']);
      await file.writeAsBytes([0, 255, 128, 4]);
      expect(await git.imageAt(root, 'image.png', ''), [0, 255, 128, 3]);
      expect(await git.imageAt(root, 'image.png', null), [0, 255, 128, 4]);
      expect(await git.imageAt(root, 'image.png', 'HEAD'), original);
      await file.delete();
      expect(await git.imageAt(root, 'image.png', null), isNull);
      expect(await git.imageAt(root, 'image.png', 'HEAD'), original);
      expect(await git.imageAt(root, 'absent.png', 'HEAD'), isNull);
    },
  );
}
