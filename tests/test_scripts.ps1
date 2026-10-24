# 部署脚本静态检查
#
# 检查的是「脚本写法上的隐患」，不是运行时行为 —— 这些坑在真实部署里都踩过，
# 用静态规则拦住，比每次靠人工回忆可靠。
#
# 用法：.\tests\test_scripts.ps1
# 退出码：0 全部通过；1 有失败项

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$results = New-Object System.Collections.Generic.List[object]

function Add-Check {
    <#
    .SYNOPSIS
        记录一项检查结果。
    .PARAMETER Name
        检查项名称。
    .PARAMETER Ok
        是否通过。
    .PARAMETER Detail
        证据或失败原因。
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Ok,
        [string]$Detail = ''
    )
    $results.Add([pscustomobject]@{ Name = $Name; Ok = $Ok; Detail = $Detail })
    $mark = if ($Ok) { 'PASS' } else { 'FAIL' }
    $color = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1}" -f $mark, $Name) -ForegroundColor $color
    if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkGray }
}

function Get-CodeLines {
    <#
    .SYNOPSIS
        读取脚本文件，返回「去掉注释后的代码行」。
    .DESCRIPTION
        必须同时处理两种注释：
          * 单行注释   以 # 开头
          * 注释块     以 <# 开始、以 # 加 > 结束（注释式帮助文档就在这个块里，
            里面的示例代码会被朴素的行匹配误判成真实代码）

        注意：本说明里刻意不写出完整的注释块起止符号 —— 在注释块内部再写一次
        「结束符号」会**提前闭合当前注释块**，导致后面的代码被当作文本。
        这个坑在写这段代码时真实踩了一次。
        返回的是 [pscustomobject] 数组，含 LineNumber 与 Text。
    .PARAMETER Path
        脚本文件路径。
    #>
    param([Parameter(Mandatory)][string]$Path)

    $result = @()
    $inBlock = $false
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($inBlock) {
            if ($line -match '#>') { $inBlock = $false }
            continue
        }
        if ($line -match '<#') {
            if ($line -notmatch '#>') { $inBlock = $true }
            continue
        }
        if ($line -match '^\s*#') { continue }
        $result += [pscustomobject]@{ LineNumber = $i + 1; Text = $line }
    }
    return $result
}

Write-Host ''
Write-Host '  Ydisks闲鱼助手 · 部署脚本静态检查' -ForegroundColor White
Write-Host ('  ' + ('─' * 62)) -ForegroundColor DarkGray

# 排除 schema 自身：检查器里写的规则字符串（正则、示例）会被自己的规则命中，
# 这是典型的「自检误报」。只检查被检查对象。
$scripts = Get-ChildItem -Path 'deploy', 'tests' -Recurse -Filter '*.ps1' |
    Where-Object { $_.Name -notlike '_*' -and $_.Name -ne 'test_scripts.ps1' }
Add-Check -Name '找到部署脚本' -Ok ($scripts.Count -ge 8) -Detail "$($scripts.Count) 个"

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '  1. 语法' -ForegroundColor Cyan

$syntaxBad = @()
foreach ($s in $scripts) {
    $errors = $null
    $tokens = $null
    [System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        $syntaxBad += "$($s.Name): $($errors[0].Message) (行 $($errors[0].Extent.StartLineNumber))"
    }
}
Add-Check -Name '全部脚本可被 PowerShell 解析' -Ok ($syntaxBad.Count -eq 0) -Detail $(
    if ($syntaxBad.Count -eq 0) { "$($scripts.Count) 个脚本" } else { $syntaxBad -join '; ' }
)

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '  2. 已知陷阱（这些坑都真实踩过）' -ForegroundColor Cyan

# (a) 不允许把 ${{ ... }} 这种 GitHub 表达式误写进 PowerShell（会当字面量）
$ghExpr = @()
foreach ($s in $scripts) {
    foreach ($l in (Get-CodeLines -Path $s.FullName)) {
        if ($l.Text -match '\$\{\{') { $ghExpr += "$($s.Name):$($l.LineNumber)" }
    }
}
Add-Check -Name '没有误写 GitHub 表达式 ${{ }}' -Ok ($ghExpr.Count -eq 0) -Detail $(if ($ghExpr) { $ghExpr -join ', ' } else { '无' })

