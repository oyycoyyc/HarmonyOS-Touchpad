# HarmonyOS 无线蓝牙触控板（nova 15 Pro → MatePad Pro Max）

将 **Huawei nova 15 Pro（HarmonyOS 7.0 / API 26）** 变为无线蓝牙多指触控板，免安装被控端 App 直接操控 **Huawei MatePad Pro Max（HarmonyOS 7.0 / API 26）**（及支持标准蓝牙键鼠的平板/电脑主机）。

基于双机真机排雷定论，本工程采用 **经典蓝牙 HID `SUBCLASS_COMBO`（111B 复合描述符：5B 双向滚轮鼠标 + 8B 标准 USB 键盘）** 架构，完整实现 **v0.1 鸿蒙电脑原生逻辑** 与 **v0.2 Mac 风格三指拖移 + 四指映三指** 一键热切换。

---

## 一、 核心功能特性

- **零权限墙 & 被控端零安装**：仅在手机端安装本 App，仅需常规权限 `ohos.permission.ACCESS_BLUETOOTH`，平板/电脑直接通过系统蓝牙连接。
- **双模式手势一键热切换**：
  - **v0.1 鸿蒙原生模式（完整对齐鸿蒙电脑官方触控板逻辑）**：三指快速上滑显示桌面 / 上滑停顿 `220ms` 进任务中心 / 下滑还原窗口 / 左右滑 `Alt+Tab` 连续切应用 / 轻点搜索；四指轻点控制中心 / 左右分屏 / 下滑返回。
  - **v0.2 Mac 三指拖移模式（默认开启）**：三指滑动即 **Mac / 鸿蒙新版三指拖移**（`1:1` 灵敏度、抗断触、`320ms` 抬手续拖、防四指异步抬手误触）；三指**原地静止长按 `180ms`** 即触发鼠标左键持续长按（松手立即释放，也可无缝衔接拖移）；四指完整接管鸿蒙电脑三指手势。
- **纯线性稳流光标（零突然加速）**：移除 App 端二次非线性加速，配合 `12ms`（~83Hz）经典蓝牙恒定发包节拍器、单包 `±36` 平滑限幅、连续移动 UI `40ms` 节流与电容异常跳点过滤；支持 **`低(1.6)` / `中(2.15)` / `快(2.35)` / `高(2.6)`** 四档纯线性灵敏度与亚像素余数累积。
- **精准多指轻点与 2D 滚动**：
  - 单指轻点严格防误触（`<= 5.5vp / <= 180ms` + `2.0vp` 落手微抖死区），不会把单指滑动误判为“轻点+拖动”；
  - 双指轻点采用 **逐指独立位移追踪**，免疫双指异步落手/抬手引起的质心跳变，稳定触发鼠标右键；
  - 双指支持垂直滚轮 + 水平 `AC Pan` 双向主轴稳定滚动（支持自然滚动开关）及双指捏合缩放（`Ctrl + 滚轮`）。
- **交互式粘滞 `Alt+Tab` 连续切应用**：
  - 蓝牙安全 6 步错峰键盘时序（步距 `22ms`、先松主键再松修饰键）+ 严格 FIFO 键盘队列（防快速甩手卡 `Alt`）；
  - 三指（v0.1）/ 四指（v0.2）左滑或右滑均统一以 `Alt+Tab` 唤起切换栏；不松手续滑方向与屏幕高亮框动画严格一致（向右滑 → `Tab` 高亮右移；向左滑 → `Shift+Tab` 高亮左移），松手即切入。
- **边缘防误触、横屏双栏与全屏沉浸**：
  - 默认开启 **`防误触:开`**，通过系统级 `window.setGestureBackEnabled(false)` 禁用左右边缘侧滑返回热区 + 页面 `onBackPress()` 拦截，避免操作边缘时误退软件导致蓝牙断开；
  - 支持 **`横屏 / 竖屏`** 一键切换（`window.Orientation.LANDSCAPE`，竖屏顶部/听筒对应横屏左侧）；非全屏横屏采用左侧控制/日志 + 右侧大面积触控板双栏布局；
  - **全屏触控模式** 隐藏状态栏、导航栏与底部横条，右上浮窗提供横竖屏切换与 `退出全屏` 并自动避让前置摄像头；保留可折叠实时日志面板（`隐日志 / 显日志`）。
