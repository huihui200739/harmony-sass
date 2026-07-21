import { describe, expect, it } from '@ohos/hypium';
import {
  DartSassRuntime,
  SassCompileResponse
} from '../main/ets/compiler/DartSassRuntime';

export default function dartSassRuntimeTest() {
  describe('DartSassRuntime', (): void => {
    it('escapes source before crossing the JavaScript bridge', 0, (): void => {
      const script: string = DartSassRuntime.createCompileScript(
        '.a::before { content: "` ${value} \\""; }'
      );
      expect(script).assertEqual(
        'globalThis.harmonySass.compile(".a::before { content: \\"` ${value} \\\\\\"\\"; }")'
      );
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
  });
}