# (b) 不允许直接用 (Get-Command xxx).Source 拼 Start-Process ——
#     Windows 上 npm 会解析成 npm.ps1，Start-Process 无法执行
$directSource = @()
foreach ($s in $scripts) {
    foreach ($l in (Get-CodeLines -Path $s.FullName)) {
        if ($l.Text -match '\(Get-Command\s+\w+\)\.Source' -and $s.Name -ne 'common.ps1') {
            $directSource += "$($s.Name):$($l.LineNumber)"
        }
    }
}
Add-Check -Name '没有直接使用 (Get-Command x).Source（应走 Get-ToolPath）' `
    -Ok ($directSource.Count -eq 0) -Detail $(if ($directSource) { $directSource -join ', ' } else { '无' })

# (c) Start-Process -Wait 不允许用于可能派生子孙进程的程序 —— 会永远等下去。
#     跳过注释行：common.ps1 的参数说明里会引用这个写法做解释。
$waitUsage = @()
foreach ($s in $scripts) {
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*#') { continue }
        if ($lines[$i] -match 'Start-Process[^\n]*-Wait') { $waitUsage += "$($s.Name):$($i + 1)" }
    }
}
Add-Check -Name '没有裸用 Start-Process -Wait（应带超时）' `
    -Ok ($waitUsage.Count -eq 0) -Detail $(if ($waitUsage) { $waitUsage -join ', ' } else { '无' })

# (d) Write-Host 里的 '  ' + (...) 必须加括号，否则 '+' 会被当字面量打出来
$bareConcat = @()
foreach ($s in $scripts) {
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "Write-Host\s+'[^']*'\s*\+\s*\(") { $bareConcat += "$($s.Name):$($i + 1)" }
    }
}
Add-Check -Name "Write-Host 字符串拼接已加括号" -Ok ($bareConcat.Count -eq 0) `
    -Detail $(if ($bareConcat) { $bareConcat -join ', ' } else { '无' })

# (e) 不允许硬编码管理员密码（除文档示例外）
$hardPwd = @()
foreach ($s in $scripts) {
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "=\s*'[A-Za-z0-9@#\$]{8,}'\s*$" -and $lines[$i] -match 'assword') {
            $hardPwd += "$($s.Name):$($i + 1)"
        }
    }
}
Add-Check -Name '没有硬编码密码' -Ok ($hardPwd.Count -eq 0) -Detail $(if ($hardPwd) { $hardPwd -join ', ' } else { '无' })

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '  3. 结构约定' -ForegroundColor Cyan

# 每个脚本都必须 dot-source common.ps1（除 common 自身）
$noCommon = @()
foreach ($s in $scripts) {
    if ($s.Name -eq 'common.ps1') { continue }
    $txt = Get-Content -LiteralPath $s.FullName -Raw -Encoding UTF8
    if ($txt -notmatch 'common\.ps1') { $noCommon += $s.Name }
}
Add-Check -Name '除 common.ps1 外都引用了公共层' -Ok ($noCommon.Count -eq 0) `
    -Detail $(if ($noCommon) { $noCommon -join ', ' } else { '全部引用' })