- **可选轨迹球鼠标惯性（默认关闭，默认强度 35%）**：
  - 支持在控制面板开启 **`轨迹球惯性`** 并用 **`5%~100%` 线性强度滑块**（默认 `35%`）精细调节手感；基于粘滞指数衰减 + 库仑干摩擦双项模型实现快速甩动滑行并干脆停下，任意手指重新落屏即刻刹停；
  - 界面已隐藏快捷测试按钮与“纯鼠标兼容”入口，聚焦触控板日常使用。
- **配置自动持久化保存**：
  - 通过 `@kit.ArkData` `preferences` 自动保存并恢复手势模式、自然滚动、光标速度档位、轨迹球惯性开关与强度、防误触开关、横竖屏方向与日志面板显隐状态，重启即保持上次偏好。

---

## 二、 手势速查表

| 手势 | **v0.1 鸿蒙原生模式（对齐鸿蒙电脑）** | **v0.2 Mac 三指拖移模式** |
| :--- | :--- | :--- |
| 单指滑动 | 纯线性稳流光标（`低 1.6 / 中 2.15 / 快 2.35 / 高 2.6`） | 同左 |
| 单指轻点 | 鼠标左键（防微移误触） | 同左 |
| 双指轻点 | 鼠标右键（逐指位移追踪，免疫异步抬手） | 同左 |
| 双指上下/左右滑 | 2D 双向滚动（垂直滚轮 + 水平 `AC Pan`，支持自然滚动） | 同左 |
| 双指张开/捏合 | 放大 / 缩小（`Ctrl + 滚轮`） | 同左 |
| 三指滑动 / 长按 | **鸿蒙电脑原生**：快上滑显示桌面(`Meta+D`) / 上滑停顿 `220ms` 进任务中心(`Meta+Tab`) / 下滑还原窗口(`Meta+D`) / 左右滑 `Alt+Tab` 连续切应用 | **Mac 三指拖移 & 原地长按（默认）**：滑动即拖移（`320ms` 抬手续拖）；原地停顿 `180ms` 即鼠标左键长按（原地松手立即释放） |
| 三指轻点 | 全局搜索（`Meta+S`） | — |
| 四指滑动 | 快上滑桌面 / 上滑停顿任务中心 / 下滑返回(`Esc`) / 左右分屏(`Meta+←/→`) | **接管鸿蒙电脑三指手势**：快上滑桌面 / 上滑停顿任务中心 / 下滑还原窗口 / 左右 `Alt+Tab` 切应用 |
| 四指轻点 | 控制中心（`Meta+C`） | 全局搜索（`Meta+S`） |

---

## 三、 模块解耦分层架构

全工程严格单向依赖，核心手势引擎与 HID 协议层 **零 ArkUI / 零蓝牙 / 零定时器依赖**，可直接脱离真机在 Node.js 中运行纯逻辑单元测试：

```text
pages/          (纯 UI 展示层: Index, BtControlPanel, TouchpadSurfaceView, LogConsoleView)
   │ 仅绑定只读状态 & 派发指令（零 transport / protocol / engine 依赖）
   ▼
app/            (应用编排层: TouchpadController, TouchpadAppFactory — 集中管理 12ms 蓝牙节拍器、12ms 轨迹球惯性定时器、FIFO 键盘队列与 220ms/320ms 定时器)
   ├── platform/ (系统能力隔离: ArkUiTouchAdapter, BluetoothPermissionService, TouchpadSettingsStore, WindowImmersiveService)
   ├── engine/   (纯领域手势引擎: TouchpadMotionEngine, PointerInertiaSimulator, ITouchpadActionMapper, HarmonyNativeActionMapper, MacRemapActionMapper)
   ├── protocol/ (纯 HID 协议编解码: HidDescriptors, ComboReportEncoder, ComboProtocolSession)
   └── transport/(可插拔传输层: IHidTransport -> ClassicBtHidTransport @ohos.bluetooth.hid)
        └── model/ (纯数据契约与 USB HID 键码常量: TouchpadTypes, HidKeyCodes)
```

---

## 四、 项目文件清单与逐文件职责说明

