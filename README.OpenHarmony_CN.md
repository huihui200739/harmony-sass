# Harmony Sass OpenHarmony 编译运行说明

本文说明如何在 OpenHarmony/HarmonyOS PC、2in1 设备或对应模拟环境中编译和运行
Harmony Sass。

## 一、环境要求

- DevEco Studio，并安装 HarmonyOS 6.1.1（API 24）SDK
- DevEco Studio 自带的 Java 运行环境
- Node.js 20.19 或更高版本
- `ohpm` 和 `hvigor`，通常随 DevEco Studio 一起安装
- 已配置好的鸿蒙 PC、2in1 设备或模拟器

项目的目标设备类型为：

- `tablet`
- `2in1`

项目包名为 `com.harmonysass.desktop`，入口模块为 `entry`。

## 二、使用 DevEco Studio 打开项目

1. 启动 DevEco Studio。
2. 选择 **Open**，打开仓库根目录，也就是包含
   `build-profile.json5`、`hvigorfile.ts` 和 `entry` 目录的目录。
3. 等待 DevEco Studio 完成项目同步和索引。
4. 如果提示安装依赖，执行 `ohpm install` 或使用 DevEco Studio 的依赖同步功能。
5. 在设备选择器中选择已经启动的模拟器或已连接的鸿蒙 PC 设备。
6. 选择 `entry` 模块和 `default` 构建目标。
7. 点击 **Run** 编译、安装并启动应用。

应用启动后会进入 Sass 双栏编辑器界面。可以打开或添加 Sass/SCSS/CSS 文件，
编辑内容后手动编译，也可以启用自动编译和项目监视。

## 三、命令行完整验证和构建

在仓库根目录执行：

```bash
bash ./scripts/verify.sh
```

该脚本会依次执行：

1. 安装 `tools/package.json` 中固定版本的 Dart Sass 构建依赖；
2. 使用官方 Dart Sass 运行时重新生成
   `entry/src/main/resources/rawfile/sass-runtime.js`；
3. 执行官方 Dart Sass 兼容性测试；
4. 安装 OpenHarmony 工程依赖；
5. 执行 ArkTS 单元测试；
6. 编译并生成未签名 HAP。

成功后，HAP 位于：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

该 HAP 用于本地开发和构建验证，项目当前没有配置应用商店发布签名。

如果 DevEco Studio 安装在非默认位置，可以通过环境变量指定 SDK、Java、Hvigor
和 Ohpm 路径：

```bash
DEVECO_SDK_HOME="/你的/DevEco-Studio/sdk" \
JAVA_HOME="/你的/DevEco-Studio/jbr/Contents/Home" \
HVIGOR="/你的/DevEco-Studio/tools/hvigor/bin/hvigorw" \
OHPM="/你的/DevEco-Studio/tools/ohpm/bin/ohpm" \
bash ./scripts/verify.sh
```

在 macOS 默认安装位置下，脚本会自动使用：

```text
/Applications/DevEco-Studio.app/Contents/sdk
/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw
/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm
```

## 四、单独执行运行时测试

如果只需要验证官方 Dart Sass 运行时，不编译鸿蒙 HAP，可以执行：

```bash
npm --prefix tools ci
npm --prefix tools run verify
```

测试会将内置浏览器运行时与相同版本的官方 Dart Sass npm 包进行对比，覆盖单文件
编译、多文件项目、模块、导入、Source Map、批量编译、诊断信息和项目监视工作流。

## 五、手动使用 Hvigor 构建

完成依赖安装后，也可以只构建 `entry` 模块：

```bash
ohpm install
"/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw" \
  --mode module \
  -p module=entry@default \
  -p product=default \
  assembleHap \
  --analyze=normal
```

执行 ArkTS 单元测试：

```bash
"/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw" \
  --mode module \
  -p module=entry@default \
  -p product=default \
  test \
  --analyze=normal
```

如果 DevEco Studio 安装路径不同，请将命令中的 `hvigorw` 路径替换为本机实际路径。

## 六、连接设备并运行

### 使用 DevEco Studio 运行

推荐使用 DevEco Studio 运行，因为它会负责设备选择、调试签名、安装和启动：

1. 启动模拟器，或通过 USB/局域网连接鸿蒙 PC 设备。
2. 确认设备已在 DevEco Studio 的设备列表中显示并处于可运行状态。
3. 选择 `entry` 模块。
4. 点击 **Run**。
5. 首次运行如果提示签名或调试授权，按照 DevEco Studio 的向导完成配置。

### 使用 HDC 安装

如果已经获得适用于目标设备的已签名 HAP，并且 `hdc` 已加入 `PATH`，可以执行：

```bash
hdc list targets
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

然后在设备上从应用列表启动 **Harmony Sass**。`verify.sh` 默认生成的是
`entry-default-unsigned.hap`，它主要用于构建验证；是否可以直接安装取决于本机
的设备签名和开发环境配置。

## 七、项目目录说明

```text
AppScope/                         应用级配置、名称和应用图标
entry/src/main/ets/               ArkTS 页面、编译器桥接和项目工作区
entry/src/main/resources/rawfile/ 内置官方 Dart Sass 浏览器运行时
tools/                            运行时生成脚本和兼容性测试
scripts/verify.sh                 完整验证、测试和 HAP 构建脚本
build-profile.json5               应用构建和目标 SDK 配置
entry/src/main/module.json5      entry 模块和启动能力配置
```

官方 Dart Sass 的功能基准和运行时来源请参阅：

- [Dart Sass 官方仓库](https://github.com/sass/dart-sass)
- [Harmony Sass 项目 README](README.md)

## 八、常见问题

### 1. 找不到 `ohpm` 或 `hvigorw`

确认已安装 DevEco Studio，并检查以下目录是否存在：

```text
/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw
```

如果安装位置不同，请按照上文通过环境变量指定路径。

### 2. Node.js 版本过低

检查版本：

```bash
node --version
```

需要 Node.js 20.19 或更高版本。Node.js 只用于重新生成和验证内置 Dart Sass
运行时，应用运行时本身使用仓库中已经生成的官方浏览器运行时。

### 3. 设备没有出现在 DevEco Studio 中

检查设备是否已启动、开发者模式和 USB 调试是否开启，并确认设备授权提示已经允许。
模拟器需要先在 Device Manager 中启动；真机还需要满足对应系统版本和调试权限要求。

### 4. 项目路径包含中文

仓库脚本已经兼容包含中文的项目路径。执行 `scripts/verify.sh` 时，脚本会在临时英文
路径中完成构建，再将生成的 HAP 复制回项目目录。

### 5. 运行时资源被重新生成

`entry/src/main/resources/rawfile/sass-runtime.js` 是由官方 Sass npm 包生成的运行时。
修改 `tools/package.json` 或运行时构建逻辑后，应重新执行：

```bash
npm --prefix tools ci
npm --prefix tools run verify
```

不要手工修改生成的运行时文件。

## 九、清理构建产物

以下目录和文件属于本地生成内容，不应提交到 Git：

```text
.hvigor/
oh_modules/
entry/build/
local.properties
```

可以在 DevEco Studio 中执行清理，也可以使用 Hvigor 清理模块构建产物：

```bash
"/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw" \
  --mode module \
  -p module=entry@default \
  -p product=default \
  clean
```
