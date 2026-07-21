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

const failure = JSON.parse(
  context.harmonySass.compile('.card { color: $missing; }')
);
assert.equal(failure.ok, false);
assert.equal(failure.error.line, 1);
assert.equal(failure.error.column, 16);
assert.match(failure.error.message, /Undefined variable/);

console.log(
  `Verified ${fixtures.length} compatibility fixtures against Dart Sass ${sassPackage.version}.`
);