### 4.1 工程配置与入口（根级 / Ability）
| 文件路径 | 作用说明 |
| :--- | :--- |
| `build-profile.json5` | 工程级编译配置，定义 HarmonyOS SDK 版本（`compileSdkVersion: "26.0.1"` / `compatibleSdkVersion: "26.0.0"`）与签名信息（Windows E 盘镜像独立保留签名段） |
| `hvigor/hvigor-config.json5` | Hvigor 构建工具配置，关闭后台 daemon（`"daemon": false`）以避免 Windows 端口冲突 |
| `oh-package.json5` | OHPM 包依赖声明 |
| `AppScope/app.json5` | 应用全局元数据（包名 `com.oyyc.harmonytouchpad`、版本号、应用图标与名称） |
| `entry/src/main/module.json5` | Entry 模块配置，声明支持 `phone`/`tablet` 设备类型与动态权限 `ohos.permission.ACCESS_BLUETOOTH` |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 应用主 `UIAbility` 生命周期入口：强制深色模式、开启屏幕常亮（`setWindowKeepScreenOn(true)`）、启动时即禁用左右侧滑返回热区（`setGestureBackEnabled(false)`）并加载 `pages/Index` |

### 4.2 数据模型层 `entry/src/main/ets/model/`（零外部依赖）
| 文件 | 作用说明 |
| :--- | :--- |
| `TouchpadTypes.ets` | 全项目共享的纯数据结构与枚举契约：HID 模式（`COMBO_TOUCHPAD`/`STANDARD_MOUSE`）、手势策略（`HARMONY_NATIVE`/`MAC_THREE_FINGER_DRAG`）、连接状态、原始触点快照 `RawTouchSnapshot`、抽象动作 `TouchpadAction`、引擎输出 `EngineTickResult`（含定时器与轨迹球惯性控制指令）与已编码 HID 包结构 |
| `HidKeyCodes.ets` | 纯 USB HID Usage Page `0x07` 键码与修饰键位掩码常量（`REPORT_ID_MOUSE`/`KEYBOARD`、`MOD_LEFT_GUI`/`ALT`/`CTRL`/`SHIFT`、`KEY_TAB`/`D`/`C`/`S`/`ESC`/`LEFT`/`RIGHT`/`SLASH`），供 `engine/` 与 `protocol/` 共同引用以杜绝跨层耦合 |

### 4.3 纯领域手势引擎层 `entry/src/main/ets/engine/`（零框架、零蓝牙、零定时器）
| 文件 | 作用说明 |
| :--- | :--- |
| `ITouchpadActionMapper.ets` | 可插拔多指手势映射策略接口，定义 `mapMultiFingerTap`、`mapMultiFingerSwipe`、`mapMultiFingerSwipeUpHold` 与 `isThreeFingerDragEnabled`，隔离“手势识别”与“系统按键策略” |
| `HarmonyNativeActionMapper.ets` | **v0.1 鸿蒙电脑原生策略实现**：三指快上滑回桌面(`Meta+D`)、三指上滑停顿任务中心(`Meta+Tab`)、三指下滑还原窗口(`Meta+D`)、三指左右滑统一 `Alt+Tab` 切应用、三指轻点全局搜索(`Meta+S`)；四指轻点控制中心(`Meta+C`)、左右分屏、下滑返回 |
| `MacRemapActionMapper.ets` | **v0.2 Mac 三指拖移策略实现**：开启 `isThreeFingerDragEnabled = true`，并将鸿蒙电脑全部三指系统手势完整重映射到四指上（四指快上滑/上滑停顿/下滑/左右滑/轻点） |
| `PointerInertiaSimulator.ets` | 纯领域轨迹球惯性运动模拟器：采样 75ms 滑动窗口速度，结合粘滞指数衰减与库仑干摩擦双项减速模型，实现高初始动量滑行与干脆刹停，支持 `5%~100%` 线性强度调节与触碰即停 |
| `TouchpadMotionEngine.ets` | 核心多指运动与状态机引擎：实现纯线性光标计算 + 亚像素余数累积 + 轨迹球惯性接入、电容跳点防护（`>120vp/<25ms`）、单指防误触轻点（`<=5.5vp/<=180ms` + `2.0vp` 死区）、逐指独立位移双指右键、主轴稳定 2D 滚动与双指捏合缩放、Mac 三指拖移/原地长按（`1:1` 灵敏度、1~3 指抗断触、四指防降级误触、`320ms` 抬手续拖与单指轻点速放）、`220ms` 上滑停顿多任务判定，以及交互式 `Alt+Tab` 续滑步进 |

