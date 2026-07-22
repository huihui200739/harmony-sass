import { describe, expect, it } from '@ohos/hypium';
import {
  DartSassRuntime,
  SassCompileRequest,
  SassCompileResponse
} from '../main/ets/compiler/DartSassRuntime';

export default function dartSassRuntimeTest() {
  describe('DartSassRuntime', (): void => {
    it('escapes source before crossing the JavaScript bridge', 0, (): void => {
      const script: string = DartSassRuntime.createCompileScript(
        '.a::before { content: "` ${value} \\""; }'
      );
      expect(script).assertEqual(
        'globalThis.harmonySass.compileProject({"source":".a::before { content: \\"` ${value} \\\\\\"\\"; }",' +
        '"entryPath":"stdin.scss","files":[],"loadPaths":[],"syntax":"scss","style":"expanded",' +
        '"sourceMap":false,"sourceMapIncludeSources":true,"charset":true,"quietDeps":false,"verbose":false})'
      );
    });

    it('serializes project files and compiler options', 0, (): void => {
      const request: SassCompileRequest = {
        source: '@use "tokens";',
        entryPath: 'src/app.scss',
        files: [{ path: 'src/_tokens.scss', contents: '$brand: blue;' }],
        loadPaths: ['src'],
        syntax: 'scss',
        style: 'compressed',
        sourceMap: true,
        sourceMapIncludeSources: true,
        charset: false,
        quietDeps: true,
        verbose: false
      };
      const script: string = DartSassRuntime.createProjectCompileScript(request);
      expect(script.startsWith('globalThis.harmonySass.compileProject(')).assertTrue();
      expect(script.includes('src/_tokens.scss')).assertTrue();
      expect(script.includes('"sourceMap":true')).assertTrue();
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
        '"formatted":"Undefined variable.","line":2,"column":8}}'
      );
      expect(response.ok).assertFalse();
      expect(response.error?.line).assertEqual(2);
      expect(response.error?.column).assertEqual(8);
    });

    it('parses source maps, loaded URLs and warnings', 0, (): void => {
      const response: SassCompileResponse = DartSassRuntime.parseResponse(
        '{"ok":true,"version":"1.101.3","css":".a {}",' +
        '"sourceMap":"{\\"version\\":3}","loadedUrls":["harmony-sass:/app.scss"],' +
        '"warnings":[{"message":"notice","deprecation":false}]}'
      );
      expect(response.sourceMap).assertEqual('{"version":3}');
      expect(response.loadedUrls?.length).assertEqual(1);
      expect(response.warnings?.[0].message).assertEqual('notice');
    });
  });
}
