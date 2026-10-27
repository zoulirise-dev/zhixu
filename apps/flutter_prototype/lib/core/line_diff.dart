/// A bounded Myers line diff. The fallback remains a valid full replacement,
/// rather than misidentifying equal-looking rows at different line numbers.
List<(String, String)> compareLines(String before, String after) {
  List<String> lines(String value) {
    if (value.isEmpty) return [];
    final result = value.split('\n');
    if (result.last.isEmpty) result.removeLast();
    return result;
  }

  final a = lines(before), b = lines(after);
  final v = <int, int>{1: 0};
  final trace = <Map<int, int>>[];
  for (var d = 0; d <= a.length + b.length && d <= 512; d++) {
    trace.add(Map.of(v));
    for (var k = -d; k <= d; k += 2) {
      var x = k == -d || k != d && (v[k - 1] ?? 0) < (v[k + 1] ?? 0)
          ? v[k + 1] ?? 0
          : (v[k - 1] ?? 0) + 1;
      var y = x - k;
      while (x < a.length && y < b.length && a[x] == b[y]) {
        x++;
        y++;
      }
      v[k] = x;
      if (x >= a.length && y >= b.length) {
        final result = <(String, String)>[];
        for (var depth = trace.length - 1; depth >= 0; depth--) {
          final previous = trace[depth], diagonal = x - y;
          final pk =
              diagonal == -depth ||
                  diagonal != depth &&
                      (previous[diagonal - 1] ?? 0) <
                          (previous[diagonal + 1] ?? 0)
              ? diagonal + 1
              : diagonal - 1;
          final px = previous[pk] ?? 0, py = px - pk;
          while (x > px && y > py) {
            result.add((' ', a[x - 1]));
            x--;
            y--;
          }
          if (depth > 0) {
            if (x == px) {
              result.add(('+', b[y - 1]));
              y--;
            } else {
              result.add(('-', a[x - 1]));
              x--;
            }
          }
        }
        return result.reversed.toList();
      }
    }
  }
  return [...a.map((s) => ('-', s)), ...b.map((s) => ('+', s))];
}
