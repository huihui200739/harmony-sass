import { describe, expect, it } from '@ohos/hypium';
import { SassEditorFile, SassProject } from '../main/ets/compiler/SassProject';

export default function sassProjectTest() {
  describe('SassProject', (): void => {
    it('normalizes project paths and detects syntax', 0, (): void => {
      expect(SassProject.normalizePath('src/./theme/../app.scss')).assertEqual('src/app.scss');
      expect(SassProject.syntaxForPath('styles/main.scss')).assertEqual('scss');
      expect(SassProject.syntaxForPath('styles/main.sass')).assertEqual('indented');
      expect(SassProject.syntaxForPath('styles/reset.css')).assertEqual('css');
    });

    it('derives relative virtual paths from selected URIs', 0, (): void => {
      const paths: string[] = SassProject.deriveVirtualPaths([
        'file://docs/project/src/main.scss',
        'file://docs/project/src/_tokens.scss',
        'file://docs/project/src/components/_button.scss'
      ]);
      expect(paths[0]).assertEqual('main.scss');
      expect(paths[1]).assertEqual('_tokens.scss');
      expect(paths[2]).assertEqual('components/_button.scss');
    });

    it('merges duplicate files and excludes the entry from imports', 0, (): void => {
      const first: SassEditorFile = {
        path: 'main.scss',
        uri: 'file://main.scss',
        contents: '@use "tokens";',
        syntax: 'scss'
      };
      const token: SassEditorFile = {
        path: '_tokens.scss',
        uri: 'file://_tokens.scss',
        contents: '$brand: blue;',
        syntax: 'scss'
      };
      const replacement: SassEditorFile = {
        path: '_tokens.scss',
        uri: 'file://_tokens.scss',
        contents: '$brand: red;',
        syntax: 'scss'
      };
      const merged: SassEditorFile[] = SassProject.mergeFiles([first, token], [replacement]);
      expect(merged.length).assertEqual(2);
      expect(merged[1].contents).assertEqual('$brand: red;');
      expect(SassProject.compilerFiles(merged, 'main.scss').length).assertEqual(1);
    });

    it('rebases separately selected files to their shared project root', 0, (): void => {
      const files: SassEditorFile[] = SassProject.rebaseUriFiles([
        {
          path: 'main.scss',
          uri: 'file://docs/project/src/main.scss',
          contents: '',
          syntax: 'scss'
        },
        {
          path: '_button.scss',
          uri: 'file://docs/project/src/components/_button.scss',
          contents: '',
          syntax: 'scss'
        }
      ]);
      expect(files[0].path).assertEqual('main.scss');
      expect(files[1].path).assertEqual('components/_button.scss');
    });
  });
}
