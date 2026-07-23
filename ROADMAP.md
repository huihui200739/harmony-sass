# 路线图

## 已完成（截至 0.15.0）

- 集成官方 Dart Sass 运行时
- 支持官方 Dart Sass `1.101.6` 语言行为
- 在 ArkWeb 页面生命周期内复用官方 `sass.Compiler` 和
  `sass.AsyncCompiler`
- 通过 `AsyncCompiler.compileStringAsync()` 实现官方异步编辑器编译和批量编译，
  并保留兼容的同步桥接
- 在超时和页面退出时清理废弃的异步桥接任务
- 对字符集输出、ASCII/彩色诊断、详细警告和三类弃用选项进行官方同步/异步对比
- 桥接官方 `sass.info`、结构化编译器版本以及完整的可空弃用版本元数据
- 保留官方对不支持语法、输出格式和未经修改的弃用选项值的校验行为
- 多文件虚拟项目编译
- 以官方兼容优先级解析 Sass 模块、转发、分部文件、目录索引、CSS 回退和传统导入
- 支持 SCSS、缩进式 Sass 和 CSS 输入
- 支持展开及压缩输出
- 支持 Source Map、官方默认选项、警告、已加载 URL 和完整错误范围
- 在入口及导入诊断、已加载 URL 和 Source Map 中保留真实 HarmonyOS 文档 URI
- 支持与官方 CLI 兼容的 CSS/Source Map 成对导出，包括 Source Map `file` 字段、
  `sourceMappingURL`、输出格式空白和 URI 编码
- 支持相对及绝对 Source Map URL、内嵌 Source Map 和跨目录 CSS 到 Map 链接
- 对包含或不包含嵌入源文件的 Source Map 进行官方 CLI 对比，包括压缩内嵌 Map
- 支持按弃用 ID 或编译器版本控制弃用项
- 支持完整的逐警告弃用元数据、完整源码范围、警告及错误 Sass 调用栈、
  官方 `quietDeps`、JavaScript 运行时堆栈和 `@debug`
- 支持官方 `quiet`、Error CSS 和批量编译 `stopOnError`
- 多入口批量编译
- 鸿蒙 PC 打开、保存、导出、复制和快捷键工作流
- 保存项目中全部已修改文件
- 自动编译、外部文件重新加载和入口文件切换
- 递归文件夹项目加载及去重，不设置应用层文件数量限制
- 基于依赖图只增量编译受影响入口
- 输入目录到输出目录映射，并登记 CSS/Source Map 的创建、更新和清理
- 文件重命名识别、忽略规则、目录权限恢复和休眠恢复
- 大型项目文件读取和签名检查分批处理
- 恢复项目文件、当前文件、各文件语法和编译选项
- 载入真实项目时自动删除未修改的内置示例
- 虚拟项目 `NodePackageImporter`，支持 `pkg:`、最近的 `node_modules`、
  作用域包、package exports、条件、数组回退、通配符优先级、嵌套依赖、
  仅供导入文件、百分号编码包路径和官方非法 URL 校验
- 官方分部文件优先歧义诊断及编码文档文件名

## 待完成的目标设备验证

- 在鸿蒙 PC 真机上验证递归文档提供器 URI
- 在不同目标鸿蒙 PC 设备上验证文件与文件夹混合选择
- 在真机上验证长时间监视、目录权限、休眠恢复及大型项目性能

本项目当前不包含应用商店发布、发布签名或自动上架工作。

## 环境边界

以下上游宿主 API 依赖 Node.js 回调、无限制宿主文件系统、子进程或 Embedded
Protocol，无法在当前 ArkTS 到 ArkWeb 的 JSON 桥接中完整复刻：

- JavaScript `Options.functions`
- 外部 JavaScript `Importer` 和 `FileImporter` 回调
- 外部 JavaScript `Logger` 回调对象
- 访问已加载虚拟项目之外文件的文件系统 `NodePackageImporter`
- Dart Sass Embedded Protocol
- 完整 Dart Sass CLI 进程、CLI 监视协议及 `--update` 目标/依赖时间戳图；
  原生应用已经提供独立的依赖感知监视和输出同步
- 文件系统入口 npm API（`compile()` 和 `compileAsync()`）、
  JavaScript 回调/值对象 API 及传统 JavaScript API

官方浏览器构建即使收到 `data` 参数也会拒绝传统 `render()` 和
`renderSync()`，因此这些 API 仍属于上游 Node.js 环境边界。
