# Harmony Sass

**Harmony Sass** 是一款面向鸿蒙 PC 的 Sass 编辑与编译工具，可在本地运行官方
[Dart Sass](https://github.com/sass/dart-sass) 实现。

应用保留原有的 ArkTS 双栏编辑器界面。所有 Sass 语言行为均由官方 Dart Sass
JavaScript 发行版提供，并非重新编写或删减后的编译器。

## 当前实现

- 原生 HarmonyOS ArkTS 双栏编辑器界面
- 内置官方 Dart Sass `1.101.6` 编译器
- 在 ArkWeb 页面生命周期内复用官方 `sass.Compiler` 和
  `sass.AsyncCompiler`
- 编辑器编译和批量编译使用官方
  `AsyncCompiler.compileStringAsync()`，同时保留同步桥接以兼容现有调用
- 编译超时或页面退出时主动释放废弃的异步桥接任务，同时允许官方编译器完成正在
  执行的求值过程
- 通过官方 `sass.info` 和 `sass.Version` 校验运行时身份及结构化编译器版本
- 通过运行时桥接提供完整的官方 Dart Sass 弃用元数据，包括可为空的结构化版本信息
- 完整支持 Dart Sass 语言能力，包括模块、混入、函数、控制流、算术运算、
  CSS at-rules 和内置 `sass:*` 模块
- 支持多文件虚拟项目，应用本身不限制项目文件数量；单次手动多选仍可能受
  HarmonyOS 文件选择器 API 限制
- 支持文件与文件夹混合选择，可递归发现 Sass、CSS 和 `package.json`
- 支持相对路径 `@use`、`@forward` 和传统 `@import`
- 兼容官方文件解析规则，包括 Sass 文件、CSS 回退、分部文件、目录 `_index`
  文件和仅供导入的 `.import.scss` 文件
- 支持配置虚拟加载路径
- 虚拟项目支持 `NodePackageImporter`、`pkg:` URL、最近的 `node_modules`、
  作用域包、百分号编码包路径、package exports 和嵌套依赖
- 支持 SCSS、缩进式 Sass 和 CSS 输入语法
- 支持展开和压缩两种 CSS 输出格式
- 支持 Source Map，可选择是否嵌入源文件
- 支持外部或内嵌 Source Map，以及内嵌 Source Map 数据 URI
- 直接调用运行时 API 时遵循官方 Source Map 默认选项
- CSS 与 Source Map 文件关联、目标文件名、URI 编码和导出格式与官方 CLI 兼容
- 支持相对或绝对 Source Map 源 URL，以及跨目录 CSS 到 Source Map 的链接
- 在已加载 URL、错误信息和 Source Map 中保留真实 HarmonyOS 文档 URI
- 支持打开、保存、另存为和保存全部项目文件
- 支持复制和导出 CSS、成对导出 CSS 与 Source Map，以及单独导出 Source Map
- 支持手动编译和防抖自动编译
- 自动发现已授权项目文件在应用外发生的新增、修改和删除，并自动重新加载和编译
- 对应用内尚未保存的修改提供外部冲突保护
- 支持结构化错误、警告、完整弃用信息、完整源码范围、Sass 调用栈、
  JavaScript 运行时堆栈和 `@debug` 消息
- 支持官方静默日志、Error CSS 和批量编译遇错停止行为
- 可通过弃用 ID 或 Dart Sass 版本设置致命弃用项
- 不在应用侧修正无效输入，而是保留官方对不支持语法、输出格式及弃用选项的报错
- 支持官方 `quietDeps` 对相对文件、虚拟加载路径和包依赖的分类行为
- 支持多个项目入口批量编译，包括部分成功结果和可选的遇错停止
- 支持恢复项目文件、当前文件、各文件语法及编译选项
- 支持依赖图增量编译，普通修改只重新编译受影响的入口
- 支持输入目录到输出目录的层级映射
- 自动创建、更新和删除已登记的 CSS 与 Source Map 文件
- 支持文件重命名识别、忽略规则、目录权限恢复和电脑休眠恢复
- 项目文件读取和签名检查采用分批并行处理，适用于大型项目
- PC 快捷键：`Ctrl+O`、`Ctrl+S`、`Ctrl+Shift+S`、`Ctrl+Enter`，
  以及用于批量编译的 `Ctrl+Shift+Enter`
- 不使用网络服务，也不会把源码发送到远程编译

## 项目使用方式

使用 **打开** 可载入单个入口文件。使用 **添加项目文件** 可同时选择入口文件、
分部文件和依赖文件。Harmony Sass 会根据所选文件 URI 推导相对虚拟路径，并允许
通过文件选择器将任意已加载的样式文件切换为当前编辑入口。

所有项目文件都会传递给内存中的 Dart Sass importer。官方编译器可以直接解析项目
导入关系，无需上传源码，也不需要 ArkWeb 获得无限制的文件系统权限。已加载的
`package.json` 会参与 `pkg:` 包解析，但不会显示在样式文件入口选择器中。

通过文件夹载入项目时，应用不会主动限制文件数量，并会分批读取文件以保持大型项目
的响应速度。单次手动多选文件仍可能受 HarmonyOS 文件选择器最多 500 项的系统限制。

载入真实项目时，未修改的内置示例会被自动移除；已经编辑的未命名内容会被保留。
项目选择结果会自动去重。

## 上游源代码

- Dart Sass 官方实现：
  [sass/dart-sass](https://github.com/sass/dart-sass)
- 当前固定版本的 `NodePackageImporter` 参考源码：
  [dart-sass 1.101.6 node_package.dart](https://github.com/sass/dart-sass/blob/1.101.6/lib/src/importer/node_package.dart)
- Sass 语言规范：
  [sass/sass](https://github.com/sass/sass)

`entry/src/main/resources/rawfile` 中生成的运行时来自官方 `sass` npm 发行包。
运行时版本和构建依赖固定在 `tools/package.json` 中。本仓库的修改只会提交到
`huihui200739/harmony-sass`，不会修改或提交到上游 Dart Sass 仓库。

## 构建

### 环境要求

- 安装包含 HarmonyOS **6.1.1（API 24）** SDK 的 DevEco Studio
- 使用 DevEco Studio 内置的 Java 运行环境
- 如需重新生成和测试 Dart Sass 运行时，需要 Node.js **20.19 或更高版本**

在 macOS 中运行：

```bash
bash ./scripts/verify.sh
```

该脚本会依次执行：

1. 安装固定版本的运行时构建依赖；
2. 重新构建并测试内置 Dart Sass 运行时；
3. 安装 HarmonyOS 项目依赖；
4. 运行 ArkTS 单元测试；
5. 生成未签名 HAP。

生成的安装包路径为：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

该 HAP 用于开发和测试，因此未进行发布签名。本项目当前不包含应用商店发布或上架
流程。

## 运行时验证

兼容性测试会将内置浏览器运行时与相同固定版本的官方 Dart Sass 包进行对比：

```bash
npm --prefix tools ci
npm --prefix tools run verify
```

测试覆盖单文件 Sass 行为和多文件项目工作流，包括分部文件、模块、转发、传统导入、
输出格式、输入语法、Source Map、已加载 URL、批量入口、调试消息、弃用控制、
致命弃用版本、依赖警告分类、警告和结构化错误。

诊断测试会对比完整源码范围和每条警告的弃用元数据。测试还会比较官方同步及异步
编译器的结果、已加载 URL、异步批量编译的遇错停止行为，以及 `charset`、
`alertAscii`、`alertColor`、`verbose`、`fatalDeprecations`、
`futureDeprecations` 和 `silenceDeprecations` 等编译选项。

文件导出测试会逐字节比较展开或压缩 CSS、Source Map 目标名称、URI 编码文件名、
Error CSS、相对或绝对 Source Map URL、内嵌 Source Map 数据 URI、不包含源文件的
Source Map，以及压缩格式下的内嵌 Source Map。

Importer 测试会比较文件与目录索引优先级、Sass 与 CSS 优先级、显式扩展名、
歧义处理、package exports、包条件、数组回退、通配符优先级、嵌套依赖、
百分号编码包路径、路径规范化和包错误边界。

## 能力边界

Harmony Sass 复刻了能够在离线 HarmonyOS 应用中可靠实现的 Dart Sass 语言编译能力
和编辑器工作流。由于 ArkWeb 的 JSON 桥接无法传递 JavaScript 回调对象，也不能提供
Node.js 进程环境，以下宿主集成 API 暂不提供：

- 通过 `Options.functions` 传入宿主 JavaScript 自定义函数
- 任意 JavaScript `Importer` 和 `FileImporter` 回调
- 任意宿主 `Logger` 回调；警告和调试信息会改为通过结构化编译结果返回
- 访问虚拟 HarmonyOS 项目之外文件的无限制文件系统
  `NodePackageImporter`
- Dart Sass Embedded Protocol
- 完整命令行进程接口，包括 stdin/stdout、全部 CLI 参数、CLI 监视模式和
  `--update` 目标/依赖时间戳图
- 文件系统入口形式的 npm API（`compile()` 和 `compileAsync()`）、
  JavaScript 值/回调对象 API 及传统 JavaScript API

通过 `@function` 声明的 Sass 函数、内置函数和全部 `sass:*` 模块均由官方编译器
支持。

官方浏览器发行版本身会对传统 `render()` 和 `renderSync()` 抛出仅限 Node.js
环境的错误，包括只传入 `data` 字符串的情况。因此 Harmony Sass 不会以不兼容的
自制实现冒充这些 API。

应用会监视已授权的项目文件并自动重新编译。依赖图会让普通修改只影响相关入口；
新增、删除、重命名、编译选项变化、权限恢复和休眠恢复则会触发完整刷新。首次导出
CSS 时选择输出目录，后续导出会保持输入目录结构，并自动创建、更新或删除登记过的
CSS 和 Source Map。

这一工作流属于原生编辑器监视功能，不等同于 CLI 的 `--update` 协议，因为 CLI
还会在独立进程中比较输出文件和传递依赖的时间戳。

递归文件夹选择和长时间监视依赖 HarmonyOS 文档提供器的具体行为。当前应用构建、
项目模型测试和模拟器回归已经通过，目录权限、休眠恢复和大型项目仍需要在目标
鸿蒙 PC 真机上完成最终验证。

## 许可证

Harmony Sass 使用 [MIT 许可证](LICENSE)。内置 Dart Sass 发行版及其依赖声明位于
`entry/src/main/resources/rawfile`。
