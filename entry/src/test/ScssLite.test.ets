import { describe, expect, it } from '@ohos/hypium';
import { ScssLite } from '../main/ets/compiler/ScssLite';

const compiler: ScssLite = new ScssLite();

export default function scssLiteTest() {
  describe('ScssLite', (): void => {
    it('replaces variables and emits a root rule', 0, (): void => {
      expect(compiler.compile('$color: red;\n.button { color: $color; }')).assertEqual('.button {\n  color: red;\n}');
    });

    it('flattens nested and parent selectors', 0, (): void => {
      const css: string = compiler.compile('.card { padding: 1px; .title { color: blue; } &:hover { color: red; } }');
      expect(css).assertEqual('.card {\n  padding: 1px;\n}\n\n.card .title {\n  color: blue;\n}\n\n.card:hover {\n  color: red;\n}');
    });

    it('expands selector lists', 0, (): void => {
      const css: string = compiler.compile('.a, .b { .item, .label { display: block; } }');
      expect(css).assertEqual('.a .item,\n.a .label,\n.b .item,\n.b .label {\n  display: block;\n}');
    });

    it('reports malformed source', 0, (): void => {
      let failed: boolean = false;
      try { compiler.compile('.card { color: red;'); } catch (_error) { failed = true; }
      expect(failed).assertTrue();
    });
  });
}
