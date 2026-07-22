import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { KeyCode } from '@kit.InputKit';
import { webview } from '@kit.ArkWeb';
import {
  DartSassRuntime,
  SassAsyncJobPollResponse,
  SassAsyncJobStartResponse,
  SassBatchCompileRequest,
  SassBatchCompileResponse,
  SassBatchCompileResult,
  SassCompileError,
  SassCompileRequest,
  SassCompileResponse,
  SassDebugMessage,
  SassExportFinalizeEntry,
  SassExportFinalizeRequest,
  SassExportFinalizeResponse,
  SassRuntimeMetadata,
  SassSourceSpan,
  SassWarning
} from '../compiler/DartSassRuntime';
import { SassEditorFile, SassProject } from '../compiler/SassProject';

const SAMPLE_SCSS: string = `$brand: #0A7BFF;
$radius: 12px;

.card {
  padding: 20px;
  border-radius: $radius;
  background: #fff;

  .title {
    color: $brand;
    font-weight: 700;
  }

  &:hover {
    box-shadow: 0 8px 24px rgba(10, 123, 255, 0.18);
  }
}`;

const SAMPLE_FILE: SassEditorFile = {
  path: 'untitled.scss',
  uri: '',
  contents: SAMPLE_SCSS,
  syntax: 'scss'
};
const MAX_PROJECT_FILES: number = 500;

@Entry
@Component
struct Index {
  @State private source: string = SAMPLE_SCSS;
  @State private result: string = '';
  @State private displayResult: string = '';
  @State private sourceMapText: string = '';
  @State private files: SassEditorFile[] = [SAMPLE_FILE];
  @State private activePath: string = SAMPLE_FILE.path;
  @State private syntax: string = 'scss';
  @State private outputStyle: string = 'expanded';
  @State private loadPathsText: string = '';
  @State private sourceMapEnabled: boolean = false;
  @State private autoCompile: boolean = false;
  @State private runtimeVersion: string = '1.101.3';
  @State private statusMessage: string = '准备就绪：输入 SCSS 后点击“编译”。';
  @State private isSuccessful: boolean = true;
  @State private diagnosticCount: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  private runtimeReady: boolean = false;
  private isCompiling: boolean = false;
  private compilePending: boolean = false;
  private compileTimer: number = -1;
  private fileWatchTimer: number = -1;
  private preferencesTimer: number = -1;
  private isCheckingFiles: boolean = false;
  private fileSignatures: Map<string, string> = new Map<string, string>();
  private dirtyPaths: Set<string> = new Set<string>();
  private preferenceStore: preferences.Preferences | null = null;

  async aboutToAppear(): Promise<void> {
    await this.restoreSession();
  }

  aboutToDisappear(): void {
    if (this.compileTimer >= 0) {
      clearTimeout(this.compileTimer);
      this.compileTimer = -1;
    }
    if (this.preferencesTimer >= 0) {
      clearTimeout(this.preferencesTimer);
      this.preferencesTimer = -1;
    }
    this.saveSession();
    this.stopFileWatch();
  }

  private async restoreSession(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        return;
      }
      this.preferenceStore = await preferences.getPreferences(
        context,
        'harmony-sass-session'
      );
      const savedSyntax: preferences.ValueType =
        await this.preferenceStore.get('syntax', this.syntax);
      const savedStyle: preferences.ValueType =
        await this.preferenceStore.get('outputStyle', this.outputStyle);
      const savedLoadPaths: preferences.ValueType =
        await this.preferenceStore.get('loadPaths', '');
      const savedSourceMap: preferences.ValueType =
        await this.preferenceStore.get('sourceMap', false);
      const savedAutoCompile: preferences.ValueType =
        await this.preferenceStore.get('autoCompile', false);
      const emptySyntaxUris: string[] = [];
      const emptySyntaxValues: string[] = [];
      const savedSyntaxUrisValue: preferences.ValueType =
        await this.preferenceStore.get('syntaxUris', emptySyntaxUris);
      const savedSyntaxValuesValue: preferences.ValueType =
        await this.preferenceStore.get('syntaxValues', emptySyntaxValues);
      if (typeof savedSyntax === 'string' && this.isSupportedSyntax(savedSyntax)) {
        this.syntax = savedSyntax;
      }
      if (typeof savedStyle === 'string' && this.isSupportedOutputStyle(savedStyle)) {
        this.outputStyle = savedStyle;
      }
      if (typeof savedLoadPaths === 'string') {
        this.loadPathsText = savedLoadPaths;
      }
      if (typeof savedSourceMap === 'boolean') {
        this.sourceMapEnabled = savedSourceMap;
      }
      if (typeof savedAutoCompile === 'boolean') {
        this.autoCompile = savedAutoCompile;
      }

      const emptyUris: string[] = [];
      const savedUrisValue: preferences.ValueType =
        await this.preferenceStore.get('projectUris', emptyUris);
      const savedActiveUriValue: preferences.ValueType =
        await this.preferenceStore.get('activeUri', '');
      const savedUris: string[] = [];
      if (Array.isArray(savedUrisValue)) {
        const uriValues: string[] = savedUrisValue as string[];
        for (const value of uriValues) {
          if (savedUris.length >= MAX_PROJECT_FILES) {
            break;
          }
          if (typeof value === 'string' &&
            value.length > 0 &&
            !savedUris.includes(value)) {
            savedUris.push(value);
          }
        }
      }
      const restoredFiles: SassEditorFile[] = [];
      const savedSyntaxUris: string[] = Array.isArray(savedSyntaxUrisValue)
        ? savedSyntaxUrisValue as string[]
        : [];
      const savedSyntaxValues: string[] = Array.isArray(savedSyntaxValuesValue)
        ? savedSyntaxValuesValue as string[]
        : [];
      for (const uri of savedUris) {
        try {
          const contents: string = await fileIo.readText(uri);
          const path: string = SassProject.fileNameFromUri(uri);
          let restoredSyntax: string = SassProject.syntaxForPath(path);
          const syntaxIndex: number = savedSyntaxUris.indexOf(uri);
          if (syntaxIndex >= 0 &&
            syntaxIndex < savedSyntaxValues.length &&
            this.isSupportedSyntax(savedSyntaxValues[syntaxIndex])) {
            restoredSyntax = savedSyntaxValues[syntaxIndex];
          }
          restoredFiles.push({
            path,
            uri,
            contents,
            syntax: restoredSyntax
          });
        } catch (_) {
        }
      }
      if (restoredFiles.length > 0) {
        const rebasedFiles: SassEditorFile[] =
          SassProject.rebaseUriFiles(restoredFiles);
        const editableFiles: SassEditorFile[] =
          SassProject.editableStylesheetFiles(rebasedFiles);
        if (editableFiles.length > 0) {
          this.files = rebasedFiles;
          let activeFile: SassEditorFile = editableFiles[0];
          if (typeof savedActiveUriValue === 'string') {
            for (const file of editableFiles) {
              if (file.uri === savedActiveUriValue) {
                activeFile = file;
                break;
              }
            }
          }
          this.activePath = activeFile.path;
          this.source = activeFile.contents;
          this.syntax = activeFile.syntax;
          this.statusMessage = `已恢复项目 · ${this.files.length} 个文件`;
          await this.rememberFileSignatures();
        }
      }
      if (this.autoCompile) {
        this.startFileWatch();
      }
    } catch (_) {
      this.preferenceStore = null;
    }
  }

  private isSupportedSyntax(value: string): boolean {
    return value === 'scss' || value === 'indented' || value === 'css';
  }

  private isSupportedOutputStyle(value: string): boolean {
    return value === 'expanded' || value === 'compressed';
  }

  private scheduleSessionSave(): void {
    if (this.preferenceStore === null) {
      return;
    }
    if (this.preferencesTimer >= 0) {
      clearTimeout(this.preferencesTimer);
    }
    this.preferencesTimer = setTimeout((): void => {
      this.preferencesTimer = -1;
      this.saveSession();
    }, 250);
  }

  private async saveSession(): Promise<void> {
    if (this.preferenceStore === null) {
      return;
    }
    try {
      const projectUris: string[] = [];
      const syntaxUris: string[] = [];
      const syntaxValues: string[] = [];
      for (const file of this.files) {
        if (file.uri.length > 0 &&
          !projectUris.includes(file.uri) &&
          projectUris.length < MAX_PROJECT_FILES) {
          projectUris.push(file.uri);
          syntaxUris.push(file.uri);
          syntaxValues.push(file.syntax);
        }
      }
      await this.preferenceStore.put('syntax', this.syntax);
      await this.preferenceStore.put('outputStyle', this.outputStyle);
      await this.preferenceStore.put('loadPaths', this.loadPathsText);
      await this.preferenceStore.put('sourceMap', this.sourceMapEnabled);
      await this.preferenceStore.put('autoCompile', this.autoCompile);
      await this.preferenceStore.put('projectUris', projectUris);
      await this.preferenceStore.put('activeUri', this.activeFile().uri);
      await this.preferenceStore.put('syntaxUris', syntaxUris);
      await this.preferenceStore.put('syntaxValues', syntaxValues);
      await this.preferenceStore.flush();
    } catch (_) {
    }
  }

  private compile(): void {
    if (!this.runtimeReady) {
      this.statusMessage = '正在初始化 Dart Sass 编译器…';
      return;
    }
    if (this.isCompiling) {
      this.compilePending = true;
      return;
    }
    this.isCompiling = true;
    this.compileWithDartSass();
  }

  private async initializeRuntime(): Promise<void> {
    if (this.runtimeReady) {
      return;
    }
    try {
      const payload: string = await this.controller.runJavaScript(
        DartSassRuntime.createMetadataScript()
      );
      const metadata: SassRuntimeMetadata =
        DartSassRuntime.parseMetadata(payload);
      if (!metadata.info.startsWith('dart-sass\t') ||
        metadata.version.length === 0 ||
        !metadata.compilerModes.includes('async')) {
        throw new Error('加载的编译器不是有效的 Dart Sass 运行时。');
      }
      this.runtimeVersion = metadata.version;
      this.runtimeReady = true;
      this.compile();
    } catch (error) {
      this.isSuccessful = false;
      this.statusMessage = `Dart Sass 初始化失败 · ${(error as Error).message}`;
    }
  }

  private async waitForAsyncJob(startScript: string): Promise<string> {
    const startPayload: string =
      await this.controller.runJavaScript(startScript);
    const started: SassAsyncJobStartResponse =
      DartSassRuntime.parseAsyncJobStartResponse(startPayload);
    if (started.jobId.length === 0) {
      throw new Error('Dart Sass 未返回异步编译任务编号。');
    }

    const deadline: number = Date.now() + 120000;
    while (Date.now() < deadline) {
      const pollPayload: string = await this.controller.runJavaScript(
        DartSassRuntime.createAsyncJobPollScript(started.jobId)
      );
      const polled: SassAsyncJobPollResponse =
        DartSassRuntime.parseAsyncJobPollResponse(pollPayload);
      if (polled.state === 'complete') {
        if (polled.payload === undefined || polled.payload.length === 0) {
          throw new Error('Dart Sass 异步编译未返回结果。');
        }
        return polled.payload;
      }
      if (polled.state !== 'pending') {
        throw new Error(polled.message ?? 'Dart Sass 异步编译任务失败。');
      }
      await new Promise<void>((resolve: () => void): void => {
        setTimeout((): void => resolve(), 8);
      });
    }
    throw new Error('Dart Sass 异步编译超时。');
  }

  private async compileWithDartSass(): Promise<void> {
    try {
      this.syncActiveSource();
      const request: SassCompileRequest = {
        source: this.source,
        entryPath: this.activePath,
        entryUri: this.activeFile().uri,
        files: SassProject.compilerFiles(this.files, this.activePath),
        loadPaths: this.loadPaths(),
        nodePackageImporter: true,
        packageEntryPointDirectory: '',
        syntax: this.syntax,
        style: this.outputStyle,
        alertAscii: false,
        alertColor: false,
        sourceMap: this.sourceMapEnabled,
        sourceMapIncludeSources: true,
        charset: true,
        quiet: false,
        quietDeps: false,
        verbose: false,
        errorCss: false,
        fatalDeprecations: [],
        futureDeprecations: [],
        silenceDeprecations: []
      };
      const script: string =
        DartSassRuntime.createAsyncProjectCompileScript(request);
      const payload: string = await this.waitForAsyncJob(script);
      const compiled: SassCompileResponse = DartSassRuntime.parseResponse(payload);
      if (compiled.ok) {
        this.result = compiled.css ?? '';
        this.showSuccessfulOutput(
          this.result,
          compiled.warnings ?? [],
          compiled.debugMessages ?? []
        );
        this.sourceMapText = compiled.sourceMap ?? '';
        this.isSuccessful = true;
        this.statusMessage = this.successMessage(compiled);
      } else {
        this.sourceMapText = '';
        this.showCompileError(
          compiled.error,
          compiled.warnings ?? [],
          compiled.debugMessages ?? []
        );
      }
    } catch (error) {
      this.result = '';
      this.displayResult = (error as Error).message;
      this.sourceMapText = '';
      this.diagnosticCount = 0;
      this.isSuccessful = false;
      this.statusMessage = '编译失败 · ' + (error as Error).message;
    } finally {
      this.isCompiling = false;
      if (this.compilePending) {
        this.compilePending = false;
        this.compile();
      }
    }
  }

  private successMessage(compiled: SassCompileResponse): string {
    const warnings: SassWarning[] = compiled.warnings ?? [];
    const debugCount: number = compiled.debugMessages?.length ?? 0;
    const loadedCount: number = compiled.loadedUrls?.length ?? 1;
    if (warnings.length === 0 && debugCount === 0) {
      return `编译成功 · Dart Sass ${compiled.version} · 已载入 ${loadedCount} 个文件`;
    }
    if (warnings.length > 0) {
      return `编译成功 · ${warnings.length} 条警告 · 完整内容已显示在输出区`;
    }
    return `编译成功 · ${debugCount} 条调试信息 · 完整内容已显示在输出区`;
  }

  private showSuccessfulOutput(
    css: string,
    warnings: SassWarning[],
    debugMessages: SassDebugMessage[]
  ): void {
    const diagnostics: string = this.formatDiagnostics(warnings, debugMessages);
    this.diagnosticCount = warnings.length + debugMessages.length;
    this.displayResult = diagnostics.length > 0
      ? `${css}\n\n----- Sass 诊断 -----\n${diagnostics}`
      : css;
  }

  private showCompileError(
    error: SassCompileError | undefined,
    warnings: SassWarning[],
    debugMessages: SassDebugMessage[]
  ): void {
    this.isSuccessful = false;
    this.result = '';
    this.diagnosticCount = warnings.length + debugMessages.length;
    if (error === undefined) {
      this.displayResult = this.formatDiagnostics(warnings, debugMessages);
      this.statusMessage = '编译失败 · Dart Sass 未返回错误详情。';
      return;
    }
    const diagnostics: string = this.formatDiagnostics(warnings, debugMessages);
    this.displayResult = diagnostics.length > 0
      ? `${error.formatted}\n\n----- Sass 诊断 -----\n${diagnostics}`
      : error.formatted;
    const location: string = error.line > 0
      ? `（第 ${error.line} 行，第 ${error.column} 列）`
      : '';
    const warningText: string = warnings.length > 0 ? ` · ${warnings.length} 条警告` : '';
    this.statusMessage = `编译失败 ${location}· ${error.message}${warningText}`;
  }

  private formatDiagnostics(
    warnings: SassWarning[],
    debugMessages: SassDebugMessage[]
  ): string {
    const messages: string[] = [];
    for (const warning of warnings) {
      const type: string = warning.deprecation
        ? warning.deprecationType !== undefined
          ? `弃用警告 ${warning.deprecationType}`
          : '弃用警告'
        : '警告';
      let message: string = `[${type}] ${warning.message}`;
      const location: string = this.formatDiagnosticLocation(warning.span);
      if (location.length > 0) {
        message += `\n${location}`;
      }
      if (warning.stack !== undefined && warning.stack.length > 0) {
        message += `\n${warning.stack}`;
      }
      messages.push(message);
    }
    for (const debugMessage of debugMessages) {
      let message: string = `[@debug] ${debugMessage.message}`;
      const location: string = this.formatDiagnosticLocation(debugMessage.span);
      if (location.length > 0) {
        message += `\n${location}`;
      }
      messages.push(message);
    }
    return messages.join('\n\n');
  }

  private formatDiagnosticLocation(span: SassSourceSpan | undefined): string {
    if (span === undefined) {
      return '';
    }
    const path: string = span.url.replace('harmony-sass:/', '');
    return `位置：${path}:${span.start.line}:${span.start.column}`;
  }

  private loadPaths(): string[] {
    return this.loadPathsText.split(',')
      .map((path: string): string => SassProject.normalizePath(path.trim()))
      .filter((path: string): boolean => path.length > 0);
  }

  private scheduleCompile(): void {
    if (!this.autoCompile || !this.runtimeReady) {
      return;
    }
    if (this.compileTimer >= 0) {
      clearTimeout(this.compileTimer);
    }
    this.compileTimer = setTimeout((): void => {
      this.compileTimer = -1;
      this.compile();
    }, 350);
  }

  private startFileWatch(): void {
    if (!this.autoCompile || this.fileWatchTimer >= 0) {
      return;
    }
    this.fileWatchTimer = setInterval((): void => {
      this.checkExternalFiles();
    }, 1200);
    this.checkExternalFiles();
  }

  private stopFileWatch(): void {
    if (this.fileWatchTimer >= 0) {
      clearInterval(this.fileWatchTimer);
      this.fileWatchTimer = -1;
    }
  }

  private async fileSignature(uri: string): Promise<string> {
    try {
      const stat: fileIo.Stat = await fileIo.stat(uri);
      return `${stat.mtime}:${stat.size}`;
    } catch (_) {
      return '';
    }
  }

  private async rememberFileSignatures(): Promise<void> {
    for (const file of this.files) {
      if (file.uri.length === 0) {
        continue;
      }
      try {
        const signature: string = await this.fileSignature(file.uri);
        if (signature.length > 0) {
          this.fileSignatures.set(file.uri, signature);
        }
      } catch (_) {
      }
    }
  }

  private async refreshFileSignature(uri: string): Promise<void> {
    if (uri.length === 0) {
      return;
    }
    try {
      const signature: string = await this.fileSignature(uri);
      if (signature.length > 0) {
        this.fileSignatures.set(uri, signature);
      } else {
        this.fileSignatures.delete(uri);
      }
    } catch (_) {
      this.fileSignatures.delete(uri);
    }
  }

  private async checkExternalFiles(): Promise<void> {
    if (!this.autoCompile || this.isCheckingFiles) {
      return;
    }
    this.isCheckingFiles = true;
    const changedPaths: string[] = [];
    const conflictPaths: string[] = [];
    const unavailablePaths: string[] = [];
    try {
      const observedFiles: SassEditorFile[] = this.files.slice();
      for (const file of observedFiles) {
        if (file.uri.length === 0) {
          continue;
        }
        try {
          const signature: string = await this.fileSignature(file.uri);
          const previous: string | undefined = this.fileSignatures.get(file.uri);
          if (signature.length === 0) {
            if (previous !== undefined && previous.length > 0) {
              unavailablePaths.push(file.path);
            }
            this.fileSignatures.set(file.uri, '');
            continue;
          }
          this.fileSignatures.set(file.uri, signature);
          if (previous === undefined || previous === signature) {
            continue;
          }
          if (this.dirtyPaths.has(file.path)) {
            conflictPaths.push(file.path);
            continue;
          }
          const contents: string = await fileIo.readText(file.uri);
          this.files = SassProject.updateContents(this.files, file.path, contents);
          if (file.path === this.activePath) {
            this.source = contents;
          }
          changedPaths.push(file.path);
        } catch (_) {
        }
      }
    } finally {
      this.isCheckingFiles = false;
    }

    if (unavailablePaths.length > 0) {
      this.isSuccessful = false;
      this.statusMessage =
        `项目文件已删除或无法访问 · ${unavailablePaths[0]} · 请重新载入项目`;
      return;
    }
    if (conflictPaths.length > 0) {
      this.isSuccessful = false;
      this.statusMessage = `检测到外部修改冲突 · ${conflictPaths[0]} 尚未保存`;
      return;
    }
    if (changedPaths.length > 0) {
      this.isSuccessful = true;
      this.statusMessage = `已重新载入外部修改 · ${changedPaths.length} 个文件`;
      this.scheduleCompile();
    }
  }

  private syncActiveSource(): void {
    this.files = SassProject.updateContents(this.files, this.activePath, this.source);
  }

  private activeFileIndex(): number {
    for (let index: number = 0; index < this.files.length; index++) {
      if (this.files[index].path === this.activePath) {
        return index;
      }
    }
    return 0;
  }

  private activeFile(): SassEditorFile {
    const index: number = this.activeFileIndex();
    return this.files[index] ?? SAMPLE_FILE;
  }

  private activeEditableFileIndex(): number {
    const editableFiles: SassEditorFile[] =
      SassProject.editableStylesheetFiles(this.files);
    for (let index: number = 0; index < editableFiles.length; index++) {
      if (editableFiles[index].path === this.activePath) {
        return index;
      }
    }
    return 0;
  }

  private fileOptions(): SelectOption[] {
    return SassProject.editableStylesheetFiles(this.files)
      .map((file: SassEditorFile): SelectOption => ({ value: file.path }));
  }

  private selectFile(index: number): void {
    const editableFiles: SassEditorFile[] =
      SassProject.editableStylesheetFiles(this.files);
    if (index < 0 || index >= editableFiles.length) {
      return;
    }
    this.syncActiveSource();
    const file: SassEditorFile = editableFiles[index];
    this.activePath = file.path;
    this.source = file.contents;
    this.syntax = file.syntax;
    this.statusMessage = `当前入口 · ${file.path}`;
    this.isSuccessful = true;
    this.scheduleSessionSave();
    this.scheduleCompile();
  }

  private async openSource(): Promise<void> {
    try {
      const uris: string[] = await this.selectDocuments(1);
      if (uris.length === 0) {
        return;
      }
      const contents: string = await fileIo.readText(uris[0]);
      const path: string = SassProject.fileNameFromUri(uris[0]);
      const file: SassEditorFile = {
        path,
        uri: uris[0],
        contents,
        syntax: SassProject.syntaxForPath(path)
      };
      this.files = [file];
      this.activePath = file.path;
      this.source = file.contents;
      this.syntax = file.syntax;
      this.result = '';
      this.displayResult = '';
      this.sourceMapText = '';
      this.diagnosticCount = 0;
      this.dirtyPaths.clear();
      this.fileSignatures.clear();
      await this.rememberFileSignatures();
      this.statusMessage = `已打开 · ${file.path}`;
      this.isSuccessful = true;
      this.scheduleSessionSave();
      this.scheduleCompile();
    } catch (error) {
      this.showActionError('打开失败', error);
    }
  }

  private async addProjectFiles(): Promise<void> {
    try {
      const selectedUris: string[] = await this.selectDocuments(500, true);
      const uris: string[] = await this.expandProjectUris(selectedUris);
      if (uris.length === 0) {
        return;
      }
      this.syncActiveSource();
      const currentFiles: SassEditorFile[] = SassProject.withoutUntouchedPlaceholder(
        this.files,
        SAMPLE_FILE.path,
        SAMPLE_FILE.contents,
        Array.from(this.dirtyPaths)
      );
      const existingUris: string[] = SassProject.uniqueUris(
        currentFiles.map((file: SassEditorFile): string => file.uri)
      );
      const combinedUris: string[] = SassProject.uniqueUris(existingUris.concat(uris));
      let virtualFileCount: number = 0;
      for (const file of currentFiles) {
        if (file.uri.length === 0) {
          virtualFileCount++;
        }
      }
      if (combinedUris.length + virtualFileCount > MAX_PROJECT_FILES) {
        throw new Error(`项目最多支持 ${MAX_PROJECT_FILES} 个项目文件。`);
      }
      const dirtyUris: Set<string> = new Set<string>();
      const dirtyVirtualPaths: Set<string> = new Set<string>();
      for (const file of currentFiles) {
        if (!this.dirtyPaths.has(file.path)) {
          continue;
        }
        if (file.uri.length > 0) {
          dirtyUris.add(file.uri);
        } else {
          dirtyVirtualPaths.add(file.path);
        }
      }
      const paths: string[] = SassProject.deriveVirtualPaths(uris);
      const incoming: SassEditorFile[] = [];
      for (let index: number = 0; index < uris.length; index++) {
        const contents: string = await fileIo.readText(uris[index]);
        incoming.push({
          path: paths[index],
          uri: uris[index],
          contents,
          syntax: SassProject.syntaxForPath(paths[index])
        });
      }
      const activeUri: string = this.activeFile().uri;
      this.files = SassProject.rebaseUriFiles(SassProject.mergeFiles(currentFiles, incoming));
      const rebasedDirtyPaths: Set<string> = new Set<string>();
      for (const file of this.files) {
        if ((file.uri.length > 0 && dirtyUris.has(file.uri)) ||
          (file.uri.length === 0 && dirtyVirtualPaths.has(file.path))) {
          rebasedDirtyPaths.add(file.path);
        }
      }
      this.dirtyPaths = rebasedDirtyPaths;
      const editableFiles: SassEditorFile[] =
        SassProject.editableStylesheetFiles(this.files);
      if (editableFiles.length === 0) {
        throw new Error('项目中没有可编译的 Sass/CSS 文件。');
      }
      let activeFile: SassEditorFile = editableFiles[0];
      for (const file of editableFiles) {
        if ((activeUri.length > 0 && file.uri === activeUri) ||
          file.path === this.activePath) {
          activeFile = file;
          break;
        }
      }
      this.activePath = activeFile.path;
      this.source = activeFile.contents;
      this.syntax = activeFile.syntax;
      this.statusMessage = `已载入项目 · 共 ${this.files.length} 个项目文件`;
      this.isSuccessful = true;
      await this.rememberFileSignatures();
      this.scheduleSessionSave();
      this.scheduleCompile();
    } catch (error) {
      this.showActionError('载入项目失败', error);
    }
  }

  private async selectDocuments(
    maxSelectNumber: number,
    allowFolders: boolean = false
  ): Promise<string[]> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('无法获取当前窗口上下文。');
    }
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.fileSuffixFilters = allowFolders
      ? ['Sass/CSS/Package|.scss,.sass,.css,.json']
      : ['Sass/CSS|.scss,.sass,.css'];
    options.maxSelectNumber = maxSelectNumber;
    if (allowFolders) {
      options.selectMode = picker.DocumentSelectMode.MIXED;
    }
    return await documentPicker.select(options);
  }

  private async expandProjectUris(selectedUris: string[]): Promise<string[]> {
    const expanded: string[] = [];
    const seen: Set<string> = new Set<string>();
    for (const uri of selectedUris) {
      const stat: fileIo.Stat = await fileIo.stat(uri);
      if (!stat.isDirectory()) {
        const fileName: string = SassProject.fileNameFromUri(uri);
        if (SassProject.isProjectFilePath(fileName) && !seen.has(uri)) {
          seen.add(uri);
          expanded.push(uri);
        }
        if (expanded.length > MAX_PROJECT_FILES) {
          throw new Error(`一次最多载入 ${MAX_PROJECT_FILES} 个项目文件。`);
        }
        continue;
      }
      let relativePaths: string[] = [];
      try {
        relativePaths = await fileIo.listFile(uri, {
          recursion: true,
          listNum: MAX_PROJECT_FILES + 1,
          filter: {
            suffix: ['.scss', '.sass', '.css', '.json']
          }
        });
      } catch (error) {
        throw new Error(
          `系统未允许递归读取所选文件夹，请改用多选文件方式。${(error as Error).message}`
        );
      }
      relativePaths.sort();
      for (const relativePath of relativePaths) {
        const normalized: string = SassProject.normalizePath(relativePath);
        if (SassProject.isProjectFilePath(normalized)) {
          const childUri: string = this.joinDocumentUri(uri, normalized);
          if (!seen.has(childUri)) {
            seen.add(childUri);
            expanded.push(childUri);
          }
          if (expanded.length > MAX_PROJECT_FILES) {
            throw new Error(`一次最多载入 ${MAX_PROJECT_FILES} 个项目文件。`);
          }
        }
      }
    }
    return expanded;
  }

  private joinDocumentUri(directoryUri: string, relativePath: string): string {
    const root: string = directoryUri.endsWith('/')
      ? directoryUri.slice(0, directoryUri.length - 1)
      : directoryUri;
    const encodedSegments: string[] = [];
    for (const segment of SassProject.normalizePath(relativePath).split('/')) {
      let decoded: string = segment;
      try {
        decoded = decodeURIComponent(segment);
      } catch (_) {
      }
      encodedSegments.push(encodeURIComponent(decoded));
    }
    return `${root}/${encodedSegments.join('/')}`;
  }

  private async saveSource(forcePicker: boolean = false): Promise<void> {
    try {
      this.syncActiveSource();
      if (forcePicker) {
        const previousUri: string = this.activeFile().uri;
        const uri: string = await this.chooseSaveUri(this.activePath, 'Sass/CSS|.scss,.sass,.css');
        if (uri.length === 0) {
          return;
        }
        this.files = SassProject.replaceUri(this.files, this.activePath, uri);
        await this.writeText(uri, this.source);
        this.dirtyPaths.delete(this.activePath);
        if (previousUri.length > 0 && previousUri !== uri) {
          this.fileSignatures.delete(previousUri);
        }
        await this.refreshFileSignature(uri);
        this.statusMessage = `已另存为 · ${this.activePath}`;
        this.isSuccessful = true;
        this.scheduleSessionSave();
        return;
      }

      let activeUri: string = this.activeFile().uri;
      if (activeUri.length === 0) {
        activeUri = await this.chooseSaveUri(this.activePath, 'Sass/CSS|.scss,.sass,.css');
        if (activeUri.length === 0) {
          return;
        }
        this.files = SassProject.replaceUri(this.files, this.activePath, activeUri);
      }

      let savedCount: number = 0;
      for (const file of this.files) {
        if (file.uri.length === 0 ||
          (file.path !== this.activePath && !this.dirtyPaths.has(file.path))) {
          continue;
        }
        await this.writeText(file.uri, file.contents);
        this.dirtyPaths.delete(file.path);
        await this.refreshFileSignature(file.uri);
        savedCount++;
      }
      this.statusMessage = savedCount > 1
        ? `已保存全部修改 · ${savedCount} 个文件`
        : `已保存 · ${this.activePath}`;
      this.isSuccessful = true;
      this.scheduleSessionSave();
    } catch (error) {
      this.showActionError('保存失败', error);
    }
  }

  private async exportCss(): Promise<void> {
    if (!this.runtimeReady) {
      this.statusMessage = 'Dart Sass 编译器尚未初始化完成。';
      this.isSuccessful = false;
      return;
    }
    try {
      const compiled: SassBatchCompileResponse =
        await this.compileProjectEntries(this.sourceMapEnabled);
      if (!compiled.ok) {
        this.showBatchCompileErrors(compiled);
        return;
      }
      const entryPaths: string[] = compiled.results.map(
        (entry: SassBatchCompileResult): string => entry.entryPath
      );
      const cssFileNames: string[] = SassProject.outputFileNames(entryPaths, '.css');
      if (!this.sourceMapEnabled) {
        const uris: string[] = await this.chooseSaveUris(cssFileNames, 'CSS|.css');
        if (uris.length === 0) {
          return;
        }
        if (uris.length !== compiled.results.length) {
          throw new Error('系统返回的保存位置数量与编译入口数量不一致。');
        }
        for (let index: number = 0; index < compiled.results.length; index++) {
          await this.writeText(uris[index], compiled.results[index].css ?? '');
        }
        this.statusMessage = compiled.results.length > 1
          ? `CSS 已批量导出 · ${compiled.results.length} 个入口`
          : `CSS 已导出 · ${cssFileNames[0]}`;
        this.isSuccessful = true;
        return;
      }

      const mapFileNames: string[] =
        SassProject.outputFileNames(entryPaths, '.css.map');
      const fileNames: string[] = [];
      for (let index: number = 0; index < cssFileNames.length; index++) {
        fileNames.push(cssFileNames[index]);
        fileNames.push(mapFileNames[index]);
      }
      const uris: string[] = await this.chooseSaveUris(fileNames, '');
      if (uris.length === 0) {
        return;
      }
      if (uris.length !== compiled.results.length * 2) {
        throw new Error('系统返回的保存位置数量与编译入口数量不一致。');
      }
      const entries: SassExportFinalizeEntry[] = [];
      for (let index: number = 0; index < compiled.results.length; index++) {
        entries.push({
          css: compiled.results[index].css ?? '',
          sourceMap: compiled.results[index].sourceMap ?? '',
          cssFileName: SassProject.fileNameFromUri(uris[index * 2]),
          sourceMapFileName: SassProject.fileNameFromUri(uris[index * 2 + 1]),
          cssUri: uris[index * 2],
          sourceMapUri: uris[index * 2 + 1]
        });
      }
      const finalized: SassExportFinalizeResponse =
        await this.finalizeExports(entries);
      if (finalized.results.length !== compiled.results.length) {
        throw new Error('Dart Sass 返回的导出文件数量与编译入口数量不一致。');
      }
      for (let index: number = 0; index < finalized.results.length; index++) {
        await this.writeText(uris[index * 2], finalized.results[index].css);
        await this.writeText(
          uris[index * 2 + 1],
          finalized.results[index].sourceMap
        );
      }
      this.statusMessage = compiled.results.length > 1
        ? `CSS 与 Source Map 已批量导出 · ${compiled.results.length} 个入口`
        : `CSS 与 Source Map 已导出 · ${cssFileNames[0]}`;
      this.isSuccessful = true;
    } catch (error) {
      this.showActionError('导出 CSS 失败', error);
    }
  }

  private async exportSourceMap(): Promise<void> {
    if (!this.sourceMapEnabled) {
      this.statusMessage = '请先启用 Source Map。';
      this.isSuccessful = false;
      return;
    }
    try {
      const compiled: SassBatchCompileResponse = await this.compileProjectEntries(true);
      if (!compiled.ok) {
        this.showBatchCompileErrors(compiled);
        return;
      }
      const entryPaths: string[] = compiled.results.map(
        (entry: SassBatchCompileResult): string => entry.entryPath
      );
      const fileNames: string[] = SassProject.outputFileNames(entryPaths, '.css.map');
      const uris: string[] = await this.chooseSaveUris(fileNames, 'Source Map|.map');
      if (uris.length === 0) {
        return;
      }
      if (uris.length !== compiled.results.length) {
        throw new Error('系统返回的保存位置数量与编译入口数量不一致。');
      }
      const entries: SassExportFinalizeEntry[] = [];
      for (let index: number = 0; index < compiled.results.length; index++) {
        const sourceMapFileName: string =
          SassProject.fileNameFromUri(uris[index]);
        const cssFileName: string = sourceMapFileName.endsWith('.map')
          ? sourceMapFileName.slice(0, sourceMapFileName.length - 4)
          : SassProject.outputFileNames(
            [compiled.results[index].entryPath],
            '.css'
          )[0];
        entries.push({
          css: compiled.results[index].css ?? '',
          sourceMap: compiled.results[index].sourceMap ?? '',
          cssFileName,
          sourceMapFileName,
          cssUri: '',
          sourceMapUri: uris[index]
        });
      }
      const finalized: SassExportFinalizeResponse =
        await this.finalizeExports(entries);
      if (finalized.results.length !== compiled.results.length) {
        throw new Error('Dart Sass 返回的导出文件数量与编译入口数量不一致。');
      }
      for (let index: number = 0; index < finalized.results.length; index++) {
        await this.writeText(uris[index], finalized.results[index].sourceMap);
      }
      this.statusMessage = compiled.results.length > 1
        ? `Source Map 已批量导出 · ${compiled.results.length} 个入口`
        : `Source Map 已导出 · ${fileNames[0]}`;
      this.isSuccessful = true;
    } catch (error) {
      this.showActionError('导出 Source Map 失败', error);
    }
  }

  private async compileProjectEntries(sourceMap: boolean): Promise<SassBatchCompileResponse> {
    this.syncActiveSource();
    const entryPaths: string[] = SassProject.entryPaths(this.files, this.activePath);
    const request: SassBatchCompileRequest = {
      entryPaths,
      files: SassProject.compilerFiles(this.files, ''),
      loadPaths: this.loadPaths(),
      nodePackageImporter: true,
      packageEntryPointDirectory: '',
      style: this.outputStyle,
      alertAscii: false,
      alertColor: false,
      sourceMap,
      sourceMapIncludeSources: true,
      charset: true,
      quiet: false,
      quietDeps: false,
      verbose: false,
      errorCss: true,
      stopOnError: false,
      fatalDeprecations: [],
      futureDeprecations: [],
      silenceDeprecations: []
    };
    const script: string =
      DartSassRuntime.createAsyncBatchCompileScript(request);
    const payload: string = await this.waitForAsyncJob(script);
    return DartSassRuntime.parseBatchResponse(payload);
  }

  private async finalizeExports(
    entries: SassExportFinalizeEntry[]
  ): Promise<SassExportFinalizeResponse> {
    const request: SassExportFinalizeRequest = {
      style: this.outputStyle,
      sourceMapUrls: 'relative',
      embedSourceMap: false,
      entries
    };
    const script: string =
      DartSassRuntime.createFinalizeExportsScript(request);
    const payload: string = await this.controller.runJavaScript(script);
    return DartSassRuntime.parseFinalizeExportsResponse(payload);
  }

  private showBatchCompileErrors(compiled: SassBatchCompileResponse): void {
    const messages: string[] = [];
    let diagnosticCount: number = 0;
    for (const entry of compiled.results) {
      if (entry.ok) {
        continue;
      }
      const errorText: string = entry.error?.formatted ??
        entry.error?.message ??
        'Dart Sass 未返回错误详情。';
      const diagnostics: string = this.formatDiagnostics(
        entry.warnings ?? [],
        entry.debugMessages ?? []
      );
      diagnosticCount += (entry.warnings?.length ?? 0) +
        (entry.debugMessages?.length ?? 0);
      messages.push(
        diagnostics.length > 0
          ? `===== ${entry.entryPath} =====\n${errorText}\n\n${diagnostics}`
          : `===== ${entry.entryPath} =====\n${errorText}`
      );
    }
    this.result = '';
    this.sourceMapText = '';
    this.diagnosticCount = diagnosticCount;
    this.displayResult = messages.join('\n\n');
    this.isSuccessful = false;
    const failedCount: number = messages.length;
    this.statusMessage = `批量编译失败 · ${failedCount} 个入口存在错误`;
  }

  private async chooseSaveUri(fileName: string, suffixChoice: string): Promise<string> {
    const uris: string[] = await this.chooseSaveUris([fileName], suffixChoice);
    return uris.length > 0 ? uris[0] : '';
  }

  private async chooseSaveUris(
    fileNames: string[],
    suffixChoice: string
  ): Promise<string[]> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('无法获取当前窗口上下文。');
    }
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
    options.newFileNames = fileNames;
    if (suffixChoice.length > 0) {
      options.fileSuffixChoices = [suffixChoice];
    }
    return await documentPicker.save(options);
  }

  private async writeText(uri: string, text: string): Promise<void> {
    let file: fileIo.File | undefined = undefined;
    try {
      file = await fileIo.open(
        uri,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC
      );
      await fileIo.write(file.fd, text);
    } catch (error) {
      throw new Error((error as Error).message);
    } finally {
      if (file !== undefined) {
        try {
          await fileIo.close(file);
        } catch (_) {
        }
      }
    }
  }

  private async copyCss(): Promise<void> {
    if (this.result.length === 0 || !this.isSuccessful) {
      this.statusMessage = '没有可复制的 CSS，请先成功编译。';
      this.isSuccessful = false;
      return;
    }
    try {
      const data: pasteboard.PasteData = pasteboard.createData(
        pasteboard.MIMETYPE_TEXT_PLAIN,
        this.result
      );
      await pasteboard.getSystemPasteboard().setData(data);
      this.statusMessage = 'CSS 已复制到剪贴板。';
      this.isSuccessful = true;
    } catch (error) {
      this.showActionError('复制失败', error);
    }
  }

  private loadSample(): void {
    this.files = [SAMPLE_FILE];
    this.activePath = SAMPLE_FILE.path;
    this.source = SAMPLE_SCSS;
    this.syntax = 'scss';
    this.result = '';
    this.displayResult = '';
    this.sourceMapText = '';
    this.diagnosticCount = 0;
    this.dirtyPaths.clear();
    this.fileSignatures.clear();
    this.statusMessage = '已载入示例。';
    this.isSuccessful = true;
    this.scheduleSessionSave();
    this.compile();
  }

  private showActionError(action: string, error: Object): void {
    this.isSuccessful = false;
    this.statusMessage = `${action} · ${(error as Error).message}`;
  }

  private handleKeyEvent(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down ||
      event.getModifierKeyState === undefined ||
      !event.getModifierKeyState(['ctrl'])) {
      return false;
    }
    if (event.keyCode === KeyCode.KEYCODE_O) {
      this.openSource();
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_S) {
      const saveAs: boolean = event.getModifierKeyState(['shift']);
      this.saveSource(saveAs);
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_ENTER) {
      this.compile();
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row() {
          Column({ space: 4 }) {
            Text('Harmony Sass').fontSize(26).fontWeight(FontWeight.Bold).fontColor('#152033')
            Text(`鸿蒙 PC 原生 Sass 编译器 · Dart Sass ${this.runtimeVersion}`)
              .fontSize(14).fontColor('#667085')
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Button('载入示例')
            .onClick((): void => this.loadSample())
            .backgroundColor('#EDF4FF').fontColor('#0A5FD0').margin({ right: 12 })
          Button('编译 CSS').onClick((): void => this.compile()).backgroundColor('#0A7BFF')
        }
        .width('100%').padding({ left: 28, right: 28, top: 22, bottom: 12 })

        Row({ space: 8 }) {
          Button('打开').onClick((): void => { this.openSource(); }).height(34)
          Button('添加项目文件').onClick((): void => { this.addProjectFiles(); }).height(34)
          Select(this.fileOptions())
            .selected(this.activeEditableFileIndex())
            .value(this.activePath)
            .onSelect((index: number): void => this.selectFile(index))
            .width(190).height(34)
          Button('保存').onClick((): void => { this.saveSource(); }).height(34)
          Button('另存为').onClick((): void => { this.saveSource(true); }).height(34)
          Blank().layoutWeight(1)
          Button('复制 CSS').onClick((): void => { this.copyCss(); }).height(34)
          Button('导出 CSS').onClick((): void => { this.exportCss(); }).height(34)
          Button('导出 Map').onClick((): void => { this.exportSourceMap(); }).height(34)
        }
        .width('100%').padding({ left: 28, right: 28, bottom: 8 })

        Row({ space: 10 }) {
          Text('语法').fontSize(13).fontColor('#667085')
          Select([{ value: 'SCSS' }, { value: 'Sass' }, { value: 'CSS' }])
            .selected(this.syntax === 'indented' ? 1 : this.syntax === 'css' ? 2 : 0)
            .onSelect((index: number): void => {
              this.syntax = index === 1 ? 'indented' : index === 2 ? 'css' : 'scss';
              this.files = SassProject.updateSyntax(this.files, this.activePath, this.syntax);
              this.scheduleSessionSave();
              this.scheduleCompile();
            })
            .width(92).height(32)
          Text('输出').fontSize(13).fontColor('#667085')
          Select([{ value: '展开' }, { value: '压缩' }])
            .selected(this.outputStyle === 'compressed' ? 1 : 0)
            .onSelect((index: number): void => {
              this.outputStyle = index === 1 ? 'compressed' : 'expanded';
              this.scheduleSessionSave();
              this.scheduleCompile();
            })
            .width(92).height(32)
          TextInput({ text: this.loadPathsText, placeholder: '载入路径，用逗号分隔' })
            .onChange((value: string): void => {
              this.loadPathsText = value;
              this.scheduleSessionSave();
              this.scheduleCompile();
            })
            .width(210).height(32).fontSize(13)
          Text('Source Map').fontSize(13).fontColor('#667085')
          Toggle({ type: ToggleType.Switch, isOn: this.sourceMapEnabled })
            .onChange((isOn: boolean): void => {
              this.sourceMapEnabled = isOn;
              this.scheduleSessionSave();
              this.scheduleCompile();
            })
          Text('自动编译').fontSize(13).fontColor('#667085')
          Toggle({ type: ToggleType.Switch, isOn: this.autoCompile })
            .onChange((isOn: boolean): void => {
              this.autoCompile = isOn;
              if (isOn) {
                this.startFileWatch();
                this.scheduleCompile();
              } else {
                this.stopFileWatch();
              }
              this.scheduleSessionSave();
            })
          Blank().layoutWeight(1)
          Text(`${this.files.length} 个文件`).fontSize(13).fontColor('#667085')
        }
        .width('100%').padding({ left: 28, right: 28, bottom: 10 })

        Text(this.statusMessage).width('100%').padding({ left: 28, right: 28, bottom: 12 })
          .fontSize(13).fontColor(this.isSuccessful ? '#16803C' : '#B42318')
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 16 }) {
          Column({ space: 10 }) {
            Text(`SCSS 输入 · ${this.activePath}`).fontWeight(FontWeight.Medium).fontColor('#344054')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            TextArea({ text: this.source, placeholder: '在此粘贴 Sass/SCSS/CSS…' })
              .layoutWeight(1).width('100%').fontSize(15).fontFamily('monospace')
              .backgroundColor('#FFFFFF').border({ width: 1, color: '#D0D5DD', radius: 8 })
              .onChange((value: string): void => {
                this.source = value;
                this.syncActiveSource();
                this.dirtyPaths.add(this.activePath);
                this.scheduleCompile();
              })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1).height('100%')

          Column({ space: 10 }) {
            Text(this.isSuccessful
              ? this.diagnosticCount > 0
                ? `CSS 输出 · ${this.diagnosticCount} 条诊断`
                : 'CSS 输出'
              : '编译错误')
              .fontWeight(FontWeight.Medium).fontColor('#344054')
            TextArea({ text: this.displayResult, placeholder: '编译结果将显示在这里' })
              .layoutWeight(1).width('100%').fontSize(15).fontFamily('monospace')
              .backgroundColor('#F9FAFB').border({ width: 1, color: '#D0D5DD', radius: 8 })
              .enabled(false)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1).height('100%')
        }
        .layoutWeight(1).width('100%').padding({ left: 28, right: 28, bottom: 24 })
      }
      .width('100%').height('100%').backgroundColor('#F4F7FB')

      Web({
        src: $rawfile('sass-runtime.html'),
        controller: this.controller
      })
        .javaScriptAccess(true)
        .width(1)
        .height(1)
        .opacity(0)
        .enabled(false)
        .onPageEnd((): void => {
          this.initializeRuntime();
        })
    }
    .width('100%').height('100%').backgroundColor('#F4F7FB')
    .focusable(true)
    .onKeyEvent((event: KeyEvent): boolean => this.handleKeyEvent(event))
  }
}