### 4.4 纯协议编解码层 `entry/src/main/ets/protocol/`（零蓝牙依赖）
| 文件 | 作用说明 |
| :--- | :--- |
| `HidDescriptors.ets` | 二进制 HID 报告描述符构造器：提供 `buildComboTouchpadDescriptor()`（111B 复合描述符：`0x01` 5B 鼠标+垂直滚轮+水平 `AC Pan`、`0x02` 8B 标准 USB 键盘）与 `buildStandardMouseDescriptor()`（54B 兜底纯鼠标描述符） |
| `ComboReportEncoder.ets` | 底层字节打包工具：将按键掩码、相对位移（`clampInt8` `[-127, 127]`）、滚轮与键码编码为 5B Combo 鼠标包、4B 标准鼠标包与 8B USB 键盘包，提供十六进制日志格式化 |
| `ComboProtocolSession.ets` | HID 协议会话与时序生成器：将 `TouchpadAction` 转为带 `delayMs` 的 HID 报文序列；实现蓝牙安全 6 步错峰多修饰键时序（步距 `22ms`，先抬主键再逆序抬修饰键）、粘滞 `Alt+Tab` 启停/步进编解码、快捷测试序列、`GET_REPORT`/`SET_REPORT` 握手应答以及断连防卡键复位包 |

### 4.5 蓝牙传输层 `entry/src/main/ets/transport/`（隔离 `@kit.ConnectivityKit`）
| 文件 | 作用说明 |
| :--- | :--- |
| `IHidTransport.ets` | 抽象传输层接口与回调契约（`HidTransportListener`），解耦具体蓝牙协议栈与上层业务，便于未来无痛扩展其他传输通道 |
| `ClassicBtHidTransport.ets` | 基于鸿蒙 API 26 `@ohos.bluetooth.hid`（`HidDeviceProfile`）的经典蓝牙 HID Device 实现：按配置注册 `SUBCLASS_COMBO (192)` / `SUBCLASS_MOUSE (128)`、处理异步注销与 `2903051` 竞争自动重试、管理配对主机列表、连接/断开、发送输入报文及响应 `GET_REPORT`/`SET_REPORT`/`SET_PROTOCOL` |

### 4.6 系统能力隔离层 `entry/src/main/ets/platform/`
| 文件 | 作用说明 |
| :--- | :--- |
| `ArkUiTouchAdapter.ets` | 适配器：将 ArkUI 原生 `TouchEvent` 转换为框架无关的 `RawTouchSnapshot`，使领域层彻底脱离 ArkUI |
| `BluetoothPermissionService.ets` | 封装 `abilityAccessCtrl` 动态申请 `ohos.permission.ACCESS_BLUETOOTH` 权限的逻辑 |
| `TouchpadSettingsStore.ets` | 基于 `@kit.ArkData` `preferences` 持久化并恢复手势模式、自然滚动、速度档位、轨迹球惯性开关/强度、防误触、横竖屏与日志显隐配置 |
| `WindowImmersiveService.ets` | 封装 `@kit.ArkUI` 窗口管理：负责横竖屏锁定切换（`window.Orientation.LANDSCAPE` / `PORTRAIT`）、全屏沉浸切换（隐藏 `status`/`navigation`/`navigationIndicator`）及边缘防误触（`setGestureBackEnabled`） |

### 4.7 应用编排层 `entry/src/main/ets/app/`
| 文件 | 作用说明 |
| :--- | :--- |
| `TouchpadController.ets` | 应用级总协调器（构造函数依赖注入 `IHidTransport`）：串联引擎、策略、协议与传输层；集中托管所有异步时序——`12ms` 经典蓝牙鼠标匀速发包节拍器与单包 `±36` 限幅拆包、`12ms` 轨迹球惯性定时器与触碰刹停逻辑、严格 FIFO 键盘队列、Mac 三指 `320ms` 抬手续拖与 `180ms` 原地长按定时器、鸿蒙电脑 `220ms` 上滑停顿定时器、连续移动 `40ms` UI 刷新节流、4 档灵敏度及惯性开关/强度管理 |
| `TouchpadAppFactory.ets` | 组合根（Composition Root）：负责实例化 `ClassicBtHidTransport` 并注入 `TouchpadController`，让 `pages/` 对具体传输层零感知 |

