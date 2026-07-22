import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import * as sass from 'sass';

const toolsDir = dirname(fileURLToPath(import.meta.url));
const sassPackage = JSON.parse(
  await readFile(resolve(toolsDir, 'node_modules/sass/package.json'), 'utf8')
);
const runtimeFile = resolve(
  toolsDir,
  '../entry/src/main/resources/rawfile/sass-runtime.js'
);
const runtimeSource = await readFile(runtimeFile, 'utf8');
const context = {
  console,
  setTimeout,
  clearTimeout,
  TextDecoder,
  TextEncoder,
  URL,
  location: { href: 'resource://rawfile/sass-runtime.html' }
};
context.globalThis = context;
context.self = context;
context.window = context;
vm.createContext(context);
vm.runInContext(runtimeSource, context);

const fixtures = [
  {
    name: 'variables and nesting',
    source: '$brand: #0a7bff; .card { color: $brand; .title { font-weight: 700; } }'
  },
  {
    name: 'mixins',
    source: '@mixin rounded($radius) { border-radius: $radius; } .card { @include rounded(8px); }'
  },
  {
    name: 'media queries',
    source: '.card { width: 20rem; @media (max-width: 600px) { width: 100%; } }'
  },
  {
    name: 'conditionals and arithmetic',
    source: '$wide: true; .card { width: 4px * 3; @if $wide { display: grid; } }'
  },
  {
    name: 'custom functions',
    source: '@function double($value) { @return $value * 2; } .card { gap: double(6px); }'
  },
  {
    name: 'built-in modules',
    source: '@use "sass:color"; .card { color: color.adjust(#036, $lightness: 20%); }'
  },
  {
    name: 'quoted punctuation',
    source: '.card::before { content: "{value;still-string}"; }'
  },
  {
    name: 'local variable scope',
    source: '$size: 1px; .a { $size: 2px; width: $size; } .b { width: $size; }'
  },
  {
    name: 'loud comments',
    source: '/*! retained */ .card { color: red; }'
  }
];

for (const fixture of fixtures) {
  const actual = JSON.parse(context.harmonySass.compile(fixture.source));
  const expected = sass.compileString(fixture.source, {
    syntax: 'scss',
    style: 'expanded',
    sourceMap: false
  }).css;
  assert.equal(actual.ok, true, `${fixture.name} should compile`);
  assert.equal(actual.css, expected, `${fixture.name} should match Dart Sass`);
  assert.equal(actual.version, sassPackage.version);
}

const project = JSON.parse(context.harmonySass.compileProject({
  source: '@use "tokens"; @use "components/button"; .app { color: tokens.$brand; }',
  entryPath: 'src/main.scss',
  files: [
    { path: 'src/_tokens.scss', contents: '$brand: #0a7bff;' },
    {
      path: 'src/components/_button.scss',
      contents: '@use "../tokens"; .button { color: tokens.$brand; }'
    }
  ]
}));
assert.equal(project.ok, true, 'virtual project should compile');
assert.match(project.css, /\.button/);
assert.match(project.css, /\.app/);
assert.equal(project.loadedUrls.length, 3);

const forwarded = JSON.parse(context.harmonySass.compileProject({
  source: '@use "theme"; .card { color: theme.$brand; }',
  entryPath: 'app.scss',
  files: [
    { path: '_colors.scss', contents: '$brand: rebeccapurple;' },
    { path: '_theme.scss', contents: '@forward "colors";' }
  ]
}));
assert.equal(forwarded.ok, true, '@forward should resolve virtual partials');
assert.match(forwarded.css, /rebeccapurple/);

const imported = JSON.parse(context.harmonySass.compileProject({
  source: '@import "legacy";',
  entryPath: 'app.scss',
  files: [
    { path: '_legacy.import.scss', contents: '.legacy { display: block; }' },
    { path: '_legacy.scss', contents: '.wrong { display: none; }' }
  ]
}));
assert.equal(imported.ok, true, '@import should prefer import-only files');
assert.match(imported.css, /\.legacy/);
assert.doesNotMatch(imported.css, /\.wrong/);

const compressed = JSON.parse(context.harmonySass.compileProject({
  source: '.card { color: red; }',
  style: 'compressed'
}));
assert.equal(compressed.ok, true);
assert.equal(compressed.css, '.card{color:red}');

const indented = JSON.parse(context.harmonySass.compileProject({
  source: '.card\n  color: red',
  entryPath: 'app.sass',
  syntax: 'indented'
}));
assert.equal(indented.ok, true);
assert.match(indented.css, /color: red/);

const css = JSON.parse(context.harmonySass.compileProject({
  source: '.card { color: red; }',
  entryPath: 'app.css',
  syntax: 'css'
}));
assert.equal(css.ok, true);
assert.match(css.css, /\.card/);

const sourceMap = JSON.parse(context.harmonySass.compileProject({
  source: '@use "tokens"; .card { color: tokens.$brand; }',
  entryPath: 'src/app.scss',
  sourceMap: true,
  files: [{
    path: 'src/_tokens.scss',
    contents: '$brand: blue; .tokens { color: $brand; }'
  }]
}));
assert.equal(sourceMap.ok, true);
assert.ok(sourceMap.sourceMap.length > 0);
assert.deepEqual(
  JSON.parse(sourceMap.sourceMap).sources.sort(),
  ['harmony-sass:/src/_tokens.scss', 'harmony-sass:/src/app.scss'].sort()
);

const warning = JSON.parse(context.harmonySass.compileProject({
  source: '@warn "check me"; .card { color: red; }'
}));
assert.equal(warning.ok, true);
assert.equal(warning.warnings.length, 1);
assert.match(warning.warnings[0].message, /check me/);

const failure = JSON.parse(
  context.harmonySass.compile('.card { color: $missing; }')
);
assert.equal(failure.ok, false);
assert.equal(failure.error.line, 1);
assert.equal(failure.error.column, 16);
assert.match(failure.error.message, /Undefined variable/);
assert.equal(failure.error.span.start.line, 1);
assert.equal(failure.error.span.end.column, 24);

console.log(
  `Verified ${fixtures.length} single-document fixtures and project workflow against Dart Sass ${sassPackage.version}.`
);
