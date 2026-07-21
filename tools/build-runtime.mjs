import { build } from 'esbuild';
import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const toolsDir = dirname(fileURLToPath(import.meta.url));
const projectDir = resolve(toolsDir, '..');
const rawfileDir = resolve(projectDir, 'entry/src/main/resources/rawfile');
const outputFile = resolve(rawfileDir, 'sass-runtime.js');
const sassPackageDir = dirname(fileURLToPath(import.meta.resolve('sass')));

await mkdir(rawfileDir, { recursive: true });

await build({
  entryPoints: [resolve(toolsDir, 'runtime-entry.mjs')],
  outfile: outputFile,
  bundle: true,
  platform: 'browser',
  format: 'iife',
  target: ['es2020'],
  minify: true,
  legalComments: 'external',
  banner: {
    js: '/* Harmony Sass runtime: official Dart Sass 1.101.3 browser build. */'
  }
});

const html = `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Harmony Sass Runtime</title>
</head>
<body>
  <script src="./sass-runtime.js"></script>
</body>
</html>
`;

await writeFile(resolve(rawfileDir, 'sass-runtime.html'), html, 'utf8');
await copyFile(
  resolve(sassPackageDir, 'LICENSE'),
  resolve(rawfileDir, 'dart-sass-license.txt')
);

const legalFile = `${outputFile}.LEGAL.txt`;
const legal = await readFile(legalFile, 'utf8');
await writeFile(
  legalFile,
  `Harmony Sass bundles the official Dart Sass JavaScript distribution.
Upstream: https://github.com/sass/dart-sass
Version: 1.101.3

${legal}`,
  'utf8'
);

console.log(`Built ${outputFile}`);
