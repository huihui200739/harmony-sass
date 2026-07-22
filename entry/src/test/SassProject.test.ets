import { describe, expect, it } from '@ohos/hypium';
import { SassEditorFile, SassProject } from '../main/ets/compiler/SassProject';

export default function sassProjectTest() {
  describe('SassProject', (): void => {
    it('normalizes project paths and detects syntax', 0, (): void => {
      expect(SassProject.normalizePath('src/./theme/../app.scss')).assertEqual('src/app.scss');
      expect(SassProject.syntaxForPath('styles/main.scss')).assertEqual('scss');
      expect(SassProject.syntaxForPath('styles/main.sass')).assertEqual('indented');
      expect(SassProject.syntaxForPath('styles/reset.css')).assertEqual('css');
      expect(SassProject.syntaxForPath('node_modules/theme/package.json')).assertEqual('json');
      expect(SassProject.isStylesheetPath('styles/main.scss')).assertTrue();
      expect(SassProject.isPackageManifestPath('node_modules/theme/package.json')).assertTrue();
      expect(SassProject.isPackageManifestPath('config.json')).assertFalse();
      expect(SassProject.isProjectFilePath('node_modules/theme/package.json')).assertTrue();
      expect(SassProject.isProjectFilePath('config.json')).assertFalse();
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
          syntax: 'indented'
        }
      ]);
      expect(files[0].path).assertEqual('main.scss');
      expect(files[1].path).assertEqual('components/_button.scss');
      expect(files[1].syntax).assertEqual('indented');
    });

    it('selects non-partial entry files and creates unique output names', 0, (): void => {
      const files: SassEditorFile[] = [
        {
          path: 'src/app.scss',
          uri: 'file://src/app.scss',
          contents: '',
          syntax: 'scss'
        },
        {
          path: 'src/_tokens.scss',
          uri: 'file://src/_tokens.scss',
          contents: '',
          syntax: 'scss'
        },
        {
          path: 'admin/app.scss',
          uri: 'file://admin/app.scss',
          contents: '',
          syntax: 'scss'
        },
        {
          path: 'node_modules/theme/package.json',
          uri: 'file://node_modules/theme/package.json',
          contents: '{"sass":"index.scss"}',
          syntax: 'json'
        }
      ];
      const entries: string[] = SassProject.entryPaths(files);
      expect(entries.length).assertEqual(2);
      expect(entries[0]).assertEqual('src/app.scss');
      expect(entries[1]).assertEqual('admin/app.scss');
      const names: string[] = SassProject.outputFileNames(entries, '.css');
      expect(names[0]).assertEqual('src-app.css');
      expect(names[1]).assertEqual('admin-app.css');
      const editableFiles: SassEditorFile[] =
        SassProject.editableStylesheetFiles(files);
      expect(editableFiles.length).assertEqual(3);
      expect(editableFiles[0].path).assertEqual('src/app.scss');
      expect(editableFiles[2].path).assertEqual('admin/app.scss');
      const compilerFiles = SassProject.compilerFiles(files, 'src/app.scss');
      expect(compilerFiles.length).assertEqual(3);
      expect(compilerFiles[2].path).assertEqual(
        'node_modules/theme/package.json'
      );
    });

    it('keeps a manually selected syntax in the project model', 0, (): void => {
      const files: SassEditorFile[] = [{
        path: 'template.scss',
        uri: 'file://template.scss',
        contents: '.card\n  color: red',
        syntax: 'scss'
      }];
      const updated: SassEditorFile[] =
        SassProject.updateSyntax(files, 'template.scss', 'indented');
      expect(updated[0].syntax).assertEqual('indented');
      expect(files[0].syntax).assertEqual('scss');
    });

    it('removes only an untouched placeholder when a real project is loaded', 0, (): void => {
      const placeholder: SassEditorFile = {
        path: 'untitled.scss',
        uri: '',
        contents: '.sample { color: blue; }',
        syntax: 'scss'
      };
      expect(SassProject.withoutUntouchedPlaceholder(
        [placeholder],
        placeholder.path,
        placeholder.contents,
        []
      ).length).assertEqual(0);
      expect(SassProject.withoutUntouchedPlaceholder(
        [placeholder],
        placeholder.path,
        placeholder.contents,
        [placeholder.path]
      ).length).assertEqual(1);
    });

    it('deduplicates project document uris in selection order', 0, (): void => {
      const uris: string[] = SassProject.uniqueUris([
        'file://main.scss',
        'file://_tokens.scss',
        'file://main.scss',
        ''
      ]);
      expect(uris.length).assertEqual(2);
      expect(uris[0]).assertEqual('file://main.scss');
      expect(uris[1]).assertEqual('file://_tokens.scss');
    });
  });
}
