// Lexical rules ported from apps/macos/Sources/Zhixu/Syntax.swift.
const syntaxRules = <String, List<(String, String)>>{
  "diff": [
    ("insertion", "^\\+.*\$"),
    ("deletion", "^-.*\$"),
    ("keyword", "^@@.*\$"),
    ("comment", "^(?:diff |index ).*\$"),
  ],
  "markdown": [
    ("string", "^```[^\\n]*\\n[\\s\\S]*?^```[^\\n]*|`[^`\\n]+`"),
    ("heading", "^#{1,6}\\s+.*\$"),
    ("comment", "<!--[\\s\\S]*?-->"),
    ("string", "\\[[^\\]\\n]+\\]\\([^\\)\\n]+\\)"),
    ("keyword", "\\*\\*[^*\\n]+\\*\\*|__[^_\\n]+__|^\\s*[-*>]\\s"),
  ],
  "html": [
    ("comment", "<!--[\\s\\S]*?-->"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`",
    ),
    ("tag", "</?[A-Za-z][\\w:.-]*|/?>"),
    ("property", "[\\w:-]+(?=\\s*=)"),
  ],
  "json": [
    ("comment", "//[^\\n]*|/\\*[\\s\\S]*?\\*/"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`",
    ),
    ("property", "\"(?:\\\\.|[^\"\\\\])*\"(?=\\s*:)"),
    ("keyword", "\\b(?:true|false|null)\\b"),
    ("number", "-?\\b\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b"),
  ],
  "java": [
    ("comment", "//[^\\n]*|/\\*[\\s\\S]*?\\*/"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:abstract|assert|async|await|as|break|case|catch|class|const|continue|debugger|default|defer|delete|do|else|enum|export|extends|false|final|finally|for|from|func|function|guard|if|implements|import|in|instanceof|interface|internal|is|let|new|nil|null|of|open|override|package|private|protected|public|readonly|record|return|self|static|struct|super|switch|synchronized|this|throw|throws|true|try|type|typeof|var|void|while|yield|def|elif|except|lambda|None|True|False|not|and|or|pass|with|raise|print|echo|namespace|use|include|require|require_once|include_once|foreach|endforeach|endif|isset|empty|fn|pub|impl|match|mut|trait|where|unsafe|mod|crate|go|range|select|chan|map|select|SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|ON|GROUP|BY|ORDER|LIMIT|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|AS|AND|OR|NOT|NULL|IS|DISTINCT|UNION)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b"),
    (
      "type",
      "\\b(?:String|Int|Integer|Boolean|Double|Float|Array|List|Map|Set|Optional|Object|bool|boolean|int|long|float|double|char|byte|short|[A-Z][A-Za-z0-9_]+)\\b",
    ),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "php": [
    ("comment", "//[^\\n]*|#[^\\n]*|/\\*[\\s\\S]*?\\*/"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:abstract|assert|async|await|as|break|case|catch|class|const|continue|debugger|default|defer|delete|do|else|enum|export|extends|false|final|finally|for|from|func|function|guard|if|implements|import|in|instanceof|interface|internal|is|let|new|nil|null|of|open|override|package|private|protected|public|readonly|record|return|self|static|struct|super|switch|synchronized|this|throw|throws|true|try|type|typeof|var|void|while|yield|def|elif|except|lambda|None|True|False|not|and|or|pass|with|raise|print|echo|namespace|use|include|require|require_once|include_once|foreach|endforeach|endif|isset|empty|fn|pub|impl|match|mut|trait|where|unsafe|mod|crate|go|range|select|chan|map|select|SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|ON|GROUP|BY|ORDER|LIMIT|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|AS|AND|OR|NOT|NULL|IS|DISTINCT|UNION)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b"),
    (
      "type",
      "\\b(?:String|Int|Integer|Boolean|Double|Float|Array|List|Map|Set|Optional|Object|bool|boolean|int|long|float|double|char|byte|short|[A-Z][A-Za-z0-9_]+)\\b",
    ),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
    ("property", "\\\$[a-zA-Z_][\\w]*"),
  ],
  "javascript": [
    ("comment", "//[^\\n]*|/\\*[\\s\\S]*?\\*/"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:abstract|assert|async|await|as|break|case|catch|class|const|continue|debugger|default|defer|delete|do|else|enum|export|extends|false|final|finally|for|from|func|function|guard|if|implements|import|in|instanceof|interface|internal|is|let|new|nil|null|of|open|override|package|private|protected|public|readonly|record|return|self|static|struct|super|switch|synchronized|this|throw|throws|true|try|type|typeof|var|void|while|yield|def|elif|except|lambda|None|True|False|not|and|or|pass|with|raise|print|echo|namespace|use|include|require|require_once|include_once|foreach|endforeach|endif|isset|empty|fn|pub|impl|match|mut|trait|where|unsafe|mod|crate|go|range|select|chan|map|select|SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|ON|GROUP|BY|ORDER|LIMIT|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|AS|AND|OR|NOT|NULL|IS|DISTINCT|UNION)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b"),
    (
      "type",
      "\\b(?:String|Int|Integer|Boolean|Double|Float|Array|List|Map|Set|Optional|Object|bool|boolean|int|long|float|double|char|byte|short|[A-Z][A-Za-z0-9_]+)\\b",
    ),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "typescript": [
    ("comment", "//[^\\n]*|/\\*[\\s\\S]*?\\*/"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:abstract|assert|async|await|as|break|case|catch|class|const|continue|debugger|default|defer|delete|do|else|enum|export|extends|false|final|finally|for|from|func|function|guard|if|implements|import|in|instanceof|interface|internal|is|let|new|nil|null|of|open|override|package|private|protected|public|readonly|record|return|self|static|struct|super|switch|synchronized|this|throw|throws|true|try|type|typeof|var|void|while|yield|def|elif|except|lambda|None|True|False|not|and|or|pass|with|raise|print|echo|namespace|use|include|require|require_once|include_once|foreach|endforeach|endif|isset|empty|fn|pub|impl|match|mut|trait|where|unsafe|mod|crate|go|range|select|chan|map|select|SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|ON|GROUP|BY|ORDER|LIMIT|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|AS|AND|OR|NOT|NULL|IS|DISTINCT|UNION)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b"),
    (
      "type",
      "\\b(?:String|Int|Integer|Boolean|Double|Float|Array|List|Map|Set|Optional|Object|bool|boolean|int|long|float|double|char|byte|short|[A-Z][A-Za-z0-9_]+)\\b",
    ),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "swift": [
    ("comment", "//[^\\n]*|/\\*[\\s\\S]*?\\*/"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:abstract|assert|async|await|as|break|case|catch|class|const|continue|debugger|default|defer|delete|do|else|enum|export|extends|false|final|finally|for|from|func|function|guard|if|implements|import|in|instanceof|interface|internal|is|let|new|nil|null|of|open|override|package|private|protected|public|readonly|record|return|self|static|struct|super|switch|synchronized|this|throw|throws|true|try|type|typeof|var|void|while|yield|def|elif|except|lambda|None|True|False|not|and|or|pass|with|raise|print|echo|namespace|use|include|require|require_once|include_once|foreach|endforeach|endif|isset|empty|fn|pub|impl|match|mut|trait|where|unsafe|mod|crate|go|range|select|chan|map|select|SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|ON|GROUP|BY|ORDER|LIMIT|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|AS|AND|OR|NOT|NULL|IS|DISTINCT|UNION)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b"),
    (
      "type",
      "\\b(?:String|Int|Integer|Boolean|Double|Float|Array|List|Map|Set|Optional|Object|bool|boolean|int|long|float|double|char|byte|short|[A-Z][A-Za-z0-9_]+)\\b",
    ),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "python": [
    ("string", "\\\"\\\"\\\"[\\s\\S]*?\\\"\\\"\\\"|'''[\\s\\S]*?'''"),
    ("comment", "#[^\\n]*"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:abstract|assert|async|await|as|break|case|catch|class|const|continue|debugger|default|defer|delete|do|else|enum|export|extends|false|final|finally|for|from|func|function|guard|if|implements|import|in|instanceof|interface|internal|is|let|new|nil|null|of|open|override|package|private|protected|public|readonly|record|return|self|static|struct|super|switch|synchronized|this|throw|throws|true|try|type|typeof|var|void|while|yield|def|elif|except|lambda|None|True|False|not|and|or|pass|with|raise|print|echo|namespace|use|include|require|require_once|include_once|foreach|endforeach|endif|isset|empty|fn|pub|impl|match|mut|trait|where|unsafe|mod|crate|go|range|select|chan|map|select|SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|ON|GROUP|BY|ORDER|LIMIT|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|AS|AND|OR|NOT|NULL|IS|DISTINCT|UNION)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b"),
    (
      "type",
      "\\b(?:String|Int|Integer|Boolean|Double|Float|Array|List|Map|Set|Optional|Object|bool|boolean|int|long|float|double|char|byte|short|[A-Z][A-Za-z0-9_]+)\\b",
    ),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "yaml": [
    ("comment", "#[^\\n]*"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`",
    ),
    ("property", "^\\s*[\\w.-]+(?=\\s*[:=])"),
    (
      "keyword",
      "\\b(?:abstract|assert|async|await|as|break|case|catch|class|const|continue|debugger|default|defer|delete|do|else|enum|export|extends|false|final|finally|for|from|func|function|guard|if|implements|import|in|instanceof|interface|internal|is|let|new|nil|null|of|open|override|package|private|protected|public|readonly|record|return|self|static|struct|super|switch|synchronized|this|throw|throws|true|try|type|typeof|var|void|while|yield|def|elif|except|lambda|None|True|False|not|and|or|pass|with|raise|print|echo|namespace|use|include|require|require_once|include_once|foreach|endforeach|endif|isset|empty|fn|pub|impl|match|mut|trait|where|unsafe|mod|crate|go|range|select|chan|map|select|SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|ON|GROUP|BY|ORDER|LIMIT|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|AS|AND|OR|NOT|NULL|IS|DISTINCT|UNION)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b"),
    (
      "type",
      "\\b(?:String|Int|Integer|Boolean|Double|Float|Array|List|Map|Set|Optional|Object|bool|boolean|int|long|float|double|char|byte|short|[A-Z][A-Za-z0-9_]+)\\b",
    ),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "sql": [
    ("comment", "--[^\\n]*|/\\*[\\s\\S]*?\\*/"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:abstract|assert|async|await|as|break|case|catch|class|const|continue|debugger|default|defer|delete|do|else|enum|export|extends|false|final|finally|for|from|func|function|guard|if|implements|import|in|instanceof|interface|internal|is|let|new|nil|null|of|open|override|package|private|protected|public|readonly|record|return|self|static|struct|super|switch|synchronized|this|throw|throws|true|try|type|typeof|var|void|while|yield|def|elif|except|lambda|None|True|False|not|and|or|pass|with|raise|print|echo|namespace|use|include|require|require_once|include_once|foreach|endforeach|endif|isset|empty|fn|pub|impl|match|mut|trait|where|unsafe|mod|crate|go|range|select|chan|map|select|SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|ON|GROUP|BY|ORDER|LIMIT|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|AS|AND|OR|NOT|NULL|IS|DISTINCT|UNION)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b"),
    (
      "type",
      "\\b(?:String|Int|Integer|Boolean|Double|Float|Array|List|Map|Set|Optional|Object|bool|boolean|int|long|float|double|char|byte|short|[A-Z][A-Za-z0-9_]+)\\b",
    ),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "shell": [
    ("comment", "#[^\\n]*"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:abstract|assert|async|await|as|break|case|catch|class|const|continue|debugger|default|defer|delete|do|else|enum|export|extends|false|final|finally|for|from|func|function|guard|if|implements|import|in|instanceof|interface|internal|is|let|new|nil|null|of|open|override|package|private|protected|public|readonly|record|return|self|static|struct|super|switch|synchronized|this|throw|throws|true|try|type|typeof|var|void|while|yield|def|elif|except|lambda|None|True|False|not|and|or|pass|with|raise|print|echo|namespace|use|include|require|require_once|include_once|foreach|endforeach|endif|isset|empty|fn|pub|impl|match|mut|trait|where|unsafe|mod|crate|go|range|select|chan|map|select|SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|ON|GROUP|BY|ORDER|LIMIT|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|AS|AND|OR|NOT|NULL|IS|DISTINCT|UNION)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b"),
    (
      "type",
      "\\b(?:String|Int|Integer|Boolean|Double|Float|Array|List|Map|Set|Optional|Object|bool|boolean|int|long|float|double|char|byte|short|[A-Z][A-Za-z0-9_]+)\\b",
    ),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
    ("property", "\\\$[a-zA-Z_][\\w]*"),
  ],
  "c": [
    ("comment", "//[^\\n]*|/\\*[\\s\\S]*?\\*/"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:abstract|assert|async|await|as|break|case|catch|class|const|continue|debugger|default|defer|delete|do|else|enum|export|extends|false|final|finally|for|from|func|function|guard|if|implements|import|in|instanceof|interface|internal|is|let|new|nil|null|of|open|override|package|private|protected|public|readonly|record|return|self|static|struct|super|switch|synchronized|this|throw|throws|true|try|type|typeof|var|void|while|yield|def|elif|except|lambda|None|True|False|not|and|or|pass|with|raise|print|echo|namespace|use|include|require|require_once|include_once|foreach|endforeach|endif|isset|empty|fn|pub|impl|match|mut|trait|where|unsafe|mod|crate|go|range|select|chan|map|select|SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|ON|GROUP|BY|ORDER|LIMIT|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|AS|AND|OR|NOT|NULL|IS|DISTINCT|UNION)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b"),
    (
      "type",
      "\\b(?:String|Int|Integer|Boolean|Double|Float|Array|List|Map|Set|Optional|Object|bool|boolean|int|long|float|double|char|byte|short|[A-Z][A-Za-z0-9_]+)\\b",
    ),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "rust": [
    ("comment", "//[^\\n]*|/\\*[\\s\\S]*?\\*/"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:abstract|assert|async|await|as|break|case|catch|class|const|continue|debugger|default|defer|delete|do|else|enum|export|extends|false|final|finally|for|from|func|function|guard|if|implements|import|in|instanceof|interface|internal|is|let|new|nil|null|of|open|override|package|private|protected|public|readonly|record|return|self|static|struct|super|switch|synchronized|this|throw|throws|true|try|type|typeof|var|void|while|yield|def|elif|except|lambda|None|True|False|not|and|or|pass|with|raise|print|echo|namespace|use|include|require|require_once|include_once|foreach|endforeach|endif|isset|empty|fn|pub|impl|match|mut|trait|where|unsafe|mod|crate|go|range|select|chan|map|select|SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|ON|GROUP|BY|ORDER|LIMIT|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|AS|AND|OR|NOT|NULL|IS|DISTINCT|UNION)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b"),
    (
      "type",
      "\\b(?:String|Int|Integer|Boolean|Double|Float|Array|List|Map|Set|Optional|Object|bool|boolean|int|long|float|double|char|byte|short|[A-Z][A-Za-z0-9_]+)\\b",
    ),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "go": [
    ("comment", "//[^\\n]*|/\\*[\\s\\S]*?\\*/"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:abstract|assert|async|await|as|break|case|catch|class|const|continue|debugger|default|defer|delete|do|else|enum|export|extends|false|final|finally|for|from|func|function|guard|if|implements|import|in|instanceof|interface|internal|is|let|new|nil|null|of|open|override|package|private|protected|public|readonly|record|return|self|static|struct|super|switch|synchronized|this|throw|throws|true|try|type|typeof|var|void|while|yield|def|elif|except|lambda|None|True|False|not|and|or|pass|with|raise|print|echo|namespace|use|include|require|require_once|include_once|foreach|endforeach|endif|isset|empty|fn|pub|impl|match|mut|trait|where|unsafe|mod|crate|go|range|select|chan|map|select|SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|ON|GROUP|BY|ORDER|LIMIT|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|AS|AND|OR|NOT|NULL|IS|DISTINCT|UNION)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b"),
    (
      "type",
      "\\b(?:String|Int|Integer|Boolean|Double|Float|Array|List|Map|Set|Optional|Object|bool|boolean|int|long|float|double|char|byte|short|[A-Z][A-Za-z0-9_]+)\\b",
    ),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "css": [
    ("comment", "/\\*[\\s\\S]*?\\*/"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "number",
      "#[0-9a-fA-F]{3,8}\\b|\\b\\d+(?:\\.\\d+)?(?:px|em|rem|vh|vw|s|ms|%)?",
    ),
    ("property", "[\\w-]+(?=\\s*:)"),
    ("tag", "[.#][a-zA-Z_][\\w-]*|@[\\w-]+"),
    (
      "keyword",
      "\\b(?:abstract|assert|async|await|as|break|case|catch|class|const|continue|debugger|default|defer|delete|do|else|enum|export|extends|false|final|finally|for|from|func|function|guard|if|implements|import|in|instanceof|interface|internal|is|let|new|nil|null|of|open|override|package|private|protected|public|readonly|record|return|self|static|struct|super|switch|synchronized|this|throw|throws|true|try|type|typeof|var|void|while|yield|def|elif|except|lambda|None|True|False|not|and|or|pass|with|raise|print|echo|namespace|use|include|require|require_once|include_once|foreach|endforeach|endif|isset|empty|fn|pub|impl|match|mut|trait|where|unsafe|mod|crate|go|range|select|chan|map|select|SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|ON|GROUP|BY|ORDER|LIMIT|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|AS|AND|OR|NOT|NULL|IS|DISTINCT|UNION)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b"),
    (
      "type",
      "\\b(?:String|Int|Integer|Boolean|Double|Float|Array|List|Map|Set|Optional|Object|bool|boolean|int|long|float|double|char|byte|short|[A-Z][A-Za-z0-9_]+)\\b",
    ),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
};
final _grammars = <String, RegExp>{};
Iterable<(int, int, String)> syntaxTokens(String text, String language) sync* {
  if (language == 'html') {
    final embedded = RegExp(
      r'(<script\b[^>]*>)([\s\S]*?)(</script\s*>)|(<style\b[^>]*>)([\s\S]*?)(</style\s*>)|(<\?php\b)([\s\S]*?)(\?>)',
      caseSensitive: false,
    );
    var offset = 0;
    for (final block in embedded.allMatches(text)) {
      final group = block.group(1) != null
          ? 1
          : block.group(4) != null
          ? 4
          : 7;
      final start = block.start + block.group(group)!.length;
      final end = start + block.group(group + 1)!.length;
      for (final token in _lexicalTokens(
        text.substring(offset, start),
        'html',
      )) {
        yield (token.$1 + offset, token.$2 + offset, token.$3);
      }
      for (final token in _lexicalTokens(
        text.substring(start, end),
        group == 1
            ? 'javascript'
            : group == 4
            ? 'css'
            : 'php',
      )) {
        yield (token.$1 + start, token.$2 + start, token.$3);
      }
      offset = end;
    }
    for (final token in _lexicalTokens(text.substring(offset), 'html')) {
      yield (token.$1 + offset, token.$2 + offset, token.$3);
    }
    return;
  }
  yield* _lexicalTokens(text, language);
}

Iterable<(int, int, String)> _lexicalTokens(
  String text,
  String language,
) sync* {
  final rules = syntaxRules[language] ?? additionalSyntaxRules[language];
  if (rules == null || text.length > 250000) return;
  final regex = _grammars.putIfAbsent(
    language,
    () => RegExp(
      List.generate(rules.length, (i) => '(?<t$i>${rules[i].$2})').join('|'),
      multiLine: true,
    ),
  );
  for (final match in regex.allMatches(text)) {
    for (var i = 0; i < rules.length; i++) {
      if (match.namedGroup('t$i') != null) {
        yield (match.start, match.end, rules[i].$1);
        break;
      }
    }
  }
}

final additionalSyntaxRules = <String, List<(String, String)>>{
  "dart": [
    ("comment", "//[^\\n]*|/\\*[\\s\\S]*?\\*/"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|\\'(?:\\\\.|[^\\'\\\\])*\\'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:abstract|as|assert|async|await|base|break|case|catch|class|const|continue|covariant|default|deferred|do|dynamic|else|enum|export|extends|extension|external|factory|false|final|finally|for|Function|get|hide|if|implements|import|in|interface|is|late|library|mixin|new|null|on|operator|part|required|rethrow|return|sealed|set|show|static|super|switch|sync|this|throw|true|try|typedef|var|void|when|while|with|yield|String|int|double|bool|List|Map|Set|Future|Stream|Widget|BuildContext)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?)\\b"),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "ruby": [
    ("comment", "#[^\\n]*"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|\\'(?:\\\\.|[^\\'\\\\])*\\'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:alias|and|begin|break|case|class|def|defined|do|else|elsif|end|ensure|false|for|if|in|module|next|nil|not|or|redo|rescue|retry|return|self|super|then|true|undef|unless|until|when|while|yield|require|puts|attr_reader|attr_accessor)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?)\\b"),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "lua": [
    ("comment", "--\\[\\[[\\s\\S]*?\\]\\]|--[^\\n]*"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|\\'(?:\\\\.|[^\\'\\\\])*\\'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:and|break|do|else|elseif|end|false|for|function|goto|if|in|local|nil|not|or|repeat|return|then|true|until|while|pairs|ipairs|print|require)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?)\\b"),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "r": [
    ("comment", "#[^\\n]*"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|\\'(?:\\\\.|[^\\'\\\\])*\\'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:if|else|repeat|while|function|for|in|next|break|TRUE|FALSE|NULL|NA|Inf|NaN|library|data.frame|list|c|print|return)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?)\\b"),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "powershell": [
    ("comment", "#[^\\n]*"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|\\'(?:\\\\.|[^\\'\\\\])*\\'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:function|param|begin|process|end|if|elseif|else|switch|for|foreach|while|do|until|try|catch|finally|throw|return|break|continue|filter|class|enum|using|Write-Host|Get-Content|Set-Content|Where-Object|ForEach-Object)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?)\\b"),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "dockerfile": [
    ("comment", "#[^\\n]*"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|\\'(?:\\\\.|[^\\'\\\\])*\\'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:FROM|RUN|CMD|LABEL|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL|AS)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?)\\b"),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "makefile": [
    ("comment", "#[^\\n]*"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|\\'(?:\\\\.|[^\\'\\\\])*\\'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:include|ifdef|ifndef|ifeq|ifneq|else|endif|define|endef|override|export|unexport|private|vpath)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?)\\b"),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "cmake": [
    ("comment", "#[^\\n]*"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|\\'(?:\\\\.|[^\\'\\\\])*\\'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:cmake_minimum_required|project|set|option|add_executable|add_library|target_link_libraries|target_include_directories|find_package|if|elseif|else|endif|foreach|endforeach|function|endfunction|include|message)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?)\\b"),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "kotlin": [
    ("comment", "//[^\\n]*|/\\*[\\s\\S]*?\\*/"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|\\'(?:\\\\.|[^\\'\\\\])*\\'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:fun|val|var|class|object|data|sealed|interface|companion|suspend|override|open|private|public|internal|protected|return|when|is|as|in|null|true|false|if|else|for|while|try|catch|finally|throw|package|import|String|Int|Boolean|Unit|List|Map)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?)\\b"),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "csharp": [
    ("comment", "//[^\\n]*|/\\*[\\s\\S]*?\\*/"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|\\'(?:\\\\.|[^\\'\\\\])*\\'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:using|namespace|class|struct|record|interface|enum|public|private|protected|internal|static|readonly|const|async|await|void|var|string|int|bool|double|decimal|return|new|this|base|null|true|false|if|else|switch|case|for|foreach|while|try|catch|finally|throw|get|set|init|required)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?)\\b"),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "cpp": [
    ("comment", "//[^\\n]*|/\\*[\\s\\S]*?\\*/"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|\\'(?:\\\\.|[^\\'\\\\])*\\'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:namespace|using|template|typename|constexpr|consteval|auto|class|struct|public|private|protected|virtual|override|final|const|static|void|int|char|bool|double|return|new|delete|nullptr|true|false|if|else|for|while|switch|case|include|std|vector|string|unique_ptr|shared_ptr)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?)\\b"),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
  "graphql": [
    ("comment", "//[^\\n]*|/\\*[\\s\\S]*?\\*/"),
    (
      "string",
      "\"(?:\\\\.|[^\"\\\\])*\"|\\'(?:\\\\.|[^\\'\\\\])*\\'|`(?:\\\\.|[^`\\\\])*`",
    ),
    (
      "keyword",
      "\\b(?:query|mutation|subscription|fragment|on|schema|type|input|enum|scalar|interface|union|implements|extend|directive|true|false|null|String|Int|Float|Boolean|ID)\\b",
    ),
    ("number", "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?)\\b"),
    ("function", "\\b[a-zA-Z_][\\w]*(?=\\s*\\()"),
  ],
};