### 4.8 纯 UI 展示层 `entry/src/main/ets/pages/`
| 文件 | 作用说明 |
| :--- | :--- |
| `Index.ets` | 应用主页面壳：维护响应式状态镜像，渲染顶栏（标题、`防误触:开/关`、`横屏/竖屏`、`隐日志/显日志`、`全屏`），根据横竖屏动态切换单列或左右双栏布局，并实现 `onBackPress()` 拦截误返回退出 |
| `components/BtControlPanel.ets` | 蓝牙与控制面板组件：显示连接状态与 TX 包计数、提供 `启动触控板` / `注销`（已隐藏纯鼠标兼容与测试按钮）、已配对主机横向列表、手势模式/自然滚动/4档速度/轨迹球惯性开关及 `5%~100%` 线性强度滑块 |
| `components/TouchpadSurfaceView.ets` | 多指触控画布组件：实时绘制最多 5 个彩色触点圆圈（`F1~F5`）、显示手势与惯性滑行徽标、底部物理左键（支持按住拖移）与右键按钮，以及全屏右上角避让摄像头的横竖屏切换与 `退出全屏` 悬浮栏 |
| `components/LogConsoleView.ets` | 可配置高度的滚动调试日志面板：按级别高亮（`ERR`/`WARN`/`OK`/`HANDSHAKE`/`GESTURE`）并支持一键清空 |

---

## 五、 构建、打包与使用说明

### 1. 目录与打包产物
- **WSL 主源码与发布目录**：`/home/oyycoyyc/personal_works/harmony-touchpad/`
- **Windows DevEco Studio 构建镜像**：`E:\HarmonyWorks\harmony-touchpad`（保留独立真机签名配置）
- **打包产物位置**：`/home/oyycoyyc/personal_works/harmony-touchpad/release/`
  - `harmony-touchpad-v0.1.2-signed.hap`：v0.1.2 正式发行签名 HAP 包（`versionCode: 1000002`，含横屏双栏模式、35% 默认轨迹球惯性滑块、配置持久化与精简 UI）
  - `harmony-touchpad-v0.1.2-unsigned.hap`：v0.1.2 未签名 HAP 包
  - `harmony-touchpad-v0.1.2-src.tar.gz`：v0.1.2 干净源码与文档归档包
  - `pack.info`：v0.1.2 HAP 构建元信息
  - 历史版本归档：`harmony-touchpad-v0.1.1-signed.hap` / `-unsigned.hap` / `-src.tar.gz`

### 2. 双机连接步骤
1. 在 **nova 15 Pro** 与 **MatePad Pro Max** 的系统“设置 → 蓝牙”中完成基础蓝牙配对（若此前配对过其他描述符，先取消旧配对再重配一次以刷新 SDP 缓存）。
2. 打开手机端 **无线触控板**，授予蓝牙权限，点击 **`启动触控板`**（日志出现 `SUBCLASS_COMBO(192), 111B` 且 `registered=true`）。
3. 点击已配对列表中的 **MatePad Pro Max**，状态变绿 **`CONNECTED`** 即可使用；需要横握大面积操控时可点击顶部 **`横屏`** 与 **`全屏`**。

---

## 六、 技术选型备忘（蓝牙 PTP / BLE HOGP / 星闪 NearLink）

- **为何采用经典蓝牙 `SUBCLASS_COMBO` 而非蓝牙 PTP / BLE HOGP**：经 nova 15 Pro + MatePad Pro Max（HarmonyOS `7.0.0.111`）4 组真机对照实验，鸿蒙 7.0 经典蓝牙 `hid_host` 不将第三方 `Digitizer/Touch Pad (0x0D/0x05)` 识别为 `touchpad`；双模手机在 BLE HOGP 配对时走 BR/EDR 链路导致未触发 LE `CCCD` 订阅。经典蓝牙 `SUBCLASS_COMBO` 是纯软件免装被控端的最优解。
- **为何暂未用星闪（`@kit.NearLinkKit`）替代蓝牙**：核查 HarmonyOS API 26.0.1 `@kit.NearLinkKit` 全部 8 个模块确认，星闪 SDK 未开放 HID 外设注册接口，且 `advertising` 不允许三方 App 修改手机 `DeviceClass`；双端 App 走星闪 `dataTransfer` 则受限于平板全局输入注入 ACL 权限。详见 [PROJECT_PLAN_AND_PROGRESS.md](file:///home/oyycoyyc/personal_works/harmony-touchpad/PROJECT_PLAN_AND_PROGRESS.md)。
