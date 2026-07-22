# Harmony Sass

**Harmony Sass** is a HarmonyOS PC Sass editor that runs the official
[Dart Sass](https://github.com/sass/dart-sass) implementation locally.

The application keeps the original ArkTS two-pane editor layout. Sass language
behavior is provided by the official Dart Sass JavaScript distribution rather
than a rewritten or reduced compiler.

## Current implementation

- Native HarmonyOS ArkTS two-pane editor UI
- Official Dart Sass `1.101.3` compiler
- Page-lifecycle reuse of the official `sass.Compiler` and
  `sass.AsyncCompiler`
- Editor and batch compilation through official
  `AsyncCompiler.compileStringAsync()`, with the synchronous bridge retained
  for compatibility
- Explicit release of abandoned asynchronous bridge jobs after timeout or
  page exit, while allowing the official compiler to finish its own active
  evaluation lifecycle
- Runtime identity and structured compiler-version validation through official
  `sass.info` and `sass.Version`
- Complete official Dart Sass deprecation metadata, including nullable
  structured release versions, available through the runtime bridge
- Full Dart Sass language behavior, including modules, mixins, functions,
  control flow, arithmetic, at-rules and built-in `sass:*` modules
- Multi-file virtual projects with up to 500 selected stylesheets and package
  manifests
- Mixed file and folder selection with recursive Sass/CSS and `package.json`
  discovery
- Relative `@use`, `@forward` and legacy `@import`
- Official-compatible file resolution for Sass files, CSS fallbacks, partials,
  directory `_index` files and import-only `.import.scss` files
- Configurable virtual load paths
- Virtual-project `NodePackageImporter` support for `pkg:` URLs, nearest
  `node_modules`, scoped and percent-encoded package paths, package exports
  and nested dependencies
- SCSS, indented Sass and CSS input syntax
- Expanded and compressed CSS output
- Optional Source Map generation with embedded sources
- External or embedded Source Maps with or without embedded sources
- Official Source Map option defaults for direct runtime API callers
- Official CLI-compatible CSS/Source Map file association, target file names,
  URI encoding and expanded/compressed export formatting
- Relative and absolute Source Map source URLs, embedded Source Map data URIs
  and cross-directory CSS-to-map links
- Real HarmonyOS document URIs in loaded URLs, errors and Source Maps
- Source file open, save and save-as
- CSS copy and export, paired CSS/Source Map export, plus standalone Source Map
  export
- Manual or debounced automatic compilation
- Automatic reload and recompilation when authorized source files change
  outside the app, with conflict protection for unsaved edits
- Save-all behavior for modified files in a loaded project
- Structured errors, warnings, complete deprecation metadata, full source-span
  context, warning and error Sass stacks, JavaScript runtime stack traces and
  `@debug` messages
- Official quiet logging, Error CSS and batch stop-on-error behavior
- Fatal deprecations selected by either deprecation ID or Dart Sass version
- Official errors for unsupported input syntax, output style and invalid
  deprecation option values without application-side correction
- Official `quietDeps` classification for relative files, virtual load paths
  and package dependencies
- Runtime batch compilation for multiple project entry stylesheets
- Session restoration for authorized project files, active file, per-file
  syntax and compiler options
- PC shortcuts: `Ctrl+O`, `Ctrl+S`, `Ctrl+Shift+S` and `Ctrl+Enter`
- No network service and no remote compilation

## Project workflow

Use **打开** for a single entry file. Use **添加项目文件** to select the entry,
partials and dependencies together. Harmony Sass derives relative virtual paths
from the selected file URIs and lets any loaded file become the compilation
entry from the file selector.

All project files are passed to in-memory Dart Sass importers. The official
compiler therefore resolves project imports without uploading source code or
requiring unrestricted filesystem access from ArkWeb. Loaded `package.json`
files participate in `pkg:` resolution but remain hidden from the stylesheet
entry selector.

An untouched built-in example is removed automatically when a real project is
loaded. Edited untitled content is retained. Project selections are
deduplicated and limited to 500 project files across all selected files and
folders.

## Upstream source

- Dart Sass implementation:
  [sass/dart-sass](https://github.com/sass/dart-sass)
- Pinned `NodePackageImporter` source:
  [dart-sass 1.101.3 node_package.dart](https://github.com/sass/dart-sass/blob/1.101.3/lib/src/importer/node_package.dart)
- Sass language specification:
  [sass/sass](https://github.com/sass/sass)

The generated runtime in `entry/src/main/resources/rawfile` is built from the
official `sass` npm distribution. Version and build dependencies are pinned in
`tools/package.json`. Changes in this repository are published only to
`huihui200739/harmony-sass`; the upstream Dart Sass repository is not modified.

## Build

### Prerequisites

- DevEco Studio with HarmonyOS **6.1.1 (API 24)** SDK
- The Java runtime bundled with DevEco Studio
- Node.js **20.19 or newer** to regenerate and test the Dart Sass runtime

On macOS, run:

```bash
bash ./scripts/verify.sh
```

The script:

1. installs the pinned runtime build dependencies;
2. rebuilds and tests the bundled Dart Sass runtime;
3. installs HarmonyOS package dependencies;
4. runs the ArkTS tests;
5. creates an unsigned HAP.

The expected package path is:

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

The HAP is unsigned for development. A release build requires your own signing
configuration and HarmonyOS release credentials.

## Runtime verification

The compatibility suite compares the bundled browser runtime with the same
pinned official Dart Sass package:

```bash
npm --prefix tools ci
npm --prefix tools run verify
```

Fixtures cover single-document Sass behavior and project workflows including
partials, modules, forwarding, legacy imports, output styles, input syntaxes,
Source Maps, loaded URLs, batch entries, debug messages, deprecation controls,
fatal deprecation versions, dependency warning classification, warnings and
structured errors. Diagnostic fixtures compare complete source-span context
and per-warning deprecation metadata. The suite also compares official
synchronous and asynchronous compiler results, loaded URLs and asynchronous
batch stop-on-error behavior. Compiler-option fixtures compare `charset`,
`alertAscii`, `alertColor`, `verbose`, `fatalDeprecations`,
`futureDeprecations` and `silenceDeprecations` through both compiler modes.
They preserve whitespace and empty invalid option values, and compare official
errors for unsupported syntax and output style. They also verify explicit
release of abandoned ArkWeb jobs. File-export
fixtures compare complete expanded and compressed CSS output, Source Map
target names and URI-encoded output names with the official CLI. They also
compare Error CSS, relative and absolute Source Map URLs, embedded Source Map
data URIs, omitted embedded sources and compressed embedded maps
byte-for-byte. Runtime checks also compare `sass.info`, structured compiler
versions and the complete nullable deprecation metadata table with the pinned
official package. Importer fixtures
also compare file-versus-index precedence, Sass-versus-CSS precedence,
explicit extensions, ambiguity handling, package exports, package conditions,
condition and array fallbacks, overlapping wildcard precedence, nested
dependencies, percent-encoded package paths, path normalization and package
error boundaries with the pinned official package.

## Runtime boundaries

Harmony Sass reproduces Dart Sass language compilation and the editor workflows
that can be implemented faithfully in an offline HarmonyOS application. The
following host integration APIs are not exposed because ArkWeb's JSON bridge
cannot transfer JavaScript callback objects or provide a Node.js process:

- host-defined JavaScript custom functions passed through `Options.functions`;
- arbitrary JavaScript `Importer` and `FileImporter` callbacks;
- arbitrary host `Logger` callbacks; warnings and debug messages are returned
  as structured compilation results instead;
- unrestricted filesystem-backed `NodePackageImporter` access outside files
  loaded into the virtual HarmonyOS project;
- the Dart Sass Embedded Protocol;
- the complete command-line process contract, including stdin/stdout, directory
  mappings, every CLI flag, CLI watch mode and `--update` target/dependency
  timestamp graph;
- filesystem file-entry npm APIs (`compile()` and `compileAsync()`),
  JavaScript value/callback object APIs and the legacy JavaScript API surface.

Sass functions declared with `@function`, built-in functions and all built-in
`sass:*` modules are supported by the official compiler.

The official browser distribution itself throws a Node.js-only error for
legacy `render()` and `renderSync()`, including their `data` string mode.
Harmony Sass therefore does not present a different implementation under
those API names.

The application watches authorized project files and automatically recompiles
when they change. This provides the native editor workflow, but it is not
presented as the CLI `--update` contract because the CLI also compares output
timestamps and transitive filesystem dependencies across a process-managed
stylesheet graph.

Recursive folder selection depends on HarmonyOS document-provider behavior.
It builds and is covered by project-model tests, but still requires validation
on the target HarmonyOS PC and document provider.

## Licensing

Harmony Sass is licensed under [MIT](LICENSE). The bundled Dart Sass
distribution and its dependency notices are included alongside the runtime in
`entry/src/main/resources/rawfile`.
