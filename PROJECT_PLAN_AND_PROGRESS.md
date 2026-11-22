# HarmonyOS 模拟触控板项目 — 架构方案与进度记录

> 最后更新：2026-11-21 23:23

---

## 1. 项目目标与调试环境

### 1.1 设备与开发环境
- **触控板端（主控手机）**：Huawei nova 15 Pro — HarmonyOS `7.0.0.111`（API 26）
- **被控端（目标主机）**：Huawei MatePad Pro Max — HarmonyOS `7.0.0.111`（API 26）
- **可调试真机**：仅上述两台设备
- **开发工具**：DevEco Studio（匹配 HarmonyOS 7.0 / API 26）已就绪，已完成过应用真机签名流程

### 1.2 功能规划
- **初版 Demo（v0.1）**：
  - 在手机端实现单指、双指、三指及以上的**点击与滑动识别**（含实时调试可视化）。
  - 与鸿蒙触控板接口/系统多模输入完成对接识别（平板识别为原生触控板）。
  - 三指及以上动作按**鸿蒙原生触控板逻辑**触发（如返回桌面、多任务、切换应用等）。
- **后期演进（v0.2+）**：
  - 支持 **Mac 风格手势重映射**：
    - **四指** → 映射为鸿蒙原生**三指手势**；
    - **三指** → 映射为 **macOS 风格三指拖移**（文字框选、窗口/文件拖动）。

---

## 2. 技术选型与架构定案

### 2.1 最终选型：蓝牙 HID 精密触控板（Precision Touchpad, PTP）
经过对比三条鸿蒙官方路径（`InputKit` 本机注入、`DriverDevelopmentKit` HID DDK 虚拟驱动、`ConnectivityKit` 蓝牙 HID），针对“手机无线控平板 + 原生多指逻辑 + 后期 Mac 拖拽重映射”，确定采用 **蓝牙 HID PTP 方案**：

- **零权限墙 & 平板零安装**：
  - 仅在 `nova 15 Pro` 安装应用，只需常规权限 `ohos.permission.ACCESS_BLUETOOTH`（无需申请受限 ACL 权限）。
  - `MatePad Pro Max` 无需安装任何被控 App，直接通过系统蓝牙识别为原生硬件触控板。
- **双传输保险（Fail-Fast 风险对冲）**：
  - **主方案（经典蓝牙 HID）**：`@kit.ConnectivityKit` → `@ohos.bluetooth.hid` (`HidDeviceProfile`，API 23+)，利用 `registerHidDevice`、`connect`、`sendReport`、`onGetReport` + `replyReport`、`onSetReport` 等接口完成 PTP 握手与多指报文上报（具体签名以 API 23+ 文档为准）。
  - **备选方案（BLE HOGP）**：若 Stage 1 实测平板经典蓝牙 Host 不对 Digitizer 启用 `hid-multitouch` PTP 驱动，则仅替换传输层为 `@ohos.bluetooth.ble` (`createGattServer` 发布 `0x1812` HID Service + `0x2A4B` Report Map + `0x2A4D` Report)，上层 PTP 协议与手势引擎 100% 复用。

### 2.2 核心数据管线设计
```text
nova 15 Pro (ArkUI onTouch: touches + historicalPoints)
        │
        ▼
[TouchTracker] ── 物理尺寸归一化 (xdpi/ydpi -> 120mm×75mm) + 100µs 递增 ScanTime
        │
        ├──────────────────────────────┐
        ▼                              ▼
[GestureRecognizer]          [VirtualTouchMapper]
(单/双/三/四指+点击与滑动识别)     - v0.1 PassthroughMode: N指原样透传
(供 UI 调试面板 & v0.2 触发器)     - v0.2 MacDragMode: 4指->3指, 3指->左键按下+单指拖移
                                       │
                                       ▼
                             [PtpReportEncoder]
                             (Parallel Mode: 单帧并行打包最多 5 指触点)
                                       │
                                       ▼
                             [BluetoothTransport]
                             (主: Classic BT HidDeviceProfile / 备: BLE HOGP)
                                       │
                                       ▼
                    MatePad Pro Max (HarmonyOS 7.0 原生多模触控板解析)
```

