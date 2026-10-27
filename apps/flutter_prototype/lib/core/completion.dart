// Vocabulary, snippets and extension mapping ported from the native app.
import 'package:path/path.dart' as p;

String sourceLanguage(String path) {
  final name = p.basename(path).toLowerCase();
  if (name == 'dockerfile' || name.startsWith('dockerfile.')) {
    return 'dockerfile';
  }
  if (name == 'makefile' || name == 'gnumakefile') return 'makefile';
  if (name == '.env' ||
      name.startsWith('.env.') ||
      name == '.gitignore' ||
      name == '.gitattributes') {
    return 'yaml';
  }
  if (name == 'cmakelists.txt') return 'cmake';
  if (name == 'gemfile' || name == 'rakefile') return 'ruby';
  return extensions[p.extension(path).replaceFirst('.', '').toLowerCase()] ??
      'plain';
}

const extensions = <String, String>{
  "dart": "dart",
  "rb": "ruby",
  "rake": "ruby",
  "gemspec": "ruby",
  "lua": "lua",
  "r": "r",
  "rscript": "r",
  "ps1": "powershell",
  "psm1": "powershell",
  "psd1": "powershell",
  "cmake": "cmake",
  "mk": "makefile",
  "graphql": "graphql",
  "gql": "graphql",
  "cc": "cpp",
  "cxx": "cpp",
  "hh": "cpp",
  "hxx": "cpp",
  "c++": "cpp",
  "pyw": "python",
  "pyi": "python",
  "mts": "typescript",
  "cts": "typescript",
  "bashrc": "shell",
  "zshrc": "shell",
  "fish": "shell",
  "conf": "yaml",
  "properties": "yaml",

  "java": "java",
  "kt": "kotlin",
  "kts": "kotlin",
  "php": "php",
  "phtml": "php",
  "html": "html",
  "htm": "html",
  "xml": "html",
  "svg": "html",
  "vue": "html",
  "svelte": "html",
  "css": "css",
  "scss": "css",
  "sass": "css",
  "less": "css",
  "json": "json",
  "jsonc": "json",
  "md": "markdown",
  "markdown": "markdown",
  "mdx": "markdown",
  "js": "javascript",
  "jsx": "javascript",
  "mjs": "javascript",
  "cjs": "javascript",
  "ts": "typescript",
  "tsx": "typescript",
  "swift": "swift",
  "py": "python",
  "yaml": "yaml",
  "yml": "yaml",
  "toml": "yaml",
  "ini": "yaml",
  "env": "yaml",
  "sql": "sql",
  "sh": "shell",
  "bash": "shell",
  "zsh": "shell",
  "c": "c",
  "h": "c",
  "cpp": "cpp",
  "hpp": "cpp",
  "cs": "csharp",
  "rs": "rust",
  "go": "go",
};
const vocabularies = <String, String>{
  "dart": "abstract as assert async await base break case catch class const continue covariant default deferred do dynamic else enum export extends extension external factory false final finally for Function get hide if implements import in interface is late library mixin new null on operator part required rethrow return sealed set show static super switch sync this throw true try typedef var void when while with yield String int double bool List Map Set Future Stream Widget BuildContext",
  "ruby": "alias and begin break case class def defined do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield require puts attr_reader attr_accessor",
  "lua": "and break do else elseif end false for function goto if in local nil not or repeat return then true until while pairs ipairs print require",
  "r": "if else repeat while function for in next break TRUE FALSE NULL NA Inf NaN library data.frame list c print return",
  "powershell": "function param begin process end if elseif else switch for foreach while do until try catch finally throw return break continue filter class enum using Write-Host Get-Content Set-Content Where-Object ForEach-Object",
  "dockerfile": "FROM RUN CMD LABEL EXPOSE ENV ADD COPY ENTRYPOINT VOLUME USER WORKDIR ARG ONBUILD STOPSIGNAL HEALTHCHECK SHELL AS",
  "makefile": "include ifdef ifndef ifeq ifneq else endif define endef override export unexport private vpath",
  "cmake": "cmake_minimum_required project set option add_executable add_library target_link_libraries target_include_directories find_package if elseif else endif foreach endforeach function endfunction include message",
  "kotlin": "fun val var class object data sealed interface companion suspend override open private public internal protected return when is as in null true false if else for while try catch finally throw package import String Int Boolean Unit List Map",
  "csharp": "using namespace class struct record interface enum public private protected internal static readonly const async await void var string int bool double decimal return new this base null true false if else switch case for foreach while try catch finally throw get set init required",
  "cpp": "namespace using template typename constexpr consteval auto class struct public private protected virtual override final const static void int char bool double return new delete nullptr true false if else for while switch case include std vector string unique_ptr shared_ptr",
  "graphql": "query mutation subscription fragment on schema type input enum scalar interface union implements extend directive true false null String Int Float Boolean ID",

  "java": "public private protected static final abstract class interface extends implements package import return new this super void int long boolean String List Map if else for while switch try catch finally throw throws null true false",
  "php": "function public private protected static class interface namespace use require require_once include include_once return echo foreach array isset empty count null true false if else elseif while try catch throw new",
  "html": "div span main section article header footer nav button input label form textarea select option ul li table tr td img link script style class id href src type placeholder disabled",
  "css": "display position width height margin padding color background background-color font-size font-weight border border-radius flex grid gap align-items justify-content overflow opacity transform transition relative absolute none block",
  "json": "true false null",
  "markdown": "",
  "javascript": "const let var function return async await class extends import export default from new this null undefined true false if else for while switch try catch finally throw console document window interface type readonly implements",
  "typescript": "const let var function return async await class extends import export default from new this null undefined true false if else for while switch try catch finally throw console document window interface type readonly implements",
  "swift": "let var func struct class enum protocol extension public private static return guard if else for in switch case import async await throws try self nil true false",
  "python": "def class import from return if elif else for while in with as try except finally raise pass break continue lambda True False None async await print",
  "yaml": "true false null",
  "sql": "SELECT FROM WHERE JOIN LEFT RIGHT INNER ON GROUP BY ORDER LIMIT INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE ALTER DROP DISTINCT NULL",
  "shell": "if then else elif fi for do done while case esac function echo export source return exit",
  "c": "int char void bool float double class struct public private return include static const if else for while switch case break null nullptr",
  "rust": "fn let mut pub struct enum impl trait use mod crate match if else for while return async await self Self Option Result",
  "go": "func package import type struct interface var const return if else for range switch case defer go chan map nil",
  "plain": "",
  "diff": "",
};
const snippets = <String, List<(String, String)>>{
  "java": [
    ("main", "public static void main(String[] args) {\n    \${cursor}\n}"),
    ("sout", "System.out.println(\${cursor});"),
    ("if", "if (\${cursor}) {\n    \n}"),
  ],
  "php": [
    ("function", "function name(\${cursor}) {\n    \n}"),
    ("foreach", "foreach (\${cursor} as \$item) {\n    \n}"),
  ],
  "javascript": [
    ("function", "function name(\${cursor}) {\n    \n}"),
    ("log", "console.log(\${cursor});"),
    ("if", "if (\${cursor}) {\n    \n}"),
  ],
  "typescript": [
    ("function", "function name(\${cursor}) {\n    \n}"),
    ("log", "console.log(\${cursor});"),
    ("if", "if (\${cursor}) {\n    \n}"),
  ],
  "html": [
    ("div", "<div>\${cursor}</div>"),
    ("span", "<span>\${cursor}</span>"),
    ("button", "<button>\${cursor}</button>"),
  ],
  "css": [
    ("flex", "display: flex;\n\${cursor}"),
    ("grid", "display: grid;\n\${cursor}"),
  ],
  "markdown": [
    ("link", "[\${cursor}](https://)"),
    ("image", "![\${cursor}](path)"),
    ("code", "```\n\${cursor}\n```"),
  ],
  "python": [
    ("def", "def name(\${cursor}):\n    pass"),
    ("if", "if \${cursor}:\n    pass"),
  ],
  "swift": [("func", "func name(\${cursor}) {\n    \n}")],
  "go": [("func", "func name(\${cursor}) {\n    \n}")],
  "rust": [("fn", "fn name(\${cursor}) {\n    \n}")],
};

List<(String, String)> completeCode(
  String text,
  String prefix,
  String language,
) {
  final words =
      text.length > 250000
            ? <String>[]
            : RegExp(r'[A-Za-z_$][A-Za-z0-9_$]{2,63}')
                  .allMatches(text)
                  .take(3000)
                  .map((m) => m[0]!)
                  .toSet()
                  .toList()
        ..sort();
  final seen = <String>{};
  return [
        ...?snippets[language],
        ...(vocabularies[language] ?? '')
            .split(' ')
            .where((s) => s.isNotEmpty)
            .map((s) => (s, s)),
        ...words.map((s) => (s, s)),
      ]
      .where(
        (s) =>
            s.$1.toLowerCase().startsWith(prefix.toLowerCase()) &&
            s.$2 != prefix &&
            seen.add(s.$1),
      )
      .take(8)
      .toList();
}

(String, int) insertSnippet(String text, String indent) {
  final insertion = text.replaceAll('\n', '\n$indent');
  final cursor = insertion.indexOf(r'${cursor}');
  final result = insertion.replaceAll(r'${cursor}', '');
  return (result, cursor < 0 ? result.length : cursor);
}
