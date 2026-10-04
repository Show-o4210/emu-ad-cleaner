# MuMu 模拟器去广告指南

## 一、先做这几步

1. 在 MuMu 多开器中备份要处理的实例。
2. **不要禁用、隐藏或删除 `com.mumu.store`。**旧指南中这一组操作会破坏部分版本的原生拖入安装，旧的一键删除脚本已撤下。
3. 如果需要去掉商店广告并保留拖入普通 APK，按 [MuMu 拖拽安装修复](MuMu拖拽安装修复.md) 的第一节下载并安装最小安装器。
4. 该工具仅验证过 MuMu 6.8.2.0 / 引擎 15.8.2.5699 / Android 15 / 商店 9.2.25（1225）；Android 12 或其他版本先不要套用工具，临时使用修复文档中的 ADB 安装方法。
5. 如果之前已经清理商店，按修复文档的第二节恢复原系统包或用户状态，再安装工具。
6. 每个多开实例单独处理，操作前核对实例编号。

安装、恢复、故障处理均在修复文档前半部分，不需要阅读原理。

## 二、可选：清理 Windows 客户端广告缓存

此步骤与拖拽修复独立。**先退出全部 MuMu 窗口和多开器**，再在 PowerShell 中执行。目录不存在会跳过；这些是旧版本使用过的缓存路径，不保证适用于每个新版本。

下面将三个指定广告缓存目录改名备份，不删除整个 `data` 目录。客户端再次联网后可能重新生成广告缓存。

```powershell
$cacheBase = Join-Path $env:APPDATA 'Netease\MuMuPlayer\data'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (Test-Path -LiteralPath $cacheBase) {
    $resolvedBase = (Resolve-Path -LiteralPath $cacheBase).Path.TrimEnd('\')
    foreach ($name in @('ProgramAds', 'startupImage', 'msgCenter')) {
        $source = Join-Path $resolvedBase $name
        $destination = Join-Path $resolvedBase ($name + '.backup-' + $stamp)
        if (-not (Test-Path -LiteralPath $source -PathType Container)) { continue }
        $resolvedSource = (Resolve-Path -LiteralPath $source).Path
        if ([IO.Path]::GetDirectoryName($resolvedSource) -ne $resolvedBase) {
            throw '缓存目录不在预期位置，已停止。'
        }
        if (Test-Path -LiteralPath $destination) { throw '备份目录已存在，已停止。' }
        Move-Item -LiteralPath $resolvedSource -Destination $destination
        Write-Host "已备份 $name"
    }
}
```

完成后重新启动 MuMu。若要恢复缓存，先退出 MuMu，把对应 `.backup-时间` 文件夹改回原名；若原名已经被客户端重新创建，先把新目录另行改名，避免覆盖。

## 三、操作后检查

- 普通 APK 拖入目标实例后能安装。
- 使用最小安装器时，商店图标和商店广告小部件不再出现。
- `com.mumu.store` 仍然是已安装、已启用的包；它承载替代安装服务，不应再被清理。
- 应用多开、键位与共享文件夹照常使用；不要清理这些功能的组件。
- 重启实例再试一次。MuMu 升级可能覆盖替代包，需先核对版本再决定是否重装工具。

## 四、恢复与常见问题

**装了最小安装器，想恢复商店：**双击工具包里的 `Restore.cmd`，选对应实例，完成后重启。

**之前隐藏/卸载过商店，或者删过系统 APK：**按 [先前已经清理过商店](MuMu拖拽安装修复.md#二先前已经清理过商店) 处理，不能继续删文件来修复拖拽。

**桌面仍有推荐内容：**顶部搜索栏等属于定制桌面的独立模块。当前内置 `app.lawnchair` 已有 MuMu 广告代码；仅看到这个包名不能判断它是干净的第三方桌面。本仓库没有验证过用替换系统桌面 APK 的方法修复这些内容。

**ADB 能装，拖入不能装：**这是两条不同安装通道。保留多开组件不能代替原生拖拽所需的商店安装服务。详见 [故障处理](MuMu拖拽安装修复.md#三遇到问题就按这里处理)。

---

**以上是操作。下面只说明广告来源与本次调查范围。**

## 五、广告来源与保留组件

| 位置 | 组件 | 本次确认的关系 |
|---|---|---|
| 安卓内 | `com.mumu.store` | 原商店同时提供广告小部件和拖拽安装服务，整包禁用会一并切断服务 |
| 安卓桌面 | MuMu 定制 `app.lawnchair` | 承载商店小部件，也有独立的推广搜索栏、弹窗逻辑 |
| Windows 客户端 | `ProgramAds` / `startupImage` / `msgCenter` 等缓存 | 与 Android 安装服务独立，路径可能随版本变化 |

保留 `com.netease.mumu.cloner`、`com.mumu.shared.sdk`、`com.mumu.acc`、输入法和输入能力组件。OAID 管理与本次拖拽修复无关，新的默认操作不再把它作为必做项。

## 六、调查范围与旧文档修正

2026-10-04 的新实测环境是 **MuMu 6.8.2.0、引擎 15.8.2.5699、Android 15**，并非旧文档记录的 Android 12。下载渠道名含有 `mumu12` 不能直接证明实例运行 Android 12，应以多开器/管理工具显示的 Android 版本为准。

在同一 APK、同一实例上，真实拖拽的结果为：原商店启用时成功，禁用后失败，恢复后再次成功。最小安装器也通过了用户真实拖入、共享目录挂载、重启后安装与回退测试。完整记录见 [修复文档](MuMu拖拽安装修复.md#五验证记录2026-10-04)。

旧指南“删除商店不影响拖入 APK”“使用 Lawnchair 通常已经规避桌面广告”等结论不适用于本次环境，已经撤下相关默认删除流程。旧 Android 12 操作记录不能作为新工具跨版本兼容的证明。
