import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

List<String> windowsDrivesFromMask(int mask) => [
  for (var i = 0; i < 26; i++)
    if (mask & (1 << i) != 0) '${String.fromCharCode(65 + i)}:\\',
];

class DirectoryBrowser {
  final bool windows;
  final String home;
  final Future<List<String>> Function(String)? folderLoader;
  final Future<List<String>> Function()? driveLoader;
  DirectoryBrowser({
    bool? windows,
    String? home,
    this.folderLoader,
    this.driveLoader,
  }) : windows = windows ?? Platform.isWindows,
       home =
           home ??
           Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ??
           Directory.current.path;
  p.Context get paths =>
      p.Context(style: windows ? p.Style.windows : p.Style.posix);
  String normalize(String input, String current) {
    var value = input.trim();
    if (value == '~' || value.startsWith('~/') || value.startsWith('~\\')) {
      value = home + value.substring(1);
    }
    if (windows && RegExp(r'^[a-zA-Z]:$').hasMatch(value)) {
      value += '\\';
    }
    if (value.isEmpty) return current.isEmpty ? home : current;
    return paths.normalize(
      paths.isAbsolute(value)
          ? value
          : paths.join(current.isEmpty ? home : current, value),
    );
  }

  bool isRoot(String value) =>
      value.isNotEmpty && paths.dirname(value) == value;
  Future<List<String>> drives() async {
    if (driveLoader != null) return driveLoader!();
    final getDrives = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<Uint32 Function(), int Function()>('GetLogicalDrives');
    final mask = getDrives();
    if (mask == 0) {
      throw const FileSystemException('Unable to enumerate drives');
    }
    return windowsDrivesFromMask(mask);
  }

  Future<List<String>> folders(String value) async {
    if (folderLoader != null) return folderLoader!(value);
    final result = <String>[];
    // Do not stat every child: protected system folders must not break the parent listing.
    await for (final entry in Directory(value).list(followLinks: false)) {
      if (paths.basename(entry.path).startsWith('.')) continue;
      if (entry is Directory) {
        result.add(entry.path);
      } else if (entry is Link) {
        try {
          if (await Directory(entry.path).exists()) result.add(entry.path);
        } on FileSystemException {
          // An inaccessible or broken link does not make its parent inaccessible.
        }
      }
    }
    result.sort(
      (a, b) => paths
          .basename(a)
          .toLowerCase()
          .compareTo(paths.basename(b).toLowerCase()),
    );
    return result;
  }
}
