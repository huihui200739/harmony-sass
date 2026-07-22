# Compatibility Status

## Implemented

- [x] Native HarmonyOS PC two-pane editor UI
- [x] Official Dart Sass `1.101.3` browser runtime
- [x] SCSS, indented Sass and CSS input
- [x] Complete Sass language semantics supplied by Dart Sass
- [x] Built-in `sass:*` modules and Sass-authored `@function`
- [x] Expanded and compressed CSS
- [x] Source Maps with embedded sources
- [x] Virtual multi-file projects and load paths
- [x] Relative `@use`, `@forward` and legacy `@import`
- [x] Partials, directory indexes, import-only files and ambiguity errors
- [x] Official-compatible direct/index and Sass/CSS resolution precedence
- [x] Structured errors, warnings, deprecation IDs, stacks and `@debug`
- [x] Multiple-entry batch CSS and Source Map export
- [x] Open, save, save-as, save-all, copy and keyboard workflows
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
- [ ] `NodePackageImporter`, `pkg:` URLs and Node package exports
- [ ] Dart Sass Embedded Protocol
- [ ] Complete Dart Sass CLI stdin/stdout, directory mapping, flags and watch

These items depend on a Node.js filesystem/process environment or callback
objects that cannot cross the current ArkTS-to-ArkWeb JSON bridge. They are
documented as platform boundaries rather than replaced with incompatible
approximations.
