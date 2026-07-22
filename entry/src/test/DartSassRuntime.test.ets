import { describe, expect, it } from '@ohos/hypium';
import {
  DartSassRuntime,
  SassBatchCompileRequest,
  SassBatchCompileResponse,
  SassCompileRequest,
  SassCompileResponse,
  SassExportFinalizeRequest,
  SassExportFinalizeResponse,
  SassRuntimeMetadata
} from '../main/ets/compiler/DartSassRuntime';

export default function dartSassRuntimeTest() {
  describe('DartSassRuntime', (): void => {
    it('escapes source before crossing the JavaScript bridge', 0, (): void => {
      const script: string = DartSassRuntime.createCompileScript(
        '.a::before { content: "` ${value} \\""; }'
      );
      expect(script).assertEqual(
        'globalThis.harmonySass.compileProject({"source":".a::before { content: \\"` ${value} \\\\\\"\\"; }",' +
        '"entryPath":"stdin.scss","entryUri":"","files":[],"loadPaths":[],"nodePackageImporter":false,' +
        '"packageEntryPointDirectory":"","syntax":"scss","style":"expanded",' +
        '"alertAscii":false,"alertColor":false,' +
        '"sourceMap":false,"sourceMapIncludeSources":true,"charset":true,"quiet":false,' +
        '"quietDeps":false,"verbose":false,"errorCss":false,' +
        '"fatalDeprecations":[],"futureDeprecations":[],"silenceDeprecations":[]})'
      );
    });

    it('serializes project files and compiler options', 0, (): void => {
      const request: SassCompileRequest = {
        source: '@use "tokens";',
        entryPath: 'src/app.scss',
        entryUri: 'file:///project/src/app.scss',
        files: [{
          path: 'src/_tokens.scss',
          uri: 'file:///project/src/_tokens.scss',
          contents: '$brand: blue;'
        }],
        loadPaths: ['src'],
        nodePackageImporter: true,
        packageEntryPointDirectory: 'src',
        syntax: 'scss',
        style: 'compressed',
        alertAscii: false,
        alertColor: false,
        sourceMap: true,
        sourceMapIncludeSources: true,
        charset: false,
        quiet: false,
        quietDeps: true,
        verbose: false,
        errorCss: true,
        fatalDeprecations: ['import'],
        futureDeprecations: [],
        silenceDeprecations: ['slash-div']
      };
      const script: string = DartSassRuntime.createProjectCompileScript(request);
      expect(script.startsWith('globalThis.harmonySass.compileProject(')).assertTrue();
      expect(script.includes('src/_tokens.scss')).assertTrue();
      expect(script.includes('"sourceMap":true')).assertTrue();
      expect(script.includes('"fatalDeprecations":["import"]')).assertTrue();
      expect(script.includes('"nodePackageImporter":true')).assertTrue();
      expect(script.includes('"packageEntryPointDirectory":"src"')).assertTrue();
      expect(script.includes('"entryUri":"file:///project/src/app.scss"')).assertTrue();
      expect(script.includes('"errorCss":true')).assertTrue();
    });

    it('serializes and parses batch compilation', 0, (): void => {
      const request: SassBatchCompileRequest = {
        entryPaths: ['src/app.scss', 'src/admin.scss'],
        files: [
          { path: 'src/app.scss', contents: '.app { color: blue; }' },
          { path: 'src/admin.scss', contents: '.admin { color: red; }' }
        ],
        loadPaths: [],
        nodePackageImporter: true,
        packageEntryPointDirectory: '',
        style: 'expanded',
        alertAscii: false,
        alertColor: false,
        sourceMap: false,
        sourceMapIncludeSources: true,
        charset: true,
        quiet: false,
        quietDeps: false,
        verbose: false,
        errorCss: true,
        stopOnError: true,
        fatalDeprecations: [],
        futureDeprecations: [],
        silenceDeprecations: []
      };
      const script: string = DartSassRuntime.createBatchCompileScript(request);
      expect(script.startsWith('globalThis.harmonySass.compileBatch(')).assertTrue();
      const response: SassBatchCompileResponse = DartSassRuntime.parseBatchResponse(
        '{"ok":true,"version":"1.101.3","results":[' +
        '{"entryPath":"src/app.scss","ok":true,"version":"1.101.3","css":".app {}"}]}'
      );
      expect(response.results[0].entryPath).assertEqual('src/app.scss');
    });

    it('serializes and parses official file export finalization', 0, (): void => {
      const request: SassExportFinalizeRequest = {
        style: 'expanded',
        sourceMapUrls: 'relative',
        embedSourceMap: false,
        entries: [{
          css: '.a {\n  color: red;\n}',
          sourceMap: '{"version":3,"mappings":"AAAA"}',
          cssFileName: 'a b.css',
          sourceMapFileName: 'a b.css.map',
          cssUri: 'file:///output/a%20b.css',
          sourceMapUri: 'file:///output/a%20b.css.map'
        }]
      };
      const script: string =
        DartSassRuntime.createFinalizeExportsScript(request);
      expect(script.startsWith(
        'globalThis.harmonySass.finalizeExports('
      )).assertTrue();
      expect(script.includes('"cssFileName":"a b.css"')).assertTrue();
      const response: SassExportFinalizeResponse =
        DartSassRuntime.parseFinalizeExportsResponse(
          '{"results":[{"css":".a {}\\n","sourceMap":' +
          '"{\\"version\\":3,\\"file\\":\\"a%20b.css\\"}"}]}'
        );
      expect(response.results.length).assertEqual(1);
      expect(response.results[0].sourceMap).assertEqual(
        '{"version":3,"file":"a%20b.css"}'
      );
    });

    it('requests and parses official runtime metadata', 0, (): void => {
      expect(DartSassRuntime.createMetadataScript()).assertEqual(
        'globalThis.harmonySass.getMetadata()'
      );
      const metadata: SassRuntimeMetadata = DartSassRuntime.parseMetadata(
        '{"version":"1.101.3","info":"dart-sass\\t1.101.3",' +
        '"deprecations":[{"id":"import","status":"active",' +
        '"description":"@import rules.","deprecatedIn":"1.80.0"}]}'
      );
      expect(metadata.version).assertEqual('1.101.3');
      expect(metadata.info).assertEqual('dart-sass\t1.101.3');
      expect(metadata.deprecations[0].id).assertEqual('import');
      expect(metadata.deprecations[0].deprecatedIn).assertEqual('1.80.0');
    });

    it('parses a successful runtime response', 0, (): void => {
      const response: SassCompileResponse = DartSassRuntime.parseResponse(
        '{"ok":true,"version":"1.101.3","css":".a {\\n  color: red;\\n}"}'
      );
      expect(response.ok).assertTrue();
      expect(response.version).assertEqual('1.101.3');
      expect(response.css).assertEqual('.a {\n  color: red;\n}');
    });

    it('accepts a JSON string returned by alternate ArkWeb versions', 0, (): void => {
      const response: SassCompileResponse = DartSassRuntime.parseResponse(
        '"{\\"ok\\":true,\\"version\\":\\"1.101.3\\",\\"css\\":\\".a {}\\"}"'
      );
      expect(response.ok).assertTrue();
      expect(response.css).assertEqual('.a {}');
    });

    it('parses structured compiler errors', 0, (): void => {
      const response: SassCompileResponse = DartSassRuntime.parseResponse(
        '{"ok":false,"version":"1.101.3","error":{"message":"Undefined variable.",' +
        '"formatted":"Undefined variable.","sassStack":"app.scss 2:8  root stylesheet\\n",' +
        '"line":2,"column":8}}'
      );
      expect(response.ok).assertFalse();
      expect(response.error?.line).assertEqual(2);
      expect(response.error?.column).assertEqual(8);
      expect(response.error?.sassStack).assertEqual(
        'app.scss 2:8  root stylesheet\n'
      );
    });

    it('parses source maps, loaded URLs and warnings', 0, (): void => {
      const response: SassCompileResponse = DartSassRuntime.parseResponse(
        '{"ok":true,"version":"1.101.3","css":".a {}",' +
        '"sourceMap":"{\\"version\\":3}","loadedUrls":["harmony-sass:/app.scss"],' +
        '"warnings":[{"message":"notice","deprecation":false}],' +
        '"debugMessages":[{"message":"debug value"}]}'
      );
      expect(response.sourceMap).assertEqual('{"version":3}');
      expect(response.loadedUrls?.length).assertEqual(1);
      expect(response.warnings?.[0].message).assertEqual('notice');
      expect(response.debugMessages?.[0].message).assertEqual('debug value');
    });
  });
}
