import { SassProjectFile } from './DartSassRuntime';

export interface SassEditorFile {
  path: string;
  uri: string;
  contents: string;
  syntax: string;
}

export class SassProject {
  static normalizePath(value: string): string {
    const normalized: string[] = [];
    const parts: string[] = value.replaceAll('\\', '/').split('/');
    for (const part of parts) {
      if (part.length === 0 || part === '.') {
        continue;
      }
      if (part === '..') {
        normalized.pop();
        continue;
      }
      normalized.push(part);
    }
    return normalized.join('/');
  }

  static syntaxForPath(path: string): string {
    const lowerPath: string = path.toLowerCase();
    if (lowerPath.endsWith('.sass')) {
      return 'indented';
    }
    if (lowerPath.endsWith('.css')) {
      return 'css';
    }
    return 'scss';
  }

  static fileNameFromUri(uri: string): string {
    const segments: string[] = SassProject.uriSegments(uri);
    return segments.length > 0 ? segments[segments.length - 1] : 'untitled.scss';
  }

  static deriveVirtualPaths(uris: string[]): string[] {
    if (uris.length === 0) {
      return [];
    }

    const allSegments: string[][] = uris.map((uri: string): string[] => SassProject.uriSegments(uri));
    if (uris.length === 1) {
      const segments: string[] = allSegments[0];
      return [segments.length > 0 ? segments[segments.length - 1] : 'untitled.scss'];
    }

    let commonLength: number = allSegments[0].length - 1;
    for (let index: number = 1; index < allSegments.length; index++) {
      commonLength = Math.min(commonLength, allSegments[index].length - 1);
      for (let segmentIndex: number = 0; segmentIndex < commonLength; segmentIndex++) {
        if (allSegments[index][segmentIndex] !== allSegments[0][segmentIndex]) {
          commonLength = segmentIndex;
          break;
        }
      }
    }

    return allSegments.map((segments: string[], index: number): string => {
      const relative: string = SassProject.normalizePath(segments.slice(commonLength).join('/'));
      return relative.length > 0 ? relative : `file-${index + 1}.scss`;
    });
  }

  static mergeFiles(existing: SassEditorFile[], incoming: SassEditorFile[]): SassEditorFile[] {
    const merged: SassEditorFile[] = existing.slice();
    for (const file of incoming) {
      let replacementIndex: number = -1;
      for (let index: number = 0; index < merged.length; index++) {
        if ((file.uri.length > 0 && merged[index].uri === file.uri) || merged[index].path === file.path) {
          replacementIndex = index;
          break;
        }
      }
      if (replacementIndex >= 0) {
        merged[replacementIndex] = file;
      } else {
        merged.push(file);
      }
    }
    return merged;
  }

  static rebaseUriFiles(files: SassEditorFile[]): SassEditorFile[] {
    const uris: string[] = [];
    for (const file of files) {
      if (file.uri.length > 0) {
        uris.push(file.uri);
      }
    }
    const rebasedPaths: string[] = SassProject.deriveVirtualPaths(uris);
    let uriIndex: number = 0;
    return files.map((file: SassEditorFile): SassEditorFile => {
      if (file.uri.length === 0) {
        return file;
      }
      const rebased: SassEditorFile = {
        path: rebasedPaths[uriIndex],
        uri: file.uri,
        contents: file.contents,
        syntax: SassProject.syntaxForPath(rebasedPaths[uriIndex])
      };
      uriIndex++;
      return rebased;
    });
  }

  static updateContents(files: SassEditorFile[], path: string, contents: string): SassEditorFile[] {
    return files.map((file: SassEditorFile): SassEditorFile => {
      if (file.path !== path) {
        return file;
      }
      return {
        path: file.path,
        uri: file.uri,
        contents,
        syntax: file.syntax
      };
    });
  }

  static compilerFiles(files: SassEditorFile[], entryPath: string): SassProjectFile[] {
    const compilerFiles: SassProjectFile[] = [];
    for (const file of files) {
      if (file.path === entryPath) {
        continue;
      }
      compilerFiles.push({
        path: file.path,
        contents: file.contents,
        syntax: file.syntax
      });
    }
    return compilerFiles;
  }

  static replaceUri(files: SassEditorFile[], path: string, uri: string): SassEditorFile[] {
    return files.map((file: SassEditorFile): SassEditorFile => {
      if (file.path !== path) {
        return file;
      }
      return {
        path: file.path,
        uri,
        contents: file.contents,
        syntax: file.syntax
      };
    });
  }

  private static uriSegments(uri: string): string[] {
    let decoded: string = uri;
    try {
      decoded = decodeURIComponent(uri);
    } catch (_) {
      decoded = uri;
    }
    const queryIndex: number = decoded.indexOf('?');
    if (queryIndex >= 0) {
      decoded = decoded.slice(0, queryIndex);
    }
    const fragmentIndex: number = decoded.indexOf('#');
    if (fragmentIndex >= 0) {
      decoded = decoded.slice(0, fragmentIndex);
    }
    const schemeIndex: number = decoded.indexOf('://');
    if (schemeIndex >= 0) {
      decoded = decoded.slice(schemeIndex + 3);
    }
    return SassProject.normalizePath(decoded).split('/').filter((part: string): boolean => part.length > 0);
  }
}
