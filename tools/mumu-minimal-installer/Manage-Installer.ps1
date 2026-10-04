param(
    [ValidateSet('Check', 'Install', 'Restore')][string]$Action = 'Check',
    [string]$MuMuPath,
    [int]$Index = -1
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$packageName = 'com.mumu.store'
$apkPath = Join-Path $PSScriptRoot 'build\mumu-minimal-installer-0.1.apk'
$expectedApkHash = 'a03ba9b5286402b4db0df9796a3bcbb82785cd49ac92f5c2ad4638235c63b43a'

function Find-MuMuPath {
    foreach ($process in @(Get-Process -Name MuMuNxDevice, MuMu, MuMuManager -ErrorAction SilentlyContinue)) {
        if (-not $process.Path) { continue }
        $directory = Split-Path -Parent $process.Path
        for ($level = 0; $level -lt 5 -and $directory; $level++) {
            if (Test-Path -LiteralPath (Join-Path $directory 'nx_main\MuMuManager.exe')) { return $directory }
            $directory = Split-Path -Parent $directory
        }
    }
    return $null
}
function Invoke-Manager([string[]]$Arguments) {
    $text = & $script:managerPath @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "MuMuManager 执行失败：$text" }
    return ($text | ConvertFrom-Json)
}
function Invoke-Adb([string[]]$Arguments, [switch]$PermitUninstallSuccess) {
    $text = & $script:adbPath -s $script:serial @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        # This MuMu pm command returns 1 even after a successful system-update rollback.
        # Permit only this exact operation; its resulting version and path are checked below.
        $knownRollback = ($Arguments -join ' ') -eq 'shell pm uninstall-system-updates com.mumu.store'
        if (-not ($PermitUninstallSuccess -and $knownRollback -and $text -match '(?m)^Success[\r ]*$')) {
            throw "ADB 执行失败：$text"
        }
    }
    return $text.Trim()
}
function Get-StoreState {
    $dump = Invoke-Adb -Arguments @('shell', 'dumpsys', 'package', $packageName)
    $version = [regex]::Match($dump, 'versionCode=(\d+)')
    $state = [regex]::Match($dump, 'User 0:([^\r\n]+)')
    if (-not $version.Success -or -not $state.Success) { throw '没有找到原系统商店包。请先修复原实例或在新实例中操作。' }
    return @{ Version = [int]$version.Groups[1].Value; User = $state.Groups[1].Value; Dump = $dump }
}

