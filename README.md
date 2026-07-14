# 安卓模拟器去广告指南（雷电 9 + MuMu 12）

> 面向 Windows 上的 **雷电模拟器 9** 与 **MuMu 模拟器 12**。  
> 思路一致：**ADB 卸载/禁用内置广告应用** → **Root + 系统盘可写后物理删除** → **清理 Windows 端广告缓存**。  
> 本机实测路径：雷电 `D:\leidian\LDPlayer9` · MuMu `D:\MuMu\MuMuPlayer`。

---

## 目录

1. [通用说明](#一通用说明)
2. [对比速查](#二对比速查)
3. [雷电模拟器 9](#三雷电模拟器-9)
4. [MuMu 模拟器 12](#四mumu-模拟器-12)
5. [效果自检](#五效果自检)
6. [常见问题](#六常见问题)
7. [本机实测结果](#七本机实测结果)

---

## 一、通用说明

### 1.1 能去掉什么 / 不能保证什么

| 通常可处理 | 说明 |
|------------|------|
| 内置应用商店 / 游戏中心 | 桌面图标、安装拦截推广等 |
| 部分追踪/设置入口 | 如 MuMu 的 OAID 管理 |
| 客户端本地广告图与配置 | 启动图、侧边广告、推送缓存等 |

| 可能仍存在 | 说明 |
|------------|------|
| 客户端联网重新拉广告 | 外框启动图等可能回弹，需再清缓存或 hosts |
| 新实例 / 升级 / 修复后恢复 | 需对**新实例**重做一遍 |
| 游戏内广告 | 与模拟器无关 |

### 1.2 通用原则

1. **先 ADB 用户卸载 + 禁用 + 隐藏**，再视权限 **物理删除系统 APK**。  
2. **不要乱删** 核心服务、输入法、多开组件。  
3. PowerShell 下 `su` 必须写成：

```powershell
.\adb.exe -s <设备> shell "su -c '你的命令'"
```

不要写成 `shell su -c "mount -o ..."`（会被拆参，报 `invalid option`）。

4. 修改 Root / 系统盘写权限后 **重启实例** 再测。  
5. 仅供个人学习与自用优化；Root、可写系统盘、删除系统应用有风险，请自行备份。

---

## 二、对比速查

| 项目 | 雷电 9 | MuMu 12 |
|------|--------|---------|
| 安装目录（示例） | `D:\leidian\LDPlayer9` | `D:\MuMu\MuMuPlayer` |
| 控制台 | `ldconsole.exe` | `nx_main\MuMuManager.exe` / `mumu-cli.exe` |
| ADB 设备示例 | `emulator-5554` | `127.0.0.1:16384`（实例 0） |
| 连接方式 | 自带 adb，开机即可 | `MuMuManager.exe adb -v 0 -c connect` |
| 主广告包名 | `com.android.flysilkworm` | `com.mumu.store` |
| 系统路径 | `/system/priv-app/ldAppStore` | `/system/priv-app/com.mumu.store` |
| 系统盘可写 | 需设置中开启「系统盘可写」+ Root | Root 后通常 `/system` 可写 |
| Windows 缓存 | `%AppData%\leidian9\` | `%AppData%\Netease\MuMuPlayer\data\` |
| 可选禁用程序 | `ldplayerpartner.exe` | 一般无需改 exe |
| 建议保留 | `com.android.coreservice` | `com.netease.mumu.cloner`、shared.sdk |

---

## 三、雷电模拟器 9

### 3.1 广告从哪来

| 位置 | 组件 / 路径 | 表现 |
|------|-------------|------|
| 安卓内 | `com.android.flysilkworm`（`/system/priv-app/ldAppStore`） | 游戏中心、推广 |
| Windows | `%AppData%\leidian9\`（及 `Leidian9`） | 启动/侧边广告图、配置 |
| Windows | `Documents\leidian9\Applications\`、`Pictures\cache\` | 首屏推荐、图缓存 |
| 程序 | `ldplayerpartner.exe` | 合作/资讯类组件 |

**建议保留：** `com.android.coreservice`（核心服务）、`com.android.launcher3`、`com.android.googleinstaller`（装 GMS，非商店广告）。

### 3.2 准备

```powershell
cd D:\leidian\LDPlayer9

# 开启 Root（改完重启）
.\ldconsole.exe modify --index 0 --root 1
.\ldconsole.exe reboot --index 0

# 设置中同时打开：ADB 调试、Root、系统盘可写（名称因版本略有差异）

.\adb.exe devices
# 期望：emulator-5554    device

$s = "emulator-5554"
.\adb.exe -s $s shell "su -c id"
# 期望：uid=0(root)

# 系统盘可写测试
.\adb.exe -s $s shell "su -c 'mount -o remount,rw /; touch /system/priv-app/.write_test && rm /system/priv-app/.write_test && echo WRITE_OK'"
```

- 输出 `WRITE_OK` → 可做物理删除  
- 仍只读 → 检查设置并重启后再测

无设备时先：

```powershell
.\ldconsole.exe launch --index 0
```

### 3.3 安卓侧清理（核心）

```powershell
$s = "emulator-5554"

# 用户层更新包（有则卸）
.\adb.exe -s $s uninstall com.android.flysilkworm

# 当前用户卸载 + 禁用 + 隐藏
.\adb.exe -s $s shell pm uninstall --user 0 com.android.flysilkworm
.\adb.exe -s $s shell pm disable-user --user 0 com.android.flysilkworm
.\adb.exe -s $s shell am force-stop com.android.flysilkworm
.\adb.exe -s $s shell "su -c 'pm hide com.android.flysilkworm; pm disable com.android.flysilkworm'"

# 彻底删除系统包（需 WRITE_OK）
.\adb.exe -s $s shell "su -c 'mount -o remount,rw /'"
.\adb.exe -s $s shell "su -c 'rm -rf /system/priv-app/ldAppStore'"
.\adb.exe -s $s shell "su -c 'rm -rf /data/data/com.android.flysilkworm /data/user/0/com.android.flysilkworm /data/user_de/0/com.android.flysilkworm'"
.\adb.exe -s $s shell "su -c 'sync'"

# 保持核心服务
.\adb.exe -s $s shell pm enable com.android.coreservice

# 验证
.\adb.exe -s $s shell "su -c 'ls /system/priv-app/ldAppStore'"
# 期望：No such file or directory

.\ldconsole.exe reboot --index 0
# 开机后再查：
.\adb.exe -s $s shell pm path com.android.flysilkworm
.\adb.exe -s $s shell pm list packages | findstr fly
```

#### 可选：模拟器内 hosts 屏蔽广告域

```powershell
@"
127.0.0.1 localhost
::1 localhost
127.0.0.1 img.ldmnq.com
127.0.0.1 ad.ldmnq.com
127.0.0.1 ads.ldmnq.com
127.0.0.1 store.ldmnq.com
127.0.0.1 ldstore.ldmnq.com
127.0.0.1 gamestore.ldmnq.com
127.0.0.1 ldapi.ldmnq.com
127.0.0.1 res.ldmnq.com
127.0.0.1 mngt.ldmnq.com
127.0.0.1 api-ad.ldmnq.com
"@ | Out-File "$env:TEMP\ld_hosts" -Encoding ascii

.\adb.exe -s $s push "$env:TEMP\ld_hosts" /data/local/tmp/hosts
.\adb.exe -s $s shell "su -c 'mount -o remount,rw /; cp /data/local/tmp/hosts /system/etc/hosts; chmod 644 /system/etc/hosts; sync; cat /system/etc/hosts'"
```

### 3.4 Windows 侧清理

```powershell
$emptyLaunch = '{"handles":[],"msgAd":{},"videoAD":{},"bgAdweb":{"ad":[],"npid":""},"bgAd":{"ad":[],"npid":""},"bgAdex":{"ad":[],"npid":""},"cache":{}}'
$emptyFirst  = '{"code":200,"msg":"ok","data":{"bigEvents":[],"specialZones":[],"recommendZone":{"type":0,"articles":[],"categoryRecommends":[]}}}'

foreach ($base in @("$env:APPDATA\leidian9", "$env:APPDATA\Leidian9")) {
  if (-not (Test-Path $base)) { continue }
  $cache = Join-Path $base "cache"
  New-Item -ItemType Directory -Path $cache -Force | Out-Null
  Get-ChildItem $cache -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match 'httpsimg_|\.jpg$|\.jpeg$|\.png$|\.gif$|ld_file'
  } | Remove-Item -Force -ErrorAction SilentlyContinue

  foreach ($pair in @(
    @{ Path = Join-Path $base "launcherad.data";    Content = "" },
    @{ Path = Join-Path $cache "launchConfig.data"; Content = $emptyLaunch },
    @{ Path = Join-Path $cache "apppush.data";      Content = "[]" }
  )) {
    Set-ItemProperty $pair.Path -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
    Set-Content -Path $pair.Path -Value $pair.Content -Encoding UTF8 -NoNewline
    Set-ItemProperty $pair.Path -Name IsReadOnly -Value $true
  }
}

$picCache = "$env:USERPROFILE\Documents\leidian9\Pictures\cache"
if (Test-Path $picCache) {
  Get-ChildItem $picCache -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

$apps = "$env:USERPROFILE\Documents\leidian9\Applications"
if (Test-Path $apps) {
  foreach ($pair in @(
    @{ Name = "first_screen.data";      Content = $emptyFirst },
    @{ Name = "first_screen_init.data"; Content = "{}" },
    @{ Name = "init_icon.data";         Content = "{}" }
  )) {
    $fp = Join-Path $apps $pair.Name
    if (Test-Path $fp) {
      Set-ItemProperty $fp -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
      Set-Content -Path $fp -Value $pair.Content -Encoding UTF8 -NoNewline
      Set-ItemProperty $fp -Name IsReadOnly -Value $true
    }
  }
}

# 可选：退出模拟器后禁用 partner
$partner = "D:\leidian\LDPlayer9\ldplayerpartner.exe"
if (Test-Path $partner) {
  Rename-Item $partner "ldplayerpartner.exe.bak_disabled"
}
```

### 3.5 雷电一键脚本（示例）

```powershell
$LD_PATH = "D:\leidian\LDPlayer9"
$s = "emulator-5554"
Set-Location $LD_PATH
& .\adb.exe -s $s wait-for-device

& .\adb.exe -s $s uninstall com.android.flysilkworm 2>$null
& .\adb.exe -s $s shell pm uninstall --user 0 com.android.flysilkworm
& .\adb.exe -s $s shell pm disable-user --user 0 com.android.flysilkworm
& .\adb.exe -s $s shell am force-stop com.android.flysilkworm
& .\adb.exe -s $s shell "su -c 'pm hide com.android.flysilkworm; pm disable com.android.flysilkworm; mount -o remount,rw /; rm -rf /system/priv-app/ldAppStore; rm -rf /data/data/com.android.flysilkworm /data/user/0/com.android.flysilkworm; sync'" 2>$null
& .\adb.exe -s $s shell pm enable com.android.coreservice 2>$null

Write-Host "安卓侧完成。请再执行 3.4 Windows 清理，并 reboot 实例。"
# & .\ldconsole.exe reboot --index 0
```

### 3.6 雷电恢复

```powershell
# 仅禁用未删文件时：
.\adb.exe -s $s shell "su -c 'pm unhide com.android.flysilkworm; pm enable com.android.flysilkworm'"
.\adb.exe -s $s shell cmd package install-existing com.android.flysilkworm

# 已物理删除：需修复/重装模拟器或从备份恢复镜像
# partner：.bak_disabled 改回 ldplayerpartner.exe
```

---

## 四、MuMu 模拟器 12

### 4.1 广告从哪来

| 位置 | 组件 / 路径 | 表现 |
|------|-------------|------|
| 安卓内 | `com.mumu.store`（`/system/priv-app/com.mumu.store`） | 应用中心、推广 |
| 安卓内 | `com.nemu.oaidmanager` | OAID / 标识入口 |
| 安卓内 | 官方桌面 `com.mumu.launcher*` | 桌面推荐位（可用第三方桌面替代） |
| Windows | `%AppData%\Netease\MuMuPlayer\data\ProgramAds` | 程序广告资源 |
| Windows | `...\data\startupImage` | 启动相关图片 |
| Windows | `...\data\msgCenter` | 消息中心缓存 |

**建议保留：** `com.netease.mumu.cloner`（应用多开）、`com.mumu.shared.sdk`、`com.mumu.acc`、输入法/nlp 等。

### 4.2 准备

```powershell
cd D:\MuMu\MuMuPlayer\nx_main

# 查看实例
.\MuMuManager.exe info -v all

# 连接 ADB（实例 0）
.\MuMuManager.exe adb -v 0 -c connect
# 常见端口：127.0.0.1:16384

.\adb.exe connect 127.0.0.1:16384
.\adb.exe devices

$s = "127.0.0.1:16384"
.\adb.exe -s $s shell "su -c id"
# 期望：uid=0(root) —— 设置中打开 Root
```

多开时对每个**已启动**实例分别 `adb -v N -c connect`，端口以 `adb devices` 为准。

### 4.3 安卓侧清理（核心）

```powershell
$s = "127.0.0.1:16384"

# 用户卸载 + 禁用 + 隐藏
.\adb.exe -s $s uninstall com.mumu.store
.\adb.exe -s $s shell pm uninstall --user 0 com.mumu.store
.\adb.exe -s $s shell pm disable-user --user 0 com.mumu.store
.\adb.exe -s $s shell am force-stop com.mumu.store
.\adb.exe -s $s shell "su -c 'pm hide com.mumu.store; pm disable com.mumu.store'"

# 物理删除（Root 后系统盘通常可写）
.\adb.exe -s $s shell "su -c 'mount -o remount,rw /system; rm -rf /system/priv-app/com.mumu.store; rm -rf /data/data/com.mumu.store /data/user/0/com.mumu.store; ls /system/priv-app | grep mumu'"

# 可选：禁用 OAID
.\adb.exe -s $s shell pm disable-user --user 0 com.nemu.oaidmanager
.\adb.exe -s $s shell am force-stop com.nemu.oaidmanager
.\adb.exe -s $s shell "su -c 'pm hide com.nemu.oaidmanager; pm disable com.nemu.oaidmanager'"

# 验证启动器无商店
.\adb.exe -s $s shell "cmd package query-activities -a android.intent.action.MAIN -c android.intent.category.LAUNCHER"
.\adb.exe -s $s shell pm path com.mumu.store
```

桌面若仍有官方推荐位，可安装第三方桌面（如 Lawnchair）并设为默认。

### 4.4 Windows 侧清理

```powershell
$base = "$env:APPDATA\Netease\MuMuPlayer\data"

foreach ($dir in @("ProgramAds", "msgCenter")) {
  $p = Join-Path $base $dir
  if (Test-Path $p) {
    Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue |
      Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "cleared $dir"
  }
}

$startup = Join-Path $base "startupImage"
if (Test-Path $startup) {
  Get-ChildItem $startup -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
    try { $_.Attributes = 'Normal' } catch {}
  }
  Get-ChildItem $startup -Directory -Force -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  $im = Join-Path $startup "imageManager.json"
  if (Test-Path $im) {
    Set-ItemProperty $im -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
    Set-Content $im -Value '{"images":[],"list":[]}' -Encoding UTF8 -NoNewline
    Set-ItemProperty $im -Name IsReadOnly -Value $true
  }
  Write-Host "cleared startupImage"
}

$fstore = Join-Path $base "fcount\fcountData_store.ini"
if (Test-Path $fstore) {
  Set-Content $fstore -Value "" -Encoding ASCII -NoNewline
}
```

### 4.5 MuMu 一键脚本（示例，实例 0）

```powershell
$MAIN = "D:\MuMu\MuMuPlayer\nx_main"
$INDEX = 0
$s = "127.0.0.1:16384"   # 以 adb devices 为准

Set-Location $MAIN
& .\MuMuManager.exe adb -v $INDEX -c connect | Out-Null
& .\adb.exe connect $s | Out-Null

& .\adb.exe -s $s uninstall com.mumu.store 2>$null
& .\adb.exe -s $s shell pm uninstall --user 0 com.mumu.store
& .\adb.exe -s $s shell pm disable-user --user 0 com.mumu.store
& .\adb.exe -s $s shell am force-stop com.mumu.store
& .\adb.exe -s $s shell "su -c 'pm hide com.mumu.store; pm disable com.mumu.store; mount -o remount,rw /system; rm -rf /system/priv-app/com.mumu.store; rm -rf /data/data/com.mumu.store /data/user/0/com.mumu.store'" 2>$null

& .\adb.exe -s $s shell pm disable-user --user 0 com.nemu.oaidmanager 2>$null
& .\adb.exe -s $s shell "su -c 'pm hide com.nemu.oaidmanager; pm disable com.nemu.oaidmanager'" 2>$null

# Windows（可另存后单独跑 4.4）
Write-Host "安卓侧完成。请再执行 4.4 Windows 清理。"
```

### 4.6 MuMu 恢复

```powershell
# 仅禁用、系统文件还在时：
.\adb.exe -s $s shell "su -c 'pm unhide com.mumu.store; pm enable com.mumu.store'"
.\adb.exe -s $s shell cmd package install-existing com.mumu.store

# 已物理删除：需重装/修复 MuMu 或从备份镜像恢复
```

---

## 五、效果自检

### 雷电

- [ ] 桌面无「雷电游戏中心」
- [ ] `pm path com.android.flysilkworm` 无结果
- [ ] `/system/priv-app/ldAppStore` 不存在
- [ ] 共享文件夹等正常（`coreservice` 启用）
- [ ] 客户端启动广告减轻（配合 Windows 清理）

### MuMu

- [ ] 桌面无「应用中心 / 商店」
- [ ] `pm path com.mumu.store` 无结果
- [ ] `/system/priv-app/` 无 `com.mumu.store`
- [ ] 应用多开仍可用（cloner 保留）
- [ ] 启动图 / 程序广告减轻（配合 Windows 清理）

---

## 六、常见问题

**Q：`pm uninstall` 报 `DELETE_FAILED_INTERNAL_ERROR`？**  
A：系统应用直接卸常失败。用 `pm uninstall --user 0` 或 Root 删系统目录。

**Q：系统盘 remount 失败 / Read-only？**  
A：打开 Root 与（雷电）系统盘可写，重启后再测。做不到物理删除时，「用户卸载 + 禁用 + 隐藏」仍可用。

**Q：删了目录后 dumpsys 还显示 codePath？**  
A：包管理器可能缓存元数据；**重启实例** 后以 `pm path` / `pm list packages` 为准。

**Q：新建实例 / 升级后又有广告？**  
A：操作只作用于当前实例磁盘。新实例或升级后重做对应章节。

**Q：Windows 广告图又回来了？**  
A：客户端会重新下载，重复第四节 / 4.4 即可；或配合 hosts。

**Q：Windows hosts 需要管理员吗？**  
A：改 `C:\Windows\System32\drivers\etc\hosts` 需要。雷电可优先写模拟器内 `/system/etc/hosts`。

**Q：会影响拖入安装 APK / 多开吗？**  
A：一般不影响。雷电保留 coreservice；MuMu 保留 cloner。从电脑拖 APK 或 `adb install` 不受商店删除影响。

---

## 七、本机实测结果

### 雷电 9（`D:\leidian\LDPlayer9`）

| 项目 | 结果 |
|------|------|
| 设备 | 实例 0，`emulator-5554` |
| Root / 系统盘 | 可写，`WRITE_OK` |
| 游戏中心 | 已删 `/system/priv-app/ldAppStore`；重启后包列表无 flysilkworm |
| hosts | 已写入 `/system/etc/hosts` |
| Windows | 配置清空；`ldplayerpartner.exe` → `.bak_disabled` |

### MuMu 12（`D:\MuMu\MuMuPlayer`）

| 项目 | 结果 |
|------|------|
| 设备 | 实例 0，`127.0.0.1:16384` |
| Root | 已开启，`/system` 可写 |
| 应用中心 | 用户卸载 + 禁用；已删 `/system/priv-app/com.mumu.store` |
| OAID | 已禁用 + 隐藏 |
| Windows | 已清 ProgramAds / startupImage / msgCenter |
| 保留 | cloner、shared.sdk 等 |

---

## 八、最短操作摘要

| 雷电 | MuMu |
|------|------|
| 1. Root + 系统盘可写，启动 | 1. Root，启动，`MuMuManager adb -v 0 -c connect` |
| 2. `pm uninstall --user 0 com.android.flysilkworm` + disable/hide | 2. `pm uninstall --user 0 com.mumu.store` + disable/hide |
| 3. `rm -rf /system/priv-app/ldAppStore` | 3. `rm -rf /system/priv-app/com.mumu.store` |
| 4. 清 `%AppData%\leidian9`，可选改名 partner | 4. 清 `%AppData%\Netease\MuMuPlayer\data` 广告目录 |
| 5. 保留 coreservice，reboot 验证 | 5. 保留 cloner，验证桌面 |

---

*融合自雷电与 MuMu 分册操作记录。路径、端口请按本机修改后使用。*
