# Compatibility Status

## Implemented

- [x] Native HarmonyOS PC two-pane editor UI
- [x] Official Dart Sass `1.101.3` browser runtime
- [x] Official `sass.Compiler` and `sass.AsyncCompiler` reuse for the ArkWeb
      page lifecycle
- [x] Official `AsyncCompiler.compileStringAsync()` editor and batch workflows
      with a compatible synchronous runtime bridge
- [x] Explicit release of abandoned asynchronous bridge jobs on timeout and
      page exit
- [x] Official `sass.info` validation and complete deprecation metadata bridge
- [x] SCSS, indented Sass and CSS input
- [x] Complete Sass language semantics supplied by Dart Sass
- [x] Built-in `sass:*` modules and Sass-authored `@function`
- [x] Expanded and compressed CSS
- [x] Source Maps with official API defaults and optional embedded sources
- [x] Official CLI-compatible paired CSS and Source Map file export
- [x] Relative/absolute Source Map source URLs and embedded Source Map data URIs
- [x] Official CLI Source Map comparisons with and without embedded sources
- [x] Real HarmonyOS document URIs in loaded URLs, diagnostics and Source Maps
- [x] Virtual multi-file projects and load paths
- [x] Relative `@use`, `@forward` and legacy `@import`
- [x] Partials, directory indexes, import-only files and ambiguity errors
- [x] Official partial-first ambiguity diagnostics
- [x] Official-compatible direct/index and Sass/CSS resolution precedence
- [x] Structured errors, warnings, deprecation IDs, warning/error Sass stacks,
      JavaScript runtime stack traces and `@debug`
- [x] Fatal deprecations by ID or Dart Sass version
- [x] Sync/async parity checks for charset output, ASCII/color diagnostics,
      verbose warnings and deprecation option validation
- [x] Official `quietDeps` behavior for relative and load-path stylesheets
- [x] Virtual-project `NodePackageImporter`, `pkg:` URLs, nearest
      `node_modules`, package exports and nested package dependencies
- [x] Multiple-entry batch CSS and Source Map export
- [x] Official `quiet`, Error CSS and batch `stopOnError` behavior
- [x] Open, save, save-as, save-all, copy and keyboard workflows
- [x] URI-safe document-provider file names containing encoded `#` or `?`
- [x] Automatic compilation and authorized external-file reload
- [x] Recursive folder discovery with deduplication and a 500-file limit
- [x] Project and compiler-option session restoration
- [x] ArkTS tests, official runtime comparisons and unsigned HAP build

## Requires target-device validation

- [ ] Confirm recursive document-provider child URIs on HarmonyOS PC hardware
- [ ] Confirm mixed file/folder picker support on all target PC device models
- [ ] Configure release signing and produce a signed distribution HAP

## Not faithfully portable to the current runtime

- [ ] Host JavaScript callbacks through `Options.functions`
- [ ] External JavaScript `Importer` and `FileImporter` callback objects
- [ ] External JavaScript `Logger` callback objects
- [ ] Filesystem-backed `NodePackageImporter` outside the loaded virtual project
- [ ] Dart Sass Embedded Protocol
- [ ] Complete Dart Sass CLI stdin/stdout, directory mapping, flags, watch and
      `--update` target/dependency timestamp graph
- [ ] Filesystem file-entry npm APIs (`compile()` and `compileAsync()`),
      JavaScript callback/value object APIs and the legacy JavaScript API
      surface

These items depend on a Node.js filesystem/process environment or callback
objects that cannot cross the current ArkTS-to-ArkWeb JSON bridge. The portable
package-resolution behavior is implemented for files loaded into the virtual
project. Authorized-file polling and automatic recompilation are implemented,
but they are not presented as CLI `--update`, which additionally depends on
output and transitive dependency timestamps. The remaining items are documented
as platform boundaries rather than replaced with incompatible approximations.
The official browser build also rejects legacy `render()` and `renderSync()`
when only the `data` string option is used.