try {
    if (-not $MuMuPath) { $MuMuPath = Find-MuMuPath }
    if (-not $MuMuPath) { $MuMuPath = Read-Host '请输入 MuMu 安装目录（里面应有 nx_main 文件夹）' }
    $MuMuPath = $MuMuPath.Trim().Trim('"')
    if ((Split-Path -Leaf $MuMuPath) -eq 'nx_main') { $MuMuPath = Split-Path -Parent $MuMuPath }
    $script:managerPath = Join-Path $MuMuPath 'nx_main\MuMuManager.exe'
    $script:adbPath = Join-Path $MuMuPath 'nx_main\adb.exe'
    if (-not (Test-Path -LiteralPath $managerPath) -or -not (Test-Path -LiteralPath $adbPath)) { throw '安装目录不正确：找不到 MuMuManager.exe 或 adb.exe。' }

    $info = Invoke-Manager -Arguments @('info', '-v', 'all')
    $players = @($info.PSObject.Properties | ForEach-Object { $_.Value } | Where-Object { $_.is_android_started })
    if ($players.Count -eq 0) { throw '请先启动要处理的 MuMu 实例，等到安卓桌面出现后再运行。' }
    Write-Host '已启动的实例：'
    foreach ($player in $players) { Write-Host ("  编号 {0}：{1}（Android {2}）" -f $player.index, $player.name, $player.android_version) }
    if ($Index -lt 0) {
        $chosen = Read-Host '请输入要处理的实例编号'
        $parsed = 0
        if (-not [int]::TryParse($chosen, [ref]$parsed)) { throw '实例编号必须是列表中的数字。' }
        $Index = $parsed
    }
    $selected = @($players | Where-Object { [string]$_.index -eq [string]$Index })
    if ($selected.Count -ne 1) { throw '该编号不在已启动实例列表中。' }
    $player = $selected[0]
    if ($player.android_version -notmatch '^15(?:\.|$)') { throw '这个版本仅验证过 Android 15，不能用于 Android 12 实例。请阅读文档中的临时安装方法。' }
    if ($player.adb_host_ip -ne '127.0.0.1' -or [int]$player.adb_port -lt 1024 -or [int]$player.adb_port -gt 65535) { throw '实例的本地 ADB 地址无效。' }
    $script:serial = '127.0.0.1:' + $player.adb_port
    $connect = & $adbPath connect $serial 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $connect -match 'cannot connect|failed|refused') { throw 'ADB 连接失败。请在 MuMu 设置中打开 ADB 调试（本地连接），然后重试。' }
    Write-Host ("目标：编号 {0}，{1}，ADB {2}" -f $Index, $player.name, $serial)

    $systemApk = Invoke-Adb -Arguments @('shell', 'ls', '/system/priv-app/com.mumu.store/com.mumu.store.apk')
    if ($systemApk -ne '/system/priv-app/com.mumu.store/com.mumu.store.apk') { throw '原系统商店 APK 不完整。不要继续：请备份实例，再修复或使用新实例。' }
    $state = Get-StoreState
    if ($state.Version -notin @(1225, 1226)) { throw "商店版本号为 $($state.Version)，本工具只验证过 1225 / 本原型 1226，未执行修改。" }
    if ($state.Dump -notmatch 'android\.uid\.system/1000') { throw '商店不是预期的系统共享 UID，未执行修改。' }
    if ($state.User -match 'hidden=true') { throw '原商店仍处于隐藏状态，请先按文档恢复隐藏，再运行本工具。' }
    Write-Host "当前商店版本号：$($state.Version)"
    if ($Action -eq 'Check') {
        Write-Host '检查通过。本次没有更新、启用或卸载商店。'
        exit 0
    }

    if ($Action -eq 'Install') {
        if (-not (Test-Path -LiteralPath $apkPath)) { throw '缺少 APK。请下载 Release 中的完整工具 ZIP 并解压，不要只下载仓库源码。' }
        $hashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
        $apkStream = [IO.File]::OpenRead($apkPath)
        try {
            $hash = [BitConverter]::ToString($hashAlgorithm.ComputeHash($apkStream)).Replace('-', '').ToLowerInvariant()
        } finally {
            $apkStream.Dispose()
            $hashAlgorithm.Dispose()
        }
        if ($hash -ne $expectedApkHash) { throw 'APK 校验失败，请重新下载该版本的完整工具 ZIP。' }
        if ($state.Version -eq 1226 -and $state.Dump -notmatch 'versionName=minimal-prototype-0\.1') { throw '版本号 1226 已被其他商店版本使用，未执行修改。' }
        if ($state.User -match 'installed=false') { Invoke-Adb -Arguments @('shell', 'cmd', 'package', 'install-existing', '--user', '0', $packageName) | Write-Host }
        if ($state.User -notmatch 'enabled=0(?:\s|$)') { Invoke-Adb -Arguments @('shell', 'pm', 'default-state', '--user', '0', $packageName) | Write-Host }
        $ready = Get-StoreState
        if ($ready.User -notmatch 'installed=true' -or $ready.User -match 'hidden=true' -or $ready.User -notmatch 'enabled=0(?:\s|$)') { throw '商店用户状态恢复失败，未安装替代包。' }
        Invoke-Adb -Arguments @('install', '--no-incremental', '-r', $apkPath) | Write-Host
        $after = Get-StoreState
        if ($after.Version -ne 1226 -or $after.Dump -notmatch 'versionName=minimal-prototype-0\.1') { throw '安装后的版本校验失败，请保存窗口输出并反馈。' }
        Write-Host '最小安装器已安装。请重启这个实例，再拖入一个普通 APK 测试。'
        Write-Host '不要再禁用、隐藏或删除 com.mumu.store。需要恢复原商店时双击 Restore.cmd。'
    } else {
        if ($state.Version -eq 1225) { Write-Host '当前已是原商店，无需恢复。'; exit 0 }
        if ($state.Dump -notmatch 'versionName=minimal-prototype-0\.1') { throw '当前更新包不是本原型，未卸载它。' }
        Invoke-Adb -Arguments @('shell', 'pm', 'uninstall-system-updates', $packageName) -PermitUninstallSuccess | Write-Host
        $after = Get-StoreState
        if ($after.Version -ne 1225) { throw '回退后的版本不是预期值，请保存窗口输出并反馈。' }
        $restoredPath = Invoke-Adb -Arguments @('shell', 'pm', 'path', $packageName)
        if ($restoredPath -ne 'package:/system/priv-app/com.mumu.store/com.mumu.store.apk') { throw '回退后没有使用原系统 APK，请保存窗口输出并反馈。' }
        Write-Host '原商店已恢复。请重启这个实例。'
    }
} catch {
    Write-Host ("操作停止：{0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