### 2.3 附注：关于“鸿蒙自写驱动适配苹果妙控板”的调研结论
- 鸿蒙支持用户态外设驱动框架：**`DriverExtensionAbility` + USB DDK + HID DDK**（不允许三方内核 `.ko`）。
- **有线 USB-C 妙控板**：技术链路可行（按 Apple VID `0x05AC` + 妙控板 PID 匹配，通过 USB/HID DDK 读取私有报文解析后，用 `OH_Hid_CreateDevice` + `OH_Hid_EmitEvent` 虚拟标准多点触控板注入系统）。
- **蓝牙妙控板**：受限较大（DDK 扩展外设框架主要面向 USB 总线，蓝牙 HID 通道由系统协议栈接管，三方难以独占底层原始通道）。
- **现实门槛**：需要申请受限 ACL 权限（如 `ohos.permission.ACCESS_DDK_HID`），且平板端 `SystemCapability.Driver.HID.Extension` 支持度需真机验证。因此优先推进本蓝牙 PTP 项目是最优解。

---

## 3. 分阶段开发计划与当前进度

### 总体进度概览
- [x] **Phase 0：文档调研、技术选型与环境确认**（已完成，2026-11-21）
- [ ] **Phase 0.5：`@ohos.bluetooth.hid` 文档精读与 ArkTS 语法热身**（进行中，已读至 `onGetReport`）
- [x] **Stage 1 双机真机排雷定论（nova 15 Pro + MatePad Pro Max 7.0.0.111）**：已完成 4 组对照实验，实锤鸿蒙手机纯软件蓝牙方案的系统级边界（详见下方第 3.1 节实验结论，2026-11-21）
- [x] **架构定案 — 方法一：经典蓝牙 `SUBCLASS_COMBO`（111B 复合键鼠 + 双向滚轮 + 鸿蒙系统快捷键）**（已拍板并完成全工程解耦重构，2026-11-21）
- [x] **v0.1（鸿蒙原生手势逻辑）+ v0.2（Mac 三指拖移 + 四指映三指）代码实现与静态/描述符自动化验收**（已完成并同步至 E 盘镜像，2026-11-21）
- [x] **首轮真机问题修复：交互式粘滞 `Alt+Tab` 连续切应用 + 6 步错峰 `Alt+Shift+Tab` + Mac 三指拖移 1:1 灵敏度齐平/抗断触/320ms 抬手续拖**（已完成 9 组单元测试并同步 E 盘，2026-11-21）
- [x] **第二轮真机手感打磨与 UI 收口：纯线性光标消除二次加速 + 边缘防误触（`setGestureBackEnabled(false)` + `onBackPress`）+ 单指防误触/双指逐指位移右键修复 + 移除冗余诊断页 + 全屏退出移至右上角**（双机实测验收通过，2026-11-21）
- [x] **第三轮真机深度优化：12ms 经典蓝牙匀速发包节拍器与单包 `±36` 限幅消除偶发突然加速 + UI 刷新节流 + 电容跳点防护 + 4 档纯线性速度（`1.6 / 2.15 / 2.35 / 2.6`）+ 全面对齐鸿蒙电脑触控板手势（三指快上滑回桌面 / 上滑停顿 `220ms` 任务中心 / 下滑还原窗口 / 左右滑统一 `Alt+Tab` 且续滑与高亮框方向一致 / 四指轻点控制中心）+ 修复 Mac 模式四指异步抬手误触三指拖移**（已全部通过模拟测试、编译签名并归档至 `release/`，2026-11-21）
- [x] **星闪（`@kit.NearLinkKit`）替代可行性核查**：直接核查 API 26.0.1 SDK 声明文件，确认纯软件平板零安装形态无法用星闪替代蓝牙 HID（详见 3.3 节，2026-11-21）
- [x] **v1.0 文档收口与发行打包**：已完善逐文件架构文档（见 [README.md](file:///home/oyycoyyc/personal_works/harmony-touchpad/README.md) 第 4 节）并输出可安装签名 `.hap` 与干净源码归档包至 `/home/oyycoyyc/personal_works/harmony-touchpad/release/`（2026-11-21）

### 3.2 最终落地方案：经典蓝牙 HID `SUBCLASS_COMBO` 架构（2026-11-21 定版）
- **蓝牙通道**：采用真机验证稳定可用的 `@ohos.bluetooth.hid`（经典蓝牙 `HidDeviceProfile`），`subclass` 设为 `hid.Subclass.SUBCLASS_COMBO (192)`（保留 `SUBCLASS_MOUSE (128)` 作为纯鼠标兼容兜底）。
- **复合描述符（111B）**：
  - `Report ID 0x01`（5B）：3 键鼠标 + 相对 X/Y + 垂直滚轮 (`Wheel 0x38`) + 水平滚动 (`Consumer AC Pan 0x0238`)。
  - `Report ID 0x02`（8B）：标准 USB 键盘（1B 修饰键 + 1B 保留 + 6B 键码），支持 6 步错峰多修饰键时序、FIFO 键盘队列与粘滞 `Alt+Tab` 连续切换 3+ 应用（左/右滑统一唤起，续滑方向与屏幕高亮框一致）。
- **核心引擎与体验收口（共 21 个 `.ets` 源码文件，完整逐文件职责表见 `README.md` 第 4 节）**：
  - `TouchpadMotionEngine`（纯领域层，零框架/零定时器依赖）：纯线性光标缩放（档位 `低 1.6 / 中 2.15 / 快 2.35 / 高 2.6`）+ 亚像素余数累积 + 电容跳点防护 + 严格单指轻点（`<=5.5vp / <=180ms` + `2.0vp` 死区）+ 逐指独立位移双指右键 + 主轴稳定 2D 滚动 + 捏合缩放(`Ctrl+滚轮`) + Mac 三指拖移（`1:1` 齐平、1~3 指抗断触、四指异步抬手防降级误触、`320ms` 抬手续拖与单指轻点速放）+ 鸿蒙电脑原生 `220ms` 上滑停顿任务中心 / 快上滑显示桌面。
  - `TouchpadController`（应用编排层）：集中托管 `12ms` 蓝牙匀速发包节拍器与单包 `±36` 平滑限幅拆包、连续移动 `40ms` UI 重绘节流、FIFO 键盘队列与 `220ms`/`320ms` 定时器。
  - `HarmonyNativeActionMapper`（v0.1 默认，完整对齐鸿蒙电脑逻辑）与 `MacRemapActionMapper`（v0.2 一键热切换），共享纯常量文件 `model/HidKeyCodes.ets`，实现零跨层耦合。
  - 窗口与交互：`WindowImmersiveService` 调用 `setGestureBackEnabled(false)` 禁用左右侧滑返回热区，配合 `Index.onBackPress()` 拦截误退出；移除 `HostDiagnosticsView` 冗余诊断页，保留 `LogConsoleView`；全屏模式 `退出全屏` 置于右上角安全区避开前置摄像头。

### 3.3 星闪（`@kit.NearLinkKit`）替代可行性核查结论（2026-11-21）
直接查阅本机 HarmonyOS API 26.0.1 SDK `@hms.nearlink.*` 全部 8 个接口文件（`advertising`、`scan`、`manager`、`remoteDevice`、`ssap`、`dataTransfer`、`constant`、`cdsm`）：
1. **无 HID 外设接口**：`@kit.NearLinkKit` 全套未提供类似蓝牙 `@ohos.bluetooth.hid` 的 HID Device 注册能力。
2. **无法伪装外设类别**：`advertising.AdvertisingData` 不允许三方 App 修改本机 `DeviceClass`（无法改为 `DEVICE_MOUSE` / `DEVICE_TOUCHPAD`），平板系统不会将手机 `ssap.Server` 自动接管为系统光标。
3. **双端 App 注入受限**：若改用手机+平板双端 App 走星闪 `dataTransfer` 传数据，平板端跨应用注入全局鼠标/快捷键需受限 ACL 权限（`INJECT_INPUT_EVENT` / `ACCESS_DDK_HID`），普通个人调试签名不可直接获取。
4. **后续可选演进方向**：纯软件侧可进一步补充“切回前台自动重注册 + 自动回连上次平板 + 报文微合并稳流”；若追求星闪原生 `touchpad` / 1000Hz+ 回报率，可外接一颗星闪 SLE 开发板（如 BS21/WS63）作为硬件桥接。

### 3.1 Stage 1 真机排雷实测结论（2026-11-21）
1. **实验 1 — 经典蓝牙 HID + 54B 标准鼠标**：✅ 连接成功，光标移动正常，平板 `inputDevice` 识别为 `sources: [mouse]`。
2. **实验 2 — 经典蓝牙 HID + 477B/613B 并行 5 指 PTP**：❌ 平板直接提示连接失败。
3. **实验 3 — 经典蓝牙 HID + 190B 串行 5 指 PTP**：⚠️ 通过 SDP、手机侧进入 `CONNECTED` 且 TX 持续增长，平板诊断中短暂闪现一个新增虚拟设备，但仍被归类为 **`mouse` 而非 `touchpad`**；全程无 `GET_REPORT` / `SET_REPORT`，平板蓝牙停在「连接中」后超时断开并销毁设备。
   - **结论**：鸿蒙 7.0 经典蓝牙 `hid_host` 不支持将第三方经典蓝牙 HID `Digitizer/Touch Pad (0x0D/0x05)` 识别为原生 `touchpad`。
4. **实验 4 — BLE HOGP (`0x1812`) + 395B/125B PTP & 54B 标准鼠标**：⚠️ 首次配对走经典蓝牙（含音频），手动连接后平板能连上 GATT 并读完 `ReportMap` 和 `ReportRef (0x2908)`，但随后中止，从未触发 `CCCD (0x2902)` 订阅写入；即便是 54B 标准鼠标表现完全一致。
   - **结论**：`nova 15 Pro` 作为双模蓝牙手机（系统固定广播 `MAJOR_PHONE` CoD 且无法关闭 BR/EDR），与 MatePad 配对时优先走经典蓝牙而非纯 LE 加密绑定（LE Bonding），导致 BLE HOGP 在安全绑定/订阅阶段被系统拦截。

### 文档精读与学习记录（2026-11-21）
- **当前阅读位置**：必读清单第 1 项 `@ohos.bluetooth.hid` 官方文档，已读完 `BaseProfile`、`BluetoothAddress`、`hid.createHidHostProfile`、`hid.createHidDeviceProfile`，当前停在 **`onGetReport(callback: Callback<GetReportData>)`**。
- **已掌握的核心概念与 ArkTS 语法（对照 C++）**：
  - **文档规范**：`Phone 23+` 等设备与最低 API 版本标签、`SystemCapability.Communication.Bluetooth.Core` 系统能力、Stage 模型约束、类型别名（`type`）与工厂方法的区分、通用错误码（`401` 参数错误 / `801` 能力不支持）。
  - **蓝牙 HID 概念**：Profile（蓝牙场景协议规范，如 HID/A2DP/HFP）、`BaseProfile` 公共基类、`HID Host`（主机端）vs `HID Device`（外设端，本项目手机侧角色）。
  - **接口 vs 类**：`interface` 是无实现的“合同/规范”（可描述方法能力或数据结构），`class` 是具体实现；鸿蒙系统通过工厂方法返回底层实现好的对象。
  - **变量声明**：ArkTS 使用 `let`（可重赋值，类比 C++ `auto`）与 `const`（常量，类比 `const auto`），类型为后置可选（`: Type`），且具备块级作用域（注意 `try` 块内作用域）。
  - **异步回调与事件订阅**：`on(...)` 登记订阅 → 底层事件触发时反复回调 → `off(...)` 取消订阅；`Callback<GetReportData>` 等价于 `(data: GetReportData) => void`（类比 C++ `std::function<void(GetReportData)>`），区别于双参数的 `AsyncCallback<T>`（`(err, data) => void`）。
- **API 细节修正**：确认 API 23+ 的 `HidDeviceProfile` 事件回调采用独立方法名形式（如 `onGetReport(callback: Callback<GetReportData>)`），而非旧式字符串事件 `on('getReport', ...)`。

### 各阶段详细任务

#### Stage 1：蓝牙 PTP 握手排雷 Spike（1~2 天，最优先）
- [ ] 在 `/home/oyycoyyc/personal_works/harmony-touchpad/` 初始化 HarmonyOS API 26 Stage 模型工程
- [ ] 配置 `ohos.permission.ACCESS_BLUETOOTH` 动态权限申请
- [ ] 实现 `HidDeviceProfile` 最小蓝牙 HID 服务，支持一键切换：
  - [ ] Test A：标准鼠标 HID Report Descriptor（验证基础连接与光标移动）
  - [ ] Test B：5 指 Microsoft PTP 精密触控板 HID Report Descriptor（含 `on('getReport')`/`replyReport` 与 `on('setReport')` 握手日志）
- [ ] 制作合成报文测试按钮（模拟单指移动、双指滚动、三指上滑）
- [ ] 在 MatePad Pro Max 上验证是否被识别为原生 `touchpad`（可通过 `inputDevice.getDeviceInfoSync().sources` 核查）
- [ ] *（条件触发）* 若经典蓝牙无法触发平板 PTP 驱动，立刻切入 BLE HOGP (`GattServer`) 验证

#### Stage 2：多指采集、识别状态机与 PTP 协议层（2~3 天）
- [ ] 基于 `onTouch` (`touches` / `changedTouches` / `getHistoricalPoints()`) 实现 `TouchTracker`
- [ ] 实现物理坐标归一化（读取 `display` `xdpi/ydpi` 映射至标准触控板物理尺寸）与 16-bit `ScanTime`（100µs 单位递增时钟）
- [ ] 实现 `GestureRecognizer` 有限状态机：识别单/双/三/四指+点击与四向滑动（含多指落点容错时间窗）
- [ ] 实现 `VirtualTouchMapper` 抽象层（v0.1 实现 `PassthroughMode`，预留 `MacDragMode` 接口）
- [ ] 实现 5 指 Parallel Mode `PtpReportEncoder`

#### Stage 3：手机端交互体验与防误触（1~2 天）
- [ ] 全屏沉浸式布局（`setWindowLayoutFullScreen(true)` + 隐藏状态栏/导航条 + `setWindowKeepScreenOn(true)` 常亮）
- [ ] 屏幕边缘安全区避让（避免误触手机侧滑返回与底部导航横条）
- [ ] 排查手机端“三指下滑截屏”等系统全局手势冲突，增加引导提示
- [ ] 完善蓝牙配对设备列表、快速重连、实时手势 HUD 与调试日志浮窗

#### Stage 4：双机真机验收（1 天）
- [ ] 验收平板识别为原生 `touchpad` 并遵循自然滚动/指针速度设置
- [ ] 验收单指（移动/轻点/双击/按压拖拽）
- [ ] 验收双指（右键轻点/上下左右惯性滚动/捏合缩放）
- [ ] 验收三指及以上（手机识别准确率 + 平板鸿蒙原生多指手势触发）
- [ ] 记录实测手感参数并冻结 v0.1，规划 v0.2（四指映三指 + 三指 Mac 拖移）

---

## 4. 必读官方文档链接清单

### HarmonyOS 官方文档
1. **蓝牙 HID 模块 (`@ohos.bluetooth.hid`)** — *核心，看 `HidDeviceProfile` 生命周期与 `getReport`/`setReport`/`sendReport`*
   - https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-bluetooth-hid
2. **蓝牙 BLE 模块 (`@ohos.bluetooth.ble`)** — *备选 HOGP 方案参考 `createGattServer`*
   - https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-bluetooth-ble
3. **ArkUI 触摸事件 (`onTouch`)** — *看 `TouchEvent`、`touches`、`changedTouches`、`getHistoricalPoints`*
   - https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-events-touch
4. **窗口管理 (`@ohos.window`)** — *看全屏沉浸、系统栏隐藏、屏幕常亮*
   - https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-window
5. **输入设备管理 (`@ohos.multimodalInput.inputDevice`)** — *平板验收 `sources` 是否含 `'touchpad'`*
   - https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-inputdevice
6. **HID DDK 驱动开发指南** — *扩展阅读（有线外设/妙控板驱动参考）*
   - https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hid-ddk-guidelines

### Precision Touchpad (PTP) 协议规范
7. **Windows Precision Touchpad Implementation Guide**
   - https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/windows-precision-touchpad-implementation-guide
8. **Required HID Top-Level Collections（重点看 Touchpad / Configuration / Mouse 三个集合与 Feature Report）**
   - https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/touchpad-required-hid-top-level-collections

---

## 5. 当前状态与后续可选方向

v1.0（含鸿蒙原生模式 + Mac 三指拖移与抬手续拖 + 交互式连续切应用 + 纯线性光标 + 边缘防误触）已双机真机验收通过并完成打包归档，交付物位于 `/home/oyycoyyc/personal_works/harmony-touchpad/release/`。  
后续如继续迭代，可优先考虑：**切回前台自动重注册并自动回连上次 MatePad**、或 **外接星闪 SLE 硬件桥接**。
