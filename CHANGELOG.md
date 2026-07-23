# 更新日志

本项目的重要变更均记录在此。

## 0.15.0 - 2026-07-23

- 确认内置官方 Dart Sass 运行时为当前 npm `latest` 版本 `1.101.6`
- 新增依赖图增量编译，普通文件变化只重新构建受影响的批量入口
- 新增输入目录到输出目录映射，自动创建和更新 CSS、Source Map，清理内嵌 Map
  后遗留的外部文件，并删除已登记的过期输出
- 新增跨目录扫描轮次的重命名识别、忽略规则、权限恢复、休眠恢复和页面生命周期
  监视复用
- 移除应用层 500 文件项目限制，对大型项目采用分批读取和签名检查
- 新增受影响入口、输出路径及重命名处理的项目模型测试

## 0.14.2 - 2026-07-22

- 对 `pkg:` 包名和子路径按路径段解码，与 `NodePackageImporter` 使用的官方 Dart
  URI 转换保持一致
- 新增百分号编码包名和子路径、重复分隔符、点路径段、规范化导出目标和包含样式表
  解析优先级的官方对比

## 0.14.1 - 2026-07-22

- 同步及异步编译均匹配官方 `NodePackageImporter` 对空 `pkg:` authority、
  查询参数和片段分隔符的拒绝行为
- 新增非法包 URL 的官方 Dart Sass 对比，覆盖 JavaScript URL API 会自动规范化的
  边界情况

## 0.14.0 - 2026-07-22

- 新增结构化官方编译器版本元数据，以及每项 Dart Sass 弃用信息的完整
  `Version | null` 版本元数据
- 在 ArkTS 到 ArkWeb 桥接中完整保留弃用选项值，使空白和无效空值产生官方诊断
- 同步及异步编译均将不支持的输入语法和输出格式直接传递给 Dart Sass，不再静默
  替换为默认值
- 新增未知或空导出条件、嵌套数组回退和重叠通配符优先级的官方
  `NodePackageImporter` 对比

## 0.13.0 - 2026-07-22

- 在 Dart Sass 提供时，为结构化错误、弃用警告和调试消息加入官方
  `SourceSpan.context`
- 为每条结构化弃用警告加入完整官方 `Deprecation` 元数据对象，同时保留已有弃用 ID
- 新增诊断源码上下文和警告元数据的官方同步/异步对比及 ArkTS 解析测试

## 0.12.0 - 2026-07-22

- 为同步及异步桥接调用者加入官方浏览器运行时 JavaScript `Error.stack`
- 保留原有 Sass 消息、Sass 调用栈、源码范围和双栏界面
- 新增同步及异步堆栈诊断的运行时和 ArkTS 解析测试

## 0.11.0 - 2026-07-22

- 在超时和编辑器页面退出时主动释放废弃的 ArkWeb 异步任务
- 页面运行时销毁时清理保留的任务状态，同时保持官方 `AsyncCompiler` 释放生命周期
- 新增 `charset`、`alertAscii`、`alertColor`、`verbose`、
  `fatalDeprecations`、`futureDeprecations` 和 `silenceDeprecations`
  的官方同步及异步对比
- 验证并记录官方浏览器发行版会拒绝传统 `render()` 和 `renderSync()`，
  包括 `data` 字符串输入，因为这些 API 需要 Node.js

## 0.10.0 - 2026-07-22

- 在页面生命周期内复用官方 `sass.AsyncCompiler`，与现有同步编译器并行使用
- 新增 ArkWeb 异步任务桥接，在不改变双栏界面的情况下返回官方
  `AsyncCompiler.compileStringAsync()` 结果
- 编辑器编译和多入口批量导出迁移至官方异步求值器，同时保留同步运行时桥接
- 新增官方同步/异步夹具对比、异步批量遇错停止测试和 ArkTS 桥接测试

## 0.9.0 - 2026-07-22

- 在 ArkWeb 页面生命周期内复用官方 `sass.Compiler`，保留现有双栏界面和编译结果
- 通过官方 `sass.info` 元数据公开并验证内置编译器，不再只依赖硬编码版本标签
- 桥接完整官方弃用元数据表，包括 ID、状态、版本和可为空的描述
- 对不嵌入源文件的外部 Source Map，以及带内嵌 Source Map 的压缩 CSS，新增逐字节
  官方 CLI 对比
- 记录剩余的 `--update` 边界：原生应用支持已授权文件变化检测和自动重新编译，
  但不复刻 CLI 进程的目标/依赖时间戳图

## 0.8.0 - 2026-07-22

- 在入口编译、相对导入、包导入、已加载 URL、结构化错误和 Source Map 中保留真实
  HarmonyOS 文档 URI
- 新增官方 `quiet` 日志行为和 CLI 兼容 Error CSS，不改变现有双栏界面
- 新增官方批量 `stopOnError` 行为，同时保留现有全部编译和导出工作流
- 新增相对及绝对 Source Map 源 URL、内嵌 Source Map 数据 URI 和跨目录
  `sourceMappingURL`