# 每个脚本都要有 .SYNOPSIS（便于 Get-Help）
$noSynopsis = @()
foreach ($s in $scripts) {
    $txt = Get-Content -LiteralPath $s.FullName -Raw -Encoding UTF8
    if ($txt -notmatch '\.SYNOPSIS') { $noSynopsis += $s.Name }
}
Add-Check -Name '全部脚本带 .SYNOPSIS 注释块' -Ok ($noSynopsis.Count -eq 0) `
    -Detail $(if ($noSynopsis) { $noSynopsis -join ', ' } else { '全部具备' })

# 兼容 Windows PowerShell 5.1：不允许用 PS7 专属语法
$ps7Only = @()
foreach ($s in $scripts) {
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*#') { continue }
        # ForEach-Object -Parallel 与空合并赋值 ??= 都是 PS7 专属
        if ($lines[$i] -match 'ForEach-Object\s+-Parallel') { $ps7Only += "$($s.Name):$($i+1)(-Parallel)" }
        if ($lines[$i] -match '\?\?=') { $ps7Only += "$($s.Name):$($i+1)(??=)" }
    }
}
Add-Check -Name '未使用 PowerShell 7 专属语法' -Ok ($ps7Only.Count -eq 0) `
    -Detail $(if ($ps7Only) { $ps7Only -join ', ' } else { '兼容 5.1' })

# 危险目录操作必须限定在本仓库内
$dangerous = @()
foreach ($s in $scripts) {
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*#') { continue }
        # 形如 Remove-Item C:\ -Recurse 之类的绝对路径删除
        if ($lines[$i] -match 'Remove-Item\s+["'']?[A-Za-z]:\\\\?["'']?\s' -or
            $lines[$i] -match 'Remove-Item\s+["'']?[/\\]["'']?\s') {
            $dangerous += "$($s.Name):$($i + 1)"
        }
    }
}
Add-Check -Name '没有危险的根目录删除操作' -Ok ($dangerous.Count -eq 0) `
    -Detail $(if ($dangerous) { $dangerous -join ', ' } else { '无' })

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '  4. 仓库卫生' -ForegroundColor Cyan

$gitignore = Get-Content -LiteralPath '.gitignore' -Raw -Encoding UTF8
$needIgnore = @('app/', 'runtime/', 'data/', 'logs/')
$missing = $needIgnore | Where-Object { $gitignore -notmatch [regex]::Escape($_) }
Add-Check -Name '.gitignore 覆盖生成物目录' -Ok ($missing.Count -eq 0) `
    -Detail $(if ($missing) { "缺少：$($missing -join ', ')" } else { 'app/ runtime/ data/ logs/ 均已忽略' })

# data.key 与凭据文件必须被忽略
$secretIgnored = ($gitignore -match 'data\.key') -and ($gitignore -match '初始管理员凭据')
Add-Check -Name '.gitignore 覆盖敏感文件' -Ok $secretIgnored `
    -Detail $(if ($secretIgnored) { 'data.key 与凭据文件均已忽略' } else { '缺少 data.key 或凭据文件的忽略规则' })

# .bat 必须是 CRLF
$batBad = @()
Get-ChildItem -Filter '*.bat' | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    $bareLf = ([regex]::Matches($text, "(?<!`r)`n")).Count
    if ($bareLf -gt 0) { $batBad += "$($_.Name)($bareLf 个裸 LF)" }
}
Add-Check -Name '批处理文件均为 CRLF 换行' -Ok ($batBad.Count -eq 0) `
    -Detail $(if ($batBad) { $batBad -join ', ' } else { "全部 $((Get-ChildItem -Filter '*.bat').Count) 个" })

# ---------------------------------------------------------------------------
$passed = @($results | Where-Object { $_.Ok }).Count
$failed = @($results | Where-Object { -not $_.Ok }).Count

Write-Host ''
Write-Host ('  ' + ('═' * 62)) -ForegroundColor DarkGray
$color = if ($failed -eq 0) { 'Green' } else { 'Red' }
Write-Host "  检查结论：通过 $passed / 失败 $failed / 共 $($results.Count)" -ForegroundColor $color
Write-Host ('  ' + ('═' * 62)) -ForegroundColor DarkGray

if ($failed -gt 0) {
    Write-Host ''
    $results | Where-Object { -not $_.Ok } | ForEach-Object {
        Write-Host "  ✗ $($_.Name)" -ForegroundColor Red
        Write-Host "    $($_.Detail)" -ForegroundColor DarkGray
    }
    exit 1
}
Write-Host ''
exit 0