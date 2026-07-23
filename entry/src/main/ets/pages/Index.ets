import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { uri } from '@kit.ArkTS';
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
import {
  SassFileRename,
  SassWorkspace
} from '../compiler/SassWorkspace';

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
const FILE_PICKER_MAX_FILES: number = 500;
const FILE_READ_BATCH_SIZE: number = 64;
const WATCH_INTERVAL_MS: number = 1200;
const DIRECTORY_RESCAN_INTERVAL_MS: number = 5000;
const RESUME_GAP_MS: number = 10000;

interface ProjectSelectionExpansion {
  uris: string[];
  directoryUris: string[];
}

interface DirectoryRefreshResult {
  addedFiles: SassEditorFile[];
  scanSucceeded: boolean;
}

interface RecentAddedFile {
  observedAt: number;
}

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
  @State private sourceMapIncludeSources: boolean = true;
  @State private sourceMapUrls: string = 'relative';
  @State private embedSourceMap: boolean = false;
  @State private autoCompile: boolean = false;
  @State private autoBatchCompile: boolean = true;
  @State private charsetEnabled: boolean = true;
  @State private alertAsciiEnabled: boolean = false;
  @State private alertColorEnabled: boolean = false;
  @State private quietEnabled: boolean = false;
  @State private quietDepsEnabled: boolean = false;
  @State private verboseEnabled: boolean = false;
  @State private errorCssEnabled: boolean = false;
  @State private stopOnError: boolean = false;
  @State private fatalDeprecationsText: string = '';
  @State private futureDeprecationsText: string = '';
  @State private silenceDeprecationsText: string = '';
  @State private advancedOptionsVisible: boolean = false;
  @State private runtimeVersion: string = '1.101.6';
  @State private statusMessage: string = '准备就绪：输入 SCSS 后点击“编译”。';
  @State private isSuccessful: boolean = true;
  @State private diagnosticCount: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  private runtimeReady: boolean = false;
  private isCompiling: boolean = false;
  private compilePending: boolean = false;
  private compilePendingBatch: boolean = false;
  private compilePendingFullBatch: boolean = false;
  private pendingBatchEntryPaths: Set<string> = new Set<string>();
  private activeBatchEntryPaths: string[] = [];
  private pendingChangedPaths: Set<string> = new Set<string>();
  private pendingFullCompile: boolean = false;
  private compileTimer: number = -1;
  private fileWatchTimer: number = -1;
  private preferencesTimer: number = -1;
  private isCheckingFiles: boolean = false;
  private fileSignatures: Map<string, string> = new Map<string, string>();
  private unavailableCounts: Map<string, number> = new Map<string, number>();
  private recentAddedFiles: Map<string, RecentAddedFile> =
    new Map<string, RecentAddedFile>();
  private dirtyPaths: Set<string> = new Set<string>();
  private projectDirectoryUris: string[] = [];
  private dependencyEntries: Map<string, Set<string>> =
    new Map<string, Set<string>>();
  private batchResults: Map<string, SassBatchCompileResult> =
    new Map<string, SassBatchCompileResult>();
  private outputDirectoryPath: string = '';
  private generatedOutputs: Map<string, string[]> =
    new Map<string, string[]>();
  private lastWatchCheckAt: number = Date.now();
  private lastDirectoryScanAt: number = 0;
  private activeAsyncJobIds: Set<string> = new Set<string>();
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
    this.releasePendingAsyncJobs();
  }

  onPageShow(): void {
    if (this.autoCompile) {
      this.lastWatchCheckAt = 0;
      this.startFileWatch();
      this.checkExternalFiles();
    }
  }

  onPageHide(): void {
    this.scheduleSessionSave();
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
      const savedAutoBatchCompile: preferences.ValueType =
        await this.preferenceStore.get('autoBatchCompile', true);
      const savedSourceMapIncludeSources: preferences.ValueType =
        await this.preferenceStore.get('sourceMapIncludeSources', true);
      const savedSourceMapUrls: preferences.ValueType =
        await this.preferenceStore.get('sourceMapUrls', 'relative');
      const savedEmbedSourceMap: preferences.ValueType =
        await this.preferenceStore.get('embedSourceMap', false);
      const savedCharset: preferences.ValueType =
        await this.preferenceStore.get('charset', true);
      const savedAlertAscii: preferences.ValueType =
        await this.preferenceStore.get('alertAscii', false);
      const savedAlertColor: preferences.ValueType =
        await this.preferenceStore.get('alertColor', false);
      const savedQuiet: preferences.ValueType =
        await this.preferenceStore.get('quiet', false);
      const savedQuietDeps: preferences.ValueType =
        await this.preferenceStore.get('quietDeps', false);
      const savedVerbose: preferences.ValueType =
        await this.preferenceStore.get('verbose', false);
      const savedErrorCss: preferences.ValueType =
        await this.preferenceStore.get('errorCss', false);
      const savedStopOnError: preferences.ValueType =
        await this.preferenceStore.get('stopOnError', false);
      const savedFatalDeprecations: preferences.ValueType =
        await this.preferenceStore.get('fatalDeprecations', '');
      const savedFutureDeprecations: preferences.ValueType =
        await this.preferenceStore.get('futureDeprecations', '');
      const savedSilenceDeprecations: preferences.ValueType =
        await this.preferenceStore.get('silenceDeprecations', '');
      const savedOutputDirectory: preferences.ValueType =
        await this.preferenceStore.get('outputDirectoryPath', '');
      const emptyGeneratedValues: string[] = [];
      const savedGeneratedEntriesValue: preferences.ValueType =
        await this.preferenceStore.get(
          'generatedOutputEntries',
          emptyGeneratedValues
        );
      const savedGeneratedCssValue: preferences.ValueType =
        await this.preferenceStore.get(
          'generatedOutputCssPaths',
          emptyGeneratedValues
        );
      const savedGeneratedMapValue: preferences.ValueType =
        await this.preferenceStore.get(
          'generatedOutputMapPaths',
          emptyGeneratedValues
        );
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
      if (typeof savedAutoBatchCompile === 'boolean') {
        this.autoBatchCompile = savedAutoBatchCompile;
      }
      if (typeof savedSourceMapIncludeSources === 'boolean') {
        this.sourceMapIncludeSources = savedSourceMapIncludeSources;
      }
      if (savedSourceMapUrls === 'relative' || savedSourceMapUrls === 'absolute') {
        this.sourceMapUrls = savedSourceMapUrls;
      }
      if (typeof savedEmbedSourceMap === 'boolean') {
        this.embedSourceMap = savedEmbedSourceMap;
      }
      if (typeof savedCharset === 'boolean') {
        this.charsetEnabled = savedCharset;
      }
      if (typeof savedAlertAscii === 'boolean') {
        this.alertAsciiEnabled = savedAlertAscii;
      }
      if (typeof savedAlertColor === 'boolean') {
        this.alertColorEnabled = savedAlertColor;
      }
      if (typeof savedQuiet === 'boolean') {
        this.quietEnabled = savedQuiet;
      }
      if (typeof savedQuietDeps === 'boolean') {
        this.quietDepsEnabled = savedQuietDeps;
      }
      if (typeof savedVerbose === 'boolean') {
        this.verboseEnabled = savedVerbose;
      }
      if (typeof savedErrorCss === 'boolean') {
        this.errorCssEnabled = savedErrorCss;
      }
      if (typeof savedStopOnError === 'boolean') {
        this.stopOnError = savedStopOnError;
      }
      if (typeof savedFatalDeprecations === 'string') {
        this.fatalDeprecationsText = savedFatalDeprecations;
      }
      if (typeof savedFutureDeprecations === 'string') {
        this.futureDeprecationsText = savedFutureDeprecations;
      }
      if (typeof savedSilenceDeprecations === 'string') {
        this.silenceDeprecationsText = savedSilenceDeprecations;
      }
      if (typeof savedOutputDirectory === 'string') {
        this.outputDirectoryPath = savedOutputDirectory;
      }
      const savedGeneratedEntries: string[] =
        Array.isArray(savedGeneratedEntriesValue)
          ? savedGeneratedEntriesValue as string[]
          : [];
      const savedGeneratedCssPaths: string[] =
        Array.isArray(savedGeneratedCssValue)
          ? savedGeneratedCssValue as string[]
          : [];
      const savedGeneratedMapPaths: string[] =
        Array.isArray(savedGeneratedMapValue)
          ? savedGeneratedMapValue as string[]
          : [];
      for (let index: number = 0;
        index < savedGeneratedEntries.length;
        index++) {
        const entryPath: string = savedGeneratedEntries[index];
        const cssPath: string = savedGeneratedCssPaths[index] ?? '';
        const mapPath: string = savedGeneratedMapPaths[index] ?? '';
        const paths: string[] = [];
        if (cssPath.length > 0) {
          paths.push(cssPath);
        }
        if (mapPath.length > 0) {
          paths.push(mapPath);
        }
        if (entryPath.length > 0 && paths.length > 0) {
          this.generatedOutputs.set(entryPath, paths);
        }
      }

      const emptyUris: string[] = [];
      const savedUrisValue: preferences.ValueType =
        await this.preferenceStore.get('projectUris', emptyUris);
      const savedDirectoryUrisValue: preferences.ValueType =
        await this.preferenceStore.get('projectDirectoryUris', emptyUris);
      const savedActiveUriValue: preferences.ValueType =
        await this.preferenceStore.get('activeUri', '');
      const savedUris: string[] = [];
      if (Array.isArray(savedUrisValue)) {
        const uriValues: string[] = savedUrisValue as string[];
        for (const value of uriValues) {
          if (typeof value === 'string' &&
            value.length > 0 &&
            !savedUris.includes(value)) {
            savedUris.push(value);
          }
        }
      }
      if (Array.isArray(savedDirectoryUrisValue)) {
        const directoryValues: string[] = savedDirectoryUrisValue as string[];
        for (const value of directoryValues) {
          if (typeof value === 'string' &&
            value.length > 0 &&
            !this.projectDirectoryUris.includes(value)) {
            this.projectDirectoryUris.push(value);
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
      const generatedEntries: string[] = [];
      const generatedCssPaths: string[] = [];
      const generatedMapPaths: string[] = [];
      for (const file of this.files) {
        if (file.uri.length > 0 &&
          !projectUris.includes(file.uri)) {
          projectUris.push(file.uri);
          syntaxUris.push(file.uri);
          syntaxValues.push(file.syntax);
        }
      }
      for (const entryPath of this.generatedOutputs.keys()) {
        const paths: string[] | undefined =
          this.generatedOutputs.get(entryPath);
        if (paths !== undefined) {
          generatedEntries.push(entryPath);
          generatedCssPaths.push(paths[0] ?? '');
          generatedMapPaths.push(paths[1] ?? '');
        }
      }
      await this.preferenceStore.put('syntax', this.syntax);
      await this.preferenceStore.put('outputStyle', this.outputStyle);
      await this.preferenceStore.put('loadPaths', this.loadPathsText);
      await this.preferenceStore.put('sourceMap', this.sourceMapEnabled);
      await this.preferenceStore.put(
        'sourceMapIncludeSources',
        this.sourceMapIncludeSources
      );
      await this.preferenceStore.put('sourceMapUrls', this.sourceMapUrls);
      await this.preferenceStore.put('embedSourceMap', this.embedSourceMap);
      await this.preferenceStore.put('autoCompile', this.autoCompile);
      await this.preferenceStore.put('autoBatchCompile', this.autoBatchCompile);
      await this.preferenceStore.put('charset', this.charsetEnabled);
      await this.preferenceStore.put('alertAscii', this.alertAsciiEnabled);
      await this.preferenceStore.put('alertColor', this.alertColorEnabled);
      await this.preferenceStore.put('quiet', this.quietEnabled);
      await this.preferenceStore.put('quietDeps', this.quietDepsEnabled);
      await this.preferenceStore.put('verbose', this.verboseEnabled);
      await this.preferenceStore.put('errorCss', this.errorCssEnabled);
      await this.preferenceStore.put('stopOnError', this.stopOnError);
      await this.preferenceStore.put(
        'fatalDeprecations',
        this.fatalDeprecationsText
      );
      await this.preferenceStore.put(
        'futureDeprecations',
        this.futureDeprecationsText
      );
      await this.preferenceStore.put(
        'silenceDeprecations',
        this.silenceDeprecationsText
      );
      await this.preferenceStore.put(
        'outputDirectoryPath',
        this.outputDirectoryPath
      );
      await this.preferenceStore.put(
        'generatedOutputEntries',
        generatedEntries
      );
      await this.preferenceStore.put(
        'generatedOutputCssPaths',
        generatedCssPaths
      );
      await this.preferenceStore.put(
        'generatedOutputMapPaths',
        generatedMapPaths
      );
      await this.preferenceStore.put('projectUris', projectUris);
      await this.preferenceStore.put(
        'projectDirectoryUris',
        this.projectDirectoryUris
      );
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
      this.compilePendingBatch = false;
      this.compilePendingFullBatch = true;
      return;
    }
    this.isCompiling = true;
    this.compileWithDartSass();
  }

  private compileBatch(entryPaths: string[] = []): void {
    if (!this.runtimeReady) {
      this.statusMessage = '正在初始化 Dart Sass 编译器…';
      return;
    }
    const requestedPaths: string[] = entryPaths
      .map((path: string): string => SassProject.normalizePath(path))
      .filter((path: string, index: number, values: string[]): boolean =>
        path.length > 0 && values.indexOf(path) === index
      );
    if (this.isCompiling) {
      this.compilePending = true;
      this.compilePendingBatch = true;
      if (requestedPaths.length === 0) {
        this.compilePendingFullBatch = true;
        this.pendingBatchEntryPaths.clear();
      } else if (!this.compilePendingFullBatch) {
        for (const path of requestedPaths) {
          this.pendingBatchEntryPaths.add(path);
        }
      }
      return;
    }
    this.isCompiling = true;
    this.activeBatchEntryPaths = requestedPaths;
    this.compileBatchWithDartSass();
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
    this.activeAsyncJobIds.add(started.jobId);

    let consumed: boolean = false;
    try {
      const deadline: number = Date.now() + 120000;
      while (Date.now() < deadline) {
        const pollPayload: string = await this.controller.runJavaScript(
          DartSassRuntime.createAsyncJobPollScript(started.jobId)
        );
        const polled: SassAsyncJobPollResponse =
          DartSassRuntime.parseAsyncJobPollResponse(pollPayload);
        if (polled.state === 'complete') {
          consumed = true;
          if (polled.payload === undefined || polled.payload.length === 0) {
            throw new Error('Dart Sass 异步编译未返回结果。');
          }
          return polled.payload;
        }
        if (polled.state !== 'pending') {
          consumed = true;
          throw new Error(polled.message ?? 'Dart Sass 异步编译任务失败。');
        }
        await new Promise<void>((resolve: () => void): void => {
          setTimeout((): void => resolve(), 8);
        });
      }
      throw new Error('Dart Sass 异步编译超时。');
    } finally {
      this.activeAsyncJobIds.delete(started.jobId);
      if (!consumed) {
        try {
          await this.controller.runJavaScript(
            DartSassRuntime.createAsyncJobReleaseScript(started.jobId)
          );
        } catch (_) {
        }
      }
    }
  }

  private async releasePendingAsyncJobs(): Promise<void> {
    const jobIds: string[] = Array.from(this.activeAsyncJobIds);
    this.activeAsyncJobIds.clear();
    for (const jobId of jobIds) {
      try {
        await this.controller.runJavaScript(
          DartSassRuntime.createAsyncJobReleaseScript(jobId)
        );
      } catch (_) {
      }
    }
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
        alertAscii: this.alertAsciiEnabled,
        alertColor: this.alertColorEnabled,
        sourceMap: this.sourceMapEnabled,
        sourceMapIncludeSources: this.sourceMapIncludeSources,
        charset: this.charsetEnabled,
        quiet: this.quietEnabled,
        quietDeps: this.quietDepsEnabled,
        verbose: this.verboseEnabled,
        errorCss: this.errorCssEnabled,
        fatalDeprecations: this.parseOptionList(this.fatalDeprecationsText),
        futureDeprecations: this.parseOptionList(this.futureDeprecationsText),
        silenceDeprecations: this.parseOptionList(this.silenceDeprecationsText)
      };
      const script: string =
        DartSassRuntime.createAsyncProjectCompileScript(request);
      const payload: string = await this.waitForAsyncJob(script);
      const compiled: SassCompileResponse = DartSassRuntime.parseResponse(payload);
      const batchResult: SassBatchCompileResult = {
        entryPath: this.activePath,
        ok: compiled.ok,
        version: compiled.version,
        css: compiled.css,
        errorCss: compiled.errorCss,
        sourceMap: compiled.sourceMap,
        loadedUrls: compiled.loadedUrls,
        warnings: compiled.warnings,
        debugMessages: compiled.debugMessages,
        error: compiled.error
      };
      this.dependencyEntries = SassWorkspace.updateDependencyGraph(
        this.dependencyEntries,
        [batchResult],
        this.files
      );
      this.batchResults.set(this.activePath, batchResult);
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
        await this.writeGeneratedOutputs([batchResult]);
      } else {
        this.sourceMapText = '';
        this.showCompileError(
          compiled.error,
          compiled.warnings ?? [],
          compiled.debugMessages ?? []
        );
        if (compiled.errorCss !== undefined && this.errorCssEnabled) {
          this.displayResult += `\n\n----- Error CSS -----\n${compiled.errorCss}`;
        }
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
      this.continuePendingCompilation();
    }
  }

  private async compileBatchWithDartSass(): Promise<void> {
    try {
      const requestedPaths: string[] = this.activeBatchEntryPaths;
      const allEntryPaths: string[] =
        SassProject.entryPaths(this.files, this.activePath);
      const isFullBatch: boolean = requestedPaths.length === 0 ||
        requestedPaths.length >= allEntryPaths.length;
      if (isFullBatch) {
        this.batchResults.clear();
        this.dependencyEntries.clear();
      }
      const compiled: SassBatchCompileResponse =
        await this.compileProjectEntries(
          this.sourceMapEnabled,
          isFullBatch ? [] : requestedPaths
        );
      this.dependencyEntries = SassWorkspace.updateDependencyGraph(
        this.dependencyEntries,
        compiled.results,
        this.files
      );
      const complete: SassBatchCompileResponse =
        SassWorkspace.mergeBatchResponse(
          this.batchResults,
          compiled,
          allEntryPaths
        );
      this.showBatchCompileOutput(complete);
      await this.writeGeneratedOutputs(compiled.results, isFullBatch);
    } catch (error) {
      this.result = '';
      this.displayResult = (error as Error).message;
      this.sourceMapText = '';
      this.diagnosticCount = 0;
      this.isSuccessful = false;
      this.statusMessage = '批量编译失败 · ' + (error as Error).message;
    } finally {
      this.isCompiling = false;
      this.continuePendingCompilation();
    }
  }

  private continuePendingCompilation(): void {
    if (!this.compilePending) {
      return;
    }
    const pendingBatch: boolean = this.compilePendingBatch;
    const pendingFullBatch: boolean = this.compilePendingFullBatch;
    const pendingPaths: string[] = Array.from(this.pendingBatchEntryPaths);
    this.compilePending = false;
    this.compilePendingBatch = false;
    this.compilePendingFullBatch = false;
    this.pendingBatchEntryPaths.clear();
    if (pendingBatch) {
      this.compileBatch(pendingFullBatch ? [] : pendingPaths);
    } else {
      this.compile();
    }
  }

  private showBatchCompileOutput(compiled: SassBatchCompileResponse): void {
    const chunks: string[] = [];
    let warnings: SassWarning[] = [];
    let debugMessages: SassDebugMessage[] = [];
    let failedCount: number = 0;
    let successfulCount: number = 0;
    for (const entry of compiled.results) {
      warnings = warnings.concat(entry.warnings ?? []);
      debugMessages = debugMessages.concat(entry.debugMessages ?? []);
      if (entry.ok) {
        successfulCount++;
        chunks.push(`===== ${entry.entryPath} =====\n${entry.css ?? ''}`);
      } else {
        failedCount++;
        const errorText: string = entry.error?.formatted ??
          entry.error?.message ??
          'Dart Sass 未返回错误详情。';
        const errorCss: string = entry.errorCss !== undefined && this.errorCssEnabled
          ? `\n\n----- Error CSS -----\n${entry.errorCss}`
          : '';
        chunks.push(`===== ${entry.entryPath} =====\n${errorText}${errorCss}`);
      }
    }
    const diagnostics: string = this.formatDiagnostics(warnings, debugMessages);
    this.result = chunks.join('\n\n');
    this.sourceMapText = '';
    this.diagnosticCount = warnings.length + debugMessages.length;
    this.displayResult = diagnostics.length > 0
      ? `${this.result}\n\n----- Sass 诊断 -----\n${diagnostics}`
      : this.result;
    this.isSuccessful = failedCount === 0 && compiled.results.length > 0;
    this.statusMessage = failedCount === 0
      ? `批量编译成功 · ${successfulCount} 个入口`
      : `批量编译完成 · ${successfulCount} 个成功 · ${failedCount} 个失败`;
  }

  private parseOptionList(value: string): string[] {
    return value.split(/[,;\n]/)
      .map((item: string): string => item.trim())
      .filter((item: string): boolean => item.length > 0);
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

  private scheduleCompile(
    changedPaths: string[] = [],
    forceFull: boolean = false
  ): void {
    if (!this.autoCompile || !this.runtimeReady) {
      return;
    }
    for (const path of changedPaths) {
      const normalized: string = SassProject.normalizePath(path);
      if (normalized.length > 0) {
        this.pendingChangedPaths.add(normalized);
      }
    }
    if (forceFull) {
      this.pendingFullCompile = true;
    }
    if (this.compileTimer >= 0) {
      clearTimeout(this.compileTimer);
    }
    this.compileTimer = setTimeout((): void => {
      this.compileTimer = -1;
      const changed: string[] = Array.from(this.pendingChangedPaths);
      const fullCompile: boolean = this.pendingFullCompile;
      this.pendingChangedPaths.clear();
      this.pendingFullCompile = false;
      const entryPaths: string[] =
        SassProject.entryPaths(this.files, this.activePath);
      if (this.autoBatchCompile && entryPaths.length > 1) {
        const affected: string[] = fullCompile
          ? entryPaths
          : SassWorkspace.affectedEntryPaths(
            changed,
            this.dependencyEntries,
            entryPaths
          );
        if (affected.length > 0) {
          this.compileBatch(
            fullCompile || affected.length >= entryPaths.length
              ? []
              : affected
          );
        }
      } else {
        this.compile();
      }
    }, 350);
  }

  private startFileWatch(): void {
    if (!this.autoCompile || this.fileWatchTimer >= 0) {
      return;
    }
    this.fileWatchTimer = setInterval((): void => {
      this.checkExternalFiles();
    }, WATCH_INTERVAL_MS);
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
    const physicalFiles: SassEditorFile[] = this.files.filter(
      (file: SassEditorFile): boolean => file.uri.length > 0
    );
    for (let start: number = 0;
      start < physicalFiles.length;
      start += FILE_READ_BATCH_SIZE) {
      const batch: SassEditorFile[] =
        physicalFiles.slice(start, start + FILE_READ_BATCH_SIZE);
      const signatures: string[] = await Promise.all(
        batch.map(
          (file: SassEditorFile): Promise<string> =>
            this.fileSignature(file.uri)
        )
      );
      for (let index: number = 0; index < batch.length; index++) {
        if (signatures[index].length > 0) {
          this.fileSignatures.set(batch[index].uri, signatures[index]);
          this.unavailableCounts.delete(batch[index].uri);
        }
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

  private async readEditorFiles(uris: string[]): Promise<SassEditorFile[]> {
    const paths: string[] = SassProject.deriveVirtualPaths(uris);
    const incoming: SassEditorFile[] = [];
    for (let start: number = 0;
      start < uris.length;
      start += FILE_READ_BATCH_SIZE) {
      const batchUris: string[] =
        uris.slice(start, start + FILE_READ_BATCH_SIZE);
      const contents: string[] = await Promise.all(
        batchUris.map(
          (fileUri: string): Promise<string> => fileIo.readText(fileUri)
        )
      );
      for (let index: number = 0; index < batchUris.length; index++) {
        const path: string = paths[start + index];
        incoming.push({
          path,
          uri: batchUris[index],
          contents: contents[index],
          syntax: SassProject.syntaxForPath(path)
        });
      }
    }
    return incoming;
  }

  private mergeWatchedFiles(incoming: SassEditorFile[]): void {
    if (incoming.length === 0) {
      return;
    }
    this.syncActiveSource();
    const activeUri: string = this.activeFile().uri;
    const dirtyUris: Set<string> = new Set<string>();
    const dirtyVirtualPaths: Set<string> = new Set<string>();
    for (const file of this.files) {
      if (!this.dirtyPaths.has(file.path)) {
        continue;
      }
      if (file.uri.length > 0) {
        dirtyUris.add(file.uri);
      } else {
        dirtyVirtualPaths.add(file.path);
      }
    }
    this.files = SassProject.rebaseUriFiles(SassProject.mergeFiles(this.files, incoming));
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
    for (const file of editableFiles) {
      if ((activeUri.length > 0 && file.uri === activeUri) ||
        file.path === this.activePath) {
        this.activePath = file.path;
        this.source = file.contents;
        this.syntax = file.syntax;
        break;
      }
    }
    this.scheduleSessionSave();
  }

  private async refreshWatchedDirectories(): Promise<DirectoryRefreshResult> {
    if (this.projectDirectoryUris.length === 0) {
      return { addedFiles: [], scanSucceeded: true };
    }
    try {
      const expansion: ProjectSelectionExpansion =
        await this.expandProjectUris(this.projectDirectoryUris);
      const knownUris: Set<string> = new Set<string>(
        this.files
          .map((file: SassEditorFile): string => file.uri)
          .filter((value: string): boolean => value.length > 0)
      );
      const addedUris: string[] = expansion.uris.filter(
        (value: string): boolean => !knownUris.has(value)
      );
      if (addedUris.length === 0) {
        return { addedFiles: [], scanSucceeded: true };
      }
      const incoming: SassEditorFile[] = await this.readEditorFiles(addedUris);
      this.mergeWatchedFiles(incoming);
      await this.rememberFileSignatures();
      const addedFiles: SassEditorFile[] = this.files.filter(
        (file: SassEditorFile): boolean => addedUris.includes(file.uri)
      );
      const observedAt: number = Date.now();
      for (const file of addedFiles) {
        this.recentAddedFiles.set(file.uri, { observedAt });
      }
      return { addedFiles, scanSucceeded: true };
    } catch (_) {
      return { addedFiles: [], scanSucceeded: false };
    }
  }

  private async removeUnavailableFiles(paths: string[]): Promise<void> {
    if (paths.length === 0) {
      return;
    }
    const removed: Set<string> = new Set<string>(paths);
    const activeUri: string = this.activeFile().uri;
    for (const file of this.files) {
      if (removed.has(file.path) && file.uri.length > 0) {
        this.fileSignatures.delete(file.uri);
        this.unavailableCounts.delete(file.uri);
      }
    }
    await this.removeGeneratedOutputs(paths);
    this.files = this.files.filter(
      (file: SassEditorFile): boolean => !removed.has(file.path)
    );
    for (const path of paths) {
      this.dirtyPaths.delete(path);
      this.batchResults.delete(path);
    }
    this.dependencyEntries.clear();
    this.files = SassProject.rebaseUriFiles(this.files);
    const editableFiles: SassEditorFile[] =
      SassProject.editableStylesheetFiles(this.files);
    if (editableFiles.length === 0) {
      this.files = [SAMPLE_FILE];
      this.activePath = SAMPLE_FILE.path;
      this.source = SAMPLE_FILE.contents;
      this.syntax = SAMPLE_FILE.syntax;
      this.dirtyPaths.clear();
    } else {
      let activeFile: SassEditorFile | undefined;
      for (const file of editableFiles) {
        if ((activeUri.length > 0 && file.uri === activeUri) ||
          file.path === this.activePath) {
          activeFile = file;
          break;
        }
      }
      const fallback: SassEditorFile = activeFile ?? editableFiles[0];
      this.activePath = fallback.path;
      this.source = fallback.contents;
      this.syntax = fallback.syntax;
    }
    this.scheduleSessionSave();
  }

  private async checkExternalFiles(): Promise<void> {
    if (!this.autoCompile || this.isCheckingFiles) {
      return;
    }
    this.isCheckingFiles = true;
    const now: number = Date.now();
    const resumed: boolean = this.lastWatchCheckAt === 0 ||
      now - this.lastWatchCheckAt >= RESUME_GAP_MS;
    this.lastWatchCheckAt = now;
    const changedPaths: string[] = [];
    const conflictPaths: string[] = [];
    const unavailablePaths: string[] = [];
    let directoryRefresh: DirectoryRefreshResult = {
      addedFiles: [],
      scanSucceeded: true
    };
    if (resumed ||
      now - this.lastDirectoryScanAt >= DIRECTORY_RESCAN_INTERVAL_MS) {
      directoryRefresh = await this.refreshWatchedDirectories();
      if (directoryRefresh.scanSucceeded) {
        this.lastDirectoryScanAt = now;
      }
    }
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
              if (this.dirtyPaths.has(file.path)) {
                conflictPaths.push(file.path);
              } else {
                const missCount: number =
                  (this.unavailableCounts.get(file.uri) ?? 0) + 1;
                this.unavailableCounts.set(file.uri, missCount);
                if (missCount >= 2 && directoryRefresh.scanSucceeded) {
                  unavailablePaths.push(file.path);
                }
              }
            }
            continue;
          }
          this.unavailableCounts.delete(file.uri);
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

    const removablePaths: string[] = unavailablePaths.filter(
      (path: string): boolean => !conflictPaths.includes(path)
    );
    const removedFiles: SassEditorFile[] = this.files.filter(
      (file: SassEditorFile): boolean => removablePaths.includes(file.path)
    );
    const recentAddedCutoff: number = Date.now() - RESUME_GAP_MS * 2;
    for (const uri of Array.from(this.recentAddedFiles.keys())) {
      const recent: RecentAddedFile | undefined =
        this.recentAddedFiles.get(uri);
      if (recent !== undefined &&
        recent.observedAt < recentAddedCutoff) {
        this.recentAddedFiles.delete(uri);
      }
    }
    const renameCandidates: SassEditorFile[] = [];
    for (const uri of this.recentAddedFiles.keys()) {
      const currentFile: SassEditorFile | undefined = this.files.find(
        (file: SassEditorFile): boolean => file.uri === uri
      );
      if (currentFile !== undefined) {
        renameCandidates.push(currentFile);
      }
    }
    const renames: SassFileRename[] = SassWorkspace.detectRenames(
      removedFiles,
      renameCandidates
    );
    const renamedNewPaths: Set<string> = new Set<string>(
      renames.map((rename: SassFileRename): string => rename.newPath)
    );
    for (const uri of Array.from(this.recentAddedFiles.keys())) {
      const currentFile: SassEditorFile | undefined = this.files.find(
        (file: SassEditorFile): boolean => file.uri === uri
      );
      if (currentFile !== undefined &&
        renamedNewPaths.has(currentFile.path)) {
        this.recentAddedFiles.delete(uri);
      }
    }
    if (removablePaths.length > 0) {
      await this.removeUnavailableFiles(removablePaths);
    }
    if (conflictPaths.length > 0) {
      this.isSuccessful = false;
      this.statusMessage = `检测到外部修改冲突 · ${conflictPaths[0]} 尚未保存`;
      return;
    }
    if (!directoryRefresh.scanSucceeded && resumed) {
      this.isSuccessful = false;
      this.statusMessage = '目录权限暂时不可用，已保留项目并等待监视恢复。';
      return;
    }
    const addedPaths: string[] = directoryRefresh.addedFiles.map(
      (file: SassEditorFile): string => file.path
    );
    if (changedPaths.length > 0 || addedPaths.length > 0 ||
      removablePaths.length > 0) {
      this.isSuccessful = true;
      const changedCount: number =
        changedPaths.length + addedPaths.length + removablePaths.length;
      this.statusMessage = renames.length > 0
        ? `已同步项目变化 · ${renames.length} 个重命名 · ${changedCount} 个文件`
        : `已同步项目变化 · ${changedCount} 个文件`;
      const structuralChange: boolean =
        addedPaths.length > 0 || removablePaths.length > 0 || resumed;
      this.scheduleCompile(
        changedPaths.concat(addedPaths).concat(removablePaths),
        structuralChange
      );
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
    this.scheduleCompile([file.path]);
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
      await this.removeGeneratedOutputs(
        Array.from(this.generatedOutputs.keys())
      );
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
      this.unavailableCounts.clear();
      this.projectDirectoryUris = [];
      this.recentAddedFiles.clear();
      this.dependencyEntries.clear();
      this.batchResults.clear();
      await this.rememberFileSignatures();
      this.statusMessage = `已打开 · ${file.path}`;
      this.isSuccessful = true;
      this.scheduleSessionSave();
      this.scheduleCompile([], true);
    } catch (error) {
      this.showActionError('打开失败', error);
    }
  }

  private async addProjectFiles(): Promise<void> {
    try {
      const selectedUris: string[] =
        await this.selectDocuments(FILE_PICKER_MAX_FILES, true);
      const expansion: ProjectSelectionExpansion =
        await this.expandProjectUris(selectedUris);
      const uris: string[] = expansion.uris;
      if (uris.length === 0) {
        return;
      }
      for (const directoryUri of expansion.directoryUris) {
        if (!this.projectDirectoryUris.includes(directoryUri)) {
          this.projectDirectoryUris.push(directoryUri);
        }
      }
      this.syncActiveSource();
      const currentFiles: SassEditorFile[] = SassProject.withoutUntouchedPlaceholder(
        this.files,
        SAMPLE_FILE.path,
        SAMPLE_FILE.contents,
        Array.from(this.dirtyPaths)
      );
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
      const incoming: SassEditorFile[] = await this.readEditorFiles(uris);
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
      this.dependencyEntries.clear();
      this.batchResults.clear();
      await this.rememberFileSignatures();
      this.scheduleSessionSave();
      this.scheduleCompile([], true);
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

  private async expandProjectUris(
    selectedUris: string[]
  ): Promise<ProjectSelectionExpansion> {
    const expanded: string[] = [];
    const seen: Set<string> = new Set<string>();
    const directoryUris: string[] = [];
    for (const uri of selectedUris) {
      const stat: fileIo.Stat = await fileIo.stat(uri);
      if (!stat.isDirectory()) {
        const fileName: string = SassProject.fileNameFromUri(uri);
        if (SassProject.isProjectFilePath(fileName) && !seen.has(uri)) {
          seen.add(uri);
          expanded.push(uri);
        }
        continue;
      }
      if (!directoryUris.includes(uri)) {
        directoryUris.push(uri);
      }
      let relativePaths: string[] = [];
      const directoryPath: string = this.documentDirectoryPath(uri);
      try {
        relativePaths = await fileIo.listFile(directoryPath, {
          recursion: true,
          listNum: 0,
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
        const normalized: string = this.relativeListedPath(directoryPath, relativePath);
        if (SassProject.isProjectFilePath(normalized)) {
          const childPath: string = `${directoryPath}/${normalized}`;
          if (!seen.has(childPath)) {
            seen.add(childPath);
            expanded.push(childPath);
          }
        }
      }
    }
    return { uris: expanded, directoryUris };
  }

  private documentDirectoryPath(directoryUri: string): string {
    if (!directoryUri.startsWith('file://')) {
      return directoryUri;
    }
    const parsed: uri.URI = new uri.URI(directoryUri);
    const decodedSegments: string[] = [];
    for (const segment of parsed.path.split('/')) {
      if (segment.length === 0) {
        continue;
      }
      try {
        decodedSegments.push(decodeURIComponent(segment));
      } catch (_) {
        decodedSegments.push(segment);
      }
    }
    return `/${decodedSegments.join('/')}`;
  }

  private relativeListedPath(directoryPath: string, listedPath: string): string {
    const normalizedDirectory: string = SassProject.normalizePath(directoryPath);
    const normalizedListed: string = SassProject.normalizePath(listedPath);
    const directoryPrefix: string = `${normalizedDirectory}/`;
    if (normalizedListed.startsWith(directoryPrefix)) {
      return normalizedListed.slice(directoryPrefix.length);
    }
    return normalizedListed;
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

  private documentParentPath(value: string): string {
    let normalized: string = value.replaceAll('\\', '/');
    while (normalized.endsWith('/') && normalized.length > 1) {
      normalized = normalized.slice(0, normalized.length - 1);
    }
    const slashIndex: number = normalized.lastIndexOf('/');
    return slashIndex > 0 ? normalized.slice(0, slashIndex) : '/';
  }

  private joinDocumentPath(root: string, relative: string): string {
    const normalizedRoot: string = root.replaceAll('\\', '/')
      .replace(/\/+$/, '');
    const normalizedRelative: string =
      SassProject.normalizePath(relative);
    return normalizedRelative.length === 0
      ? normalizedRoot
      : `${normalizedRoot}/${normalizedRelative}`;
  }

  private documentFileUri(path: string): string {
    if (path.startsWith('file://')) {
      return path;
    }
    const encoded: string = path.split('/').map(
      (part: string): string => encodeURIComponent(part)
    ).join('/');
    return path.startsWith('/') ? `file://${encoded}` : `file:///${encoded}`;
  }

  private async ensureOutputDirectory(): Promise<void> {
    if (this.outputDirectoryPath.length > 0) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('无法获取当前窗口上下文。');
    }
    const documentPicker: picker.DocumentViewPicker =
      new picker.DocumentViewPicker(context);
    const options: picker.DocumentSaveOptions =
      new picker.DocumentSaveOptions();
    options.newFileNames = ['harmony-sass-output.css'];
    options.fileSuffixChoices = ['CSS|.css'];
    options.autoCreateEmptyFile = false;
    const uris: string[] = await documentPicker.save(options);
    if (uris.length === 0) {
      throw new Error('未选择 CSS 输出目录。');
    }
    this.outputDirectoryPath =
      this.documentParentPath(this.documentDirectoryPath(uris[0]));
    if (this.outputDirectoryPath.length === 0) {
      throw new Error('无法确定 CSS 输出目录。');
    }
    await fileIo.mkdir(this.outputDirectoryPath, true);
    this.scheduleSessionSave();
  }

  private async deleteGeneratedPath(path: string): Promise<void> {
    if (path.length === 0) {
      return;
    }
    try {
      await fileIo.unlink(path);
    } catch (_) {
    }
  }

  private async removeGeneratedOutputs(entryPaths: string[]): Promise<void> {
    for (const entryPath of entryPaths) {
      const normalized: string = SassProject.normalizePath(entryPath);
      const paths: string[] | undefined = this.generatedOutputs.get(normalized);
      if (paths === undefined) {
        continue;
      }
      for (const path of paths) {
        await this.deleteGeneratedPath(path);
      }
      this.generatedOutputs.delete(normalized);
    }
    this.scheduleSessionSave();
  }

  private async writeGeneratedOutputs(
    results: SassBatchCompileResult[],
    removeMissing: boolean = false
  ): Promise<void> {
    if (this.outputDirectoryPath.length === 0) {
      return;
    }
    const successfulEntries: Set<string> = new Set<string>();
    for (const entry of results) {
      const entryPath: string = SassProject.normalizePath(entry.entryPath);
      if (!entry.ok || entry.css === undefined) {
        continue;
      }
      const cssPath: string = this.joinDocumentPath(
        this.outputDirectoryPath,
        SassProject.outputRelativePath(entryPath, '.css')
      );
      const mapPath: string = this.joinDocumentPath(
        this.outputDirectoryPath,
        SassProject.outputRelativePath(entryPath, '.css.map')
      );
      const cssParent: string = this.documentParentPath(cssPath);
      await fileIo.mkdir(cssParent, true);
      const oldPaths: string[] = this.generatedOutputs.get(entryPath) ?? [];
      if (!this.sourceMapEnabled) {
        await this.writeText(cssPath, entry.css);
        if (oldPaths.length > 1) {
          await this.deleteGeneratedPath(oldPaths[1]);
        }
        this.generatedOutputs.set(entryPath, [cssPath]);
        successfulEntries.add(entryPath);
        continue;
      }

      if (entry.sourceMap === undefined || entry.sourceMap.length === 0) {
        throw new Error(`入口 ${entryPath} 未返回 Source Map。`);
      }
      const finalized: SassExportFinalizeResponse =
        await this.finalizeExports([{
          css: entry.css,
          sourceMap: entry.sourceMap,
          cssFileName: SassProject.fileNameFromUri(cssPath),
          sourceMapFileName: SassProject.fileNameFromUri(mapPath),
          cssUri: this.documentFileUri(cssPath),
          sourceMapUri: this.documentFileUri(mapPath)
        }], this.embedSourceMap);
      if (finalized.results.length !== 1) {
        throw new Error(`入口 ${entryPath} 的导出结果无效。`);
      }
      await this.writeText(cssPath, finalized.results[0].css);
      if (this.embedSourceMap) {
        if (oldPaths.length > 1) {
          await this.deleteGeneratedPath(oldPaths[1]);
        }
        this.generatedOutputs.set(entryPath, [cssPath]);
      } else {
        await fileIo.mkdir(this.documentParentPath(mapPath), true);
        await this.writeText(mapPath, finalized.results[0].sourceMap);
        this.generatedOutputs.set(entryPath, [cssPath, mapPath]);
      }
      successfulEntries.add(entryPath);
    }
    if (removeMissing) {
      const currentEntries: Set<string> = new Set<string>(
        results.map(
          (entry: SassBatchCompileResult): string =>
            SassProject.normalizePath(entry.entryPath)
        )
      );
      const staleEntries: string[] = [];
      for (const entryPath of this.generatedOutputs.keys()) {
        if (!currentEntries.has(entryPath)) {
          staleEntries.push(entryPath);
        }
      }
      await this.removeGeneratedOutputs(staleEntries);
    }
    if (successfulEntries.size > 0) {
      this.scheduleSessionSave();
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
      this.showBatchCompileOutput(compiled);
      const successfulCount: number = compiled.results.filter(
        (entry: SassBatchCompileResult): boolean => entry.ok
      ).length;
      if (successfulCount === 0) {
        this.showBatchCompileErrors(compiled);
        return;
      }
      await this.ensureOutputDirectory();
      await this.writeGeneratedOutputs(compiled.results, true);
      const failedCount: number = compiled.results.length - successfulCount;
      this.statusMessage = failedCount > 0
        ? `CSS 已同步 · ${successfulCount} 个成功 · ${failedCount} 个入口失败`
        : `CSS 已同步 · ${successfulCount} 个入口`;
      this.isSuccessful = failedCount === 0;
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
      const compiled: SassBatchCompileResponse =
        await this.compileProjectEntries(true);
      this.showBatchCompileOutput(compiled);
      const successfulCount: number = compiled.results.filter(
        (entry: SassBatchCompileResult): boolean => entry.ok
      ).length;
      if (successfulCount === 0) {
        this.showBatchCompileErrors(compiled);
        return;
      }
      await this.ensureOutputDirectory();
      await this.writeGeneratedOutputs(compiled.results, true);
      const failedCount: number = compiled.results.length - successfulCount;
      this.statusMessage = failedCount > 0
        ? `CSS 与 Source Map 已同步 · ${successfulCount} 个成功 · ${failedCount} 个入口失败`
        : `CSS 与 Source Map 已同步 · ${successfulCount} 个入口`;
      this.isSuccessful = failedCount === 0;
    } catch (error) {
      this.showActionError('导出 Source Map 失败', error);
    }
  }

  private async compileProjectEntries(
    sourceMap: boolean,
    requestedEntryPaths: string[] = []
  ): Promise<SassBatchCompileResponse> {
    this.syncActiveSource();
    const allEntryPaths: string[] =
      SassProject.entryPaths(this.files, this.activePath);
    const entryPaths: string[] = requestedEntryPaths.length > 0
      ? requestedEntryPaths
        .map((path: string): string => SassProject.normalizePath(path))
        .filter(
          (path: string, index: number, values: string[]): boolean =>
            allEntryPaths.includes(path) && values.indexOf(path) === index
        )
      : allEntryPaths;
    const request: SassBatchCompileRequest = {
      entryPaths,
      files: SassProject.compilerFiles(this.files, ''),
      loadPaths: this.loadPaths(),
      nodePackageImporter: true,
      packageEntryPointDirectory: '',
      style: this.outputStyle,
      alertAscii: this.alertAsciiEnabled,
      alertColor: this.alertColorEnabled,
      sourceMap,
      sourceMapIncludeSources: this.sourceMapIncludeSources,
      charset: this.charsetEnabled,
      quiet: this.quietEnabled,
      quietDeps: this.quietDepsEnabled,
      verbose: this.verboseEnabled,
      errorCss: this.errorCssEnabled,
      stopOnError: this.stopOnError,
      fatalDeprecations: this.parseOptionList(this.fatalDeprecationsText),
      futureDeprecations: this.parseOptionList(this.futureDeprecationsText),
      silenceDeprecations: this.parseOptionList(this.silenceDeprecationsText)
    };
    const script: string =
      DartSassRuntime.createAsyncBatchCompileScript(request);
    const payload: string = await this.waitForAsyncJob(script);
    return DartSassRuntime.parseBatchResponse(payload);
  }

  private async finalizeExports(
    entries: SassExportFinalizeEntry[],
    embedSourceMap: boolean = this.embedSourceMap
  ): Promise<SassExportFinalizeResponse> {
    const request: SassExportFinalizeRequest = {
      style: this.outputStyle,
      sourceMapUrls: this.sourceMapUrls,
      embedSourceMap,
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
        fileIo.OpenMode.WRITE_ONLY |
          fileIo.OpenMode.CREATE |
          fileIo.OpenMode.TRUNC
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

  private async loadSample(): Promise<void> {
    await this.removeGeneratedOutputs(
      Array.from(this.generatedOutputs.keys())
    );
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
    this.unavailableCounts.clear();
    this.projectDirectoryUris = [];
    this.recentAddedFiles.clear();
    this.dependencyEntries.clear();
    this.batchResults.clear();
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
      if (event.getModifierKeyState(['shift'])) {
        this.compileBatch();
      } else {
        this.compile();
      }
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
            .onClick((): void => {
              this.loadSample();
            })
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
          Button('批量编译').onClick((): void => { this.compileBatch(); }).height(34)
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
              this.scheduleCompile([this.activePath]);
            })
            .width(92).height(32)
          Text('输出').fontSize(13).fontColor('#667085')
          Select([{ value: '展开' }, { value: '压缩' }])
            .selected(this.outputStyle === 'compressed' ? 1 : 0)
            .onSelect((index: number): void => {
              this.outputStyle = index === 1 ? 'compressed' : 'expanded';
              this.scheduleSessionSave();
              this.scheduleCompile([], true);
            })
            .width(92).height(32)
          TextInput({ text: this.loadPathsText, placeholder: '载入路径，用逗号分隔' })
            .onChange((value: string): void => {
              this.loadPathsText = value;
              this.scheduleSessionSave();
              this.scheduleCompile([], true);
            })
            .width(210).height(32).fontSize(13)
          Text('Source Map').fontSize(13).fontColor('#667085')
          Toggle({ type: ToggleType.Switch, isOn: this.sourceMapEnabled })
            .onChange((isOn: boolean): void => {
              this.sourceMapEnabled = isOn;
              this.scheduleSessionSave();
              this.scheduleCompile([], true);
            })
          Text('自动编译').fontSize(13).fontColor('#667085')
          Toggle({ type: ToggleType.Switch, isOn: this.autoCompile })
            .onChange((isOn: boolean): void => {
              this.autoCompile = isOn;
              if (isOn) {
                this.startFileWatch();
                this.scheduleCompile([], true);
              } else {
                this.stopFileWatch();
              }
              this.scheduleSessionSave();
            })
          Button(this.advancedOptionsVisible ? '收起高级' : '高级选项')
            .onClick((): void => {
              this.advancedOptionsVisible = !this.advancedOptionsVisible;
            })
            .height(32)
          Blank().layoutWeight(1)
          Text(`${this.files.length} 个文件 · ${
            SassProject.entryPaths(this.files, this.activePath).length
          } 个入口`).fontSize(13).fontColor('#667085')
        }
        .width('100%').padding({ left: 28, right: 28, bottom: 10 })

        if (this.advancedOptionsVisible) {
          Column({ space: 8 }) {
            Row({ space: 10 }) {
              Text('包含源文件').fontSize(12).fontColor('#667085')
              Toggle({
                type: ToggleType.Switch,
                isOn: this.sourceMapIncludeSources
              }).onChange((isOn: boolean): void => {
                this.sourceMapIncludeSources = isOn;
                this.scheduleSessionSave();
                this.scheduleCompile([], true);
              })
              Text('嵌入 Map').fontSize(12).fontColor('#667085')
              Toggle({ type: ToggleType.Switch, isOn: this.embedSourceMap })
                .onChange((isOn: boolean): void => {
                  this.embedSourceMap = isOn;
                  this.scheduleSessionSave();
                  this.scheduleCompile([], true);
                })
              Text('Map 地址').fontSize(12).fontColor('#667085')
              Select([{ value: '相对' }, { value: '绝对' }])
                .selected(this.sourceMapUrls === 'absolute' ? 1 : 0)
                .onSelect((index: number): void => {
                  this.sourceMapUrls = index === 1 ? 'absolute' : 'relative';
                  this.scheduleSessionSave();
                  this.scheduleCompile([], true);
                })
                .width(88).height(30)
              Text('字符集标记').fontSize(12).fontColor('#667085')
              Toggle({ type: ToggleType.Switch, isOn: this.charsetEnabled })
                .onChange((isOn: boolean): void => {
                  this.charsetEnabled = isOn;
                  this.scheduleSessionSave();
                  this.scheduleCompile([], true);
                })
              Text('批量监视').fontSize(12).fontColor('#667085')
              Toggle({ type: ToggleType.Switch, isOn: this.autoBatchCompile })
                .onChange((isOn: boolean): void => {
                  this.autoBatchCompile = isOn;
                  this.scheduleSessionSave();
                  this.scheduleCompile([], true);
                })
              Text('遇错停止').fontSize(12).fontColor('#667085')
              Toggle({ type: ToggleType.Switch, isOn: this.stopOnError })
                .onChange((isOn: boolean): void => {
                  this.stopOnError = isOn;
                  this.scheduleSessionSave();
                  this.scheduleCompile([], true);
                })
            }.width('100%')

            Row({ space: 10 }) {
              Text('ASCII 诊断').fontSize(12).fontColor('#667085')
              Toggle({ type: ToggleType.Switch, isOn: this.alertAsciiEnabled })
                .onChange((isOn: boolean): void => {
                  this.alertAsciiEnabled = isOn;
                  this.scheduleSessionSave();
                  this.scheduleCompile([], true);
                })
              Text('彩色诊断').fontSize(12).fontColor('#667085')
              Toggle({ type: ToggleType.Switch, isOn: this.alertColorEnabled })
                .onChange((isOn: boolean): void => {
                  this.alertColorEnabled = isOn;
                  this.scheduleSessionSave();
                  this.scheduleCompile([], true);
                })
              Text('静默').fontSize(12).fontColor('#667085')
              Toggle({ type: ToggleType.Switch, isOn: this.quietEnabled })
                .onChange((isOn: boolean): void => {
                  this.quietEnabled = isOn;
                  this.scheduleSessionSave();
                  this.scheduleCompile([], true);
                })
              Text('静默依赖').fontSize(12).fontColor('#667085')
              Toggle({ type: ToggleType.Switch, isOn: this.quietDepsEnabled })
                .onChange((isOn: boolean): void => {
                  this.quietDepsEnabled = isOn;
                  this.scheduleSessionSave();
                  this.scheduleCompile([], true);
                })
              Text('详细警告').fontSize(12).fontColor('#667085')
              Toggle({ type: ToggleType.Switch, isOn: this.verboseEnabled })
                .onChange((isOn: boolean): void => {
                  this.verboseEnabled = isOn;
                  this.scheduleSessionSave();
                  this.scheduleCompile([], true);
                })
              Text('Error CSS').fontSize(12).fontColor('#667085')
              Toggle({ type: ToggleType.Switch, isOn: this.errorCssEnabled })
                .onChange((isOn: boolean): void => {
                  this.errorCssEnabled = isOn;
                  this.scheduleSessionSave();
                  this.scheduleCompile([], true);
                })
            }.width('100%')

            Row({ space: 10 }) {
              TextInput({
                text: this.fatalDeprecationsText,
                placeholder: '致命弃用：ID 或版本，逗号分隔'
              }).onChange((value: string): void => {
                this.fatalDeprecationsText = value;
                this.scheduleSessionSave();
                this.scheduleCompile([], true);
              }).layoutWeight(1).height(30).fontSize(12)
              TextInput({
                text: this.futureDeprecationsText,
                placeholder: '未来弃用：ID，逗号分隔'
              }).onChange((value: string): void => {
                this.futureDeprecationsText = value;
                this.scheduleSessionSave();
                this.scheduleCompile([], true);
              }).layoutWeight(1).height(30).fontSize(12)
              TextInput({
                text: this.silenceDeprecationsText,
                placeholder: '忽略弃用：ID，逗号分隔'
              }).onChange((value: string): void => {
                this.silenceDeprecationsText = value;
                this.scheduleSessionSave();
                this.scheduleCompile([], true);
              }).layoutWeight(1).height(30).fontSize(12)
            }.width('100%')
          }
          .width('100%')
          .padding({ left: 28, right: 28, bottom: 10 })
        }

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
                const contentsChanged: boolean = value !== this.activeFile().contents;
                this.source = value;
                this.syncActiveSource();
                if (contentsChanged) {
                  this.dirtyPaths.add(this.activePath);
                }
                this.scheduleCompile([this.activePath]);
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
