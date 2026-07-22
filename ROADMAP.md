# Roadmap

## Completed through 0.12.0

- Official Dart Sass runtime integration
- Official Dart Sass `1.101.3` language behavior
- Official `sass.Compiler` and `sass.AsyncCompiler` reuse for the ArkWeb page
  lifecycle
- Official asynchronous editor and batch compilation through
  `AsyncCompiler.compileStringAsync()`, with a compatible synchronous bridge
- Explicit cleanup of abandoned asynchronous bridge jobs on timeout and page
  exit
- Official sync/async option comparisons for charset output, ASCII/color
  diagnostics, verbose warnings and all three deprecation option lists
- Official `sass.info` runtime validation and complete deprecation metadata
  bridging
- Multi-file virtual project compilation
- Sass module, forwarding, partial, index, CSS fallback and legacy import
  resolution with official-compatible precedence
- SCSS, indented Sass and CSS input
- Expanded and compressed output
- Source Maps with official defaults, warnings, loaded URLs and full error
  spans
- Real HarmonyOS document URIs in entry/import diagnostics, loaded URLs and
  Source Maps
- Official CLI-compatible paired CSS/Source Map file export, including the
  Source Map `file` field, `sourceMappingURL`, output-style whitespace and URI
  encoding
- Relative and absolute Source Map URLs, embedded Source Maps and
  cross-directory CSS-to-map links
- Official CLI comparisons for Source Maps with and without embedded sources,
  including compressed embedded maps
- Deprecation controls by ID or compiler version, deprecation IDs, warning and
  error Sass stacks, official `quietDeps` behavior, JavaScript runtime stack
  traces and `@debug` messages
- Official `quiet`, Error CSS and batch `stopOnError` behavior
- Multiple-entry batch compilation
- HarmonyOS PC open, save, export, copy and keyboard workflows
- Save-all for modified project files
- Automatic compilation, external file reloading and entry-file switching
- Recursive folder project loading with deduplication and a global 500-file
  limit
- Session restoration for project files, active file, per-file syntax and
  compiler options
- Automatic removal of the untouched built-in example when loading a project
- Virtual-project `NodePackageImporter` with `pkg:`, nearest `node_modules`,
  scoped packages, package exports, nested dependencies and import-only files
- Official partial-first ambiguity diagnostics and encoded document file names

## Platform validation and release work

- Validate recursive document-provider URIs on target HarmonyOS PC hardware
- Signed release packages and automated release publishing

## Environment boundaries

These upstream host APIs cannot be reproduced faithfully without Node.js
callbacks, unrestricted host filesystem access, a child process or the
Embedded Protocol:

- JavaScript `Options.functions`
- external JavaScript `Importer` and `FileImporter` callbacks
- external JavaScript `Logger` callback objects
- filesystem-backed `NodePackageImporter` outside the loaded virtual project
- Dart Sass Embedded Protocol
- the complete Dart Sass CLI process, CLI watch contract and `--update`
  target/dependency timestamp graph
- filesystem file-entry npm APIs (`compile()` and `compileAsync()`),
  JavaScript callback/value object APIs and the legacy JavaScript API surface

The official browser build rejects legacy `render()` and `renderSync()` even
when `data` is provided, so these remain an upstream Node.js boundary.
