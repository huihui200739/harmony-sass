# Harmony Sass

**Harmony Sass** is a HarmonyOS PC Sass editor that runs the official
[Dart Sass](https://github.com/sass/dart-sass) implementation locally.

The application keeps the original ArkTS two-pane editor layout. Sass language
behavior is provided by the official Dart Sass JavaScript distribution rather
than a rewritten or reduced compiler.

## Current implementation

- Native HarmonyOS ArkTS two-pane editor UI
- Official Dart Sass `1.101.3` compiler
- Full Dart Sass language behavior, including modules, mixins, functions,
  control flow, arithmetic, at-rules and built-in `sass:*` modules
- Multi-file virtual projects with up to 500 selected `.scss`, `.sass` or
  `.css` files
- Mixed file and folder selection with recursive Sass/CSS discovery
- Relative `@use`, `@forward` and legacy `@import`
- Official-compatible file resolution for Sass files, CSS fallbacks, partials,
  directory `_index` files and import-only `.import.scss` files
- Configurable virtual load paths
- SCSS, indented Sass and CSS input syntax
- Expanded and compressed CSS output
- Optional Source Map generation with embedded sources
- Source file open, save and save-as
- CSS copy and export, plus Source Map export
- Manual or debounced automatic compilation
- Automatic reload and recompilation when authorized source files change
  outside the app, with conflict protection for unsaved edits
- Save-all behavior for modified files in a loaded project
- Structured errors, warnings, deprecation IDs, Sass stacks and `@debug`
  messages
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

All project files are passed to an in-memory Dart Sass importer. The official
compiler therefore resolves project imports without uploading source code or
requiring filesystem access from ArkWeb.

An untouched built-in example is removed automatically when a real project is
loaded. Edited untitled content is retained. Project selections are
deduplicated and limited to 500 Sass/CSS files across all selected files and
folders.

## Upstream source

- Dart Sass implementation:
  [sass/dart-sass](https://github.com/sass/dart-sass)
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
warnings and structured errors. Importer fixtures also compare file-versus-index
precedence, Sass-versus-CSS precedence, explicit extensions and ambiguity
handling with the pinned official package.

## Runtime boundaries

Harmony Sass reproduces Dart Sass language compilation and the editor workflows
that can be implemented faithfully in an offline HarmonyOS application. The
following host integration APIs are not exposed because ArkWeb's JSON bridge
cannot transfer JavaScript callback objects or provide a Node.js process and
filesystem:

- host-defined JavaScript custom functions passed through `Options.functions`;
- arbitrary JavaScript `Importer` and `FileImporter` callbacks;
- `NodePackageImporter`, `pkg:` URLs, `node_modules` lookup and package exports;
- the Dart Sass Embedded Protocol;
- the complete command-line process contract, including stdin/stdout, directory
  mappings, every CLI flag and CLI watch mode.

Sass functions declared with `@function`, built-in functions and all built-in
`sass:*` modules are supported by the official compiler.

Recursive folder selection depends on HarmonyOS document-provider behavior.
It builds and is covered by project-model tests, but still requires validation
on the target HarmonyOS PC and document provider.

## Licensing

Harmony Sass is licensed under [MIT](LICENSE). The bundled Dart Sass
distribution and its dependency notices are included alongside the runtime in
`entry/src/main/resources/rawfile`.
