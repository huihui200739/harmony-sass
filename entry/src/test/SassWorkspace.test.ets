import { describe, expect, it } from '@ohos/hypium';
import {
  SassBatchCompileResponse,
  SassBatchCompileResult
} from '../main/ets/compiler/DartSassRuntime';
import { SassEditorFile } from '../main/ets/compiler/SassProject';
import { SassWorkspace } from '../main/ets/compiler/SassWorkspace';

export default function sassWorkspaceTest() {
  describe('SassWorkspace', (): void => {
    const files: SassEditorFile[] = [{
      path: 'src/app.scss',
      uri: 'file:///project/src/app.scss',
      contents: '@use "tokens";',
      syntax: 'scss'
    }, {
      path: 'src/admin.scss',
      uri: 'file:///project/src/admin.scss',
      contents: '@use "tokens";',
      syntax: 'scss'
    }, {
      path: 'src/_tokens.scss',
      uri: 'file:///project/src/_tokens.scss',
      contents: '$brand: blue;',
      syntax: 'scss'
    }];

    it('maps official loaded URLs back to virtual project paths', 0, (): void => {
      expect(SassWorkspace.projectPathForLoadedUrl(
        'file:///project/src/_tokens.scss',
        files
      )).assertEqual('src/_tokens.scss');
      expect(SassWorkspace.projectPathForLoadedUrl(
        'harmony-sass:/src/app.scss',
        files
      )).assertEqual('src/app.scss');
    });

    it('updates dependencies and selects only affected entries', 0, (): void => {
      const results: SassBatchCompileResult[] = [{
        entryPath: 'src/app.scss',
        ok: true,
        version: '1.101.6',
        css: '.app {}',
        loadedUrls: [
          'file:///project/src/app.scss',
          'file:///project/src/_tokens.scss'
        ]
      }, {
        entryPath: 'src/admin.scss',
        ok: true,
        version: '1.101.6',
        css: '.admin {}',
        loadedUrls: [
          'file:///project/src/admin.scss',
          'file:///project/src/_tokens.scss'
        ]
      }];
      const graph: Map<string, Set<string>> =
        SassWorkspace.updateDependencyGraph(
          new Map<string, Set<string>>(),
          results,
          files
        );
      expect(graph.get('src/_tokens.scss')?.size).assertEqual(2);
      expect(SassWorkspace.affectedEntryPaths(
        ['src/app.scss'],
        graph,
        ['src/app.scss', 'src/admin.scss']
      ).length).assertEqual(1);
      expect(SassWorkspace.affectedEntryPaths(
        ['src/_tokens.scss'],
        graph,
        ['src/app.scss', 'src/admin.scss']
      ).length).assertEqual(2);
      expect(SassWorkspace.affectedEntryPaths(
        ['src/new.scss'],
        graph,
        ['src/app.scss', 'src/admin.scss']
      ).length).assertEqual(2);
    });

    it('merges incremental results into the complete project result', 0, (): void => {
      const previous: Map<string, SassBatchCompileResult> =
        new Map<string, SassBatchCompileResult>();
      previous.set('src/admin.scss', {
        entryPath: 'src/admin.scss',
        ok: true,
        version: '1.101.6',
        css: '.admin {}'
      });
      const response: SassBatchCompileResponse = {
        ok: true,
        version: '1.101.6',
        results: [{
          entryPath: 'src/app.scss',
          ok: true,
          version: '1.101.6',
          css: '.app {}'
        }]
      };
      const merged: SassBatchCompileResponse =
        SassWorkspace.mergeBatchResponse(
          previous,
          response,
          ['src/app.scss', 'src/admin.scss']
        );
      expect(merged.results.length).assertEqual(2);
      expect(merged.results[1].entryPath).assertEqual('src/admin.scss');
    });

    it('detects rename pairs by their unchanged contents', 0, (): void => {
      const renames = SassWorkspace.detectRenames(
        [{
          path: 'src/old.scss',
          uri: 'file:///project/src/old.scss',
          contents: '.same {}',
          syntax: 'scss'
        }],
        [{
          path: 'src/new.scss',
          uri: 'file:///project/src/new.scss',
          contents: '.same {}',
          syntax: 'scss'
        }]
      );
      expect(renames.length).assertEqual(1);
      expect(renames[0].oldPath).assertEqual('src/old.scss');
      expect(renames[0].newPath).assertEqual('src/new.scss');
    });
  });
}