- 在运行时兼容测试中逐字节匹配官方 Dart Sass CLI Error CSS 及外部/内嵌
  Source Map 导出

## 0.7.0 - 2026-07-22

- Source Map 启用时匹配官方 Dart Sass CLI 文件导出行为
- 通过现有 CSS 导出操作成对导出 CSS 和 Source Map，不改变双栏界面
- 在 Source Map `file` 字段中写入最终 CSS 文件，并按官方展开/压缩空白和 URI
  编码行为追加 `sourceMappingURL`
- 保留单独 Source Map 导出，同时将 Map 与对应 CSS 文件名关联
- 匹配分部文件与非分部文件冲突时的官方分部优先歧义顺序和错误信息
- 保留文档提供器文件名中百分号编码的 `#` 和 `?`
- 新增展开、压缩和包含空格输出文件名的官方 CLI 对比

## 0.6.0 - 2026-07-22

- 根据官方 Dart Sass `1.101.6` 实现加入虚拟项目 `NodePackageImporter`
- 新增 `pkg:` URL 解析、最近 `node_modules` 查找、作用域包、package exports、
  通配符导出和清单顺序 Sass 条件
- 新增包 `sass`/`style`、分部、索引、直接子路径和仅供导入回退
- 新增包内相对导入、嵌套包依赖和包样式表的官方 `quietDeps` 分类
- 支持加载 `package.json` 清单，但不会把清单显示为可编辑 Sass 入口，也不会改变
  双栏编辑器布局
- 新增包成功路径和包错误边界的官方对比

## 0.5.1 - 2026-07-22

- 为 `fatalDeprecations` 新增官方 Dart Sass 编译器版本值
- 修正 `sourceMapIncludeSources` 以使用官方默认值，同时在 HarmonyOS 编辑器和导出中
  继续支持嵌入源文件
- 分离入口相对 importer 和虚拟加载路径 importer，使 `quietDeps` 按官方 Dart Sass
  行为分类依赖弃用信息
- 为编译器错误加入结构化 `sassStack`
- 新增 Source Map 默认值、致命弃用版本和依赖警告行为的官方包对比

## 0.5.0 - 2026-07-22

- 修正虚拟 importer 优先级，使直接文件、目录索引、Sass 语法文件、CSS 回退、
  分部、显式扩展名和仅供导入样式表与官方 Dart Sass 一致
- 新增 importer 边界和歧义处理的官方包对比
- 新增递归文件/文件夹混合项目加载、URI 去重和全局 500 文件限制
- 载入真实项目时自动移除未修改的内置示例，同时保留已编辑的未命名内容
- 新增已授权项目文件、当前文件、逐文件语法覆盖、输出格式、加载路径、Source Map
  和自动编译的会话恢复
- 新增批量 CSS 和 Source Map 导出，并生成避免冲突的输出文件名
- 新增排队自动编译、完整警告/调试展示和文件删除检测
- 记录 Node.js 回调、包 importer、Embedded Protocol、CLI、目标设备和签名边界

## 0.4.0 - 2026-07-22

- 为 ArkWeb 运行时桥接加入官方 Dart Sass 弃用控制
- 新增结构化弃用 ID、Sass 警告调用栈和 `@debug` 消息
- 新增虚拟项目多入口样式表批量编译
- 自动编译启用时检测外部文档变化，并保护尚未保存的修改冲突
- 现有保存操作改为保存项目中全部已修改文件，另存为仍只作用于当前文件
- 扩展诊断和批量编译的运行时及 ArkTS 测试

## 0.3.0 - 2026-07-22

- 新增由官方 Dart Sass 驱动的内存多文件项目 importer
- 新增相对 `@use`、`@forward`、`@import`、分部、`_index` 和仅供导入文件解析
- 新增 SCSS、缩进式 Sass 和 CSS 输入模式，以及展开或压缩输出
- 新增 Source Map、已加载 URL 报告、编译器警告和完整结构化错误范围
- 新增 HarmonyOS 文件打开、项目文件选择、保存、另存为、CSS 复制、CSS 导出和
  Source Map 导出
- 新增当前入口切换、虚拟加载路径、自动编译和 PC 快捷键，同时保留双栏布局
- 新增项目路径/模型测试和端到端运行时项目夹具

## 0.2.0 - 2026-07-21

- 使用官方 Dart Sass `1.101.6` 替换手写 `ScssLite` 子集
- 新增本地不可见 ArkWeb 运行时，不改变可见编辑器界面
- 支持混入、函数、控制流、算术运算、CSS at-rules 和内置 Sass 模块
- 新增包含行列信息的结构化 Dart Sass 错误
- 新增上游兼容夹具和内置第三方声明

## 0.1.0 - 2026-07-12

- 发布首个面向鸿蒙 PC 的开源 MVP
- 新增原生 ArkTS SCSS Lite 编译器核心
- 支持变量、嵌套选择器、选择器列表和 `&` 父选择器
- 新增 SCSS 到 CSS 双栏编辑器界面
- 新增核心编译行为和非法源码的单元测试
