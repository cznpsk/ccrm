# ccrm — จัดการ sessions ของ Claude Code + Codex + Kimi + Gemini แบบ interactive (fzf) สำหรับ Windows PowerShell
# ใช้: ccrm -> Claude ทุก project + Codex/Kimi/Gemini ทั้งหมด
# คีย์: Enter=resume, Tab=เลือกจะลบ, กด Tab อีกครั้งบนบรรทัดเดิม=ยืนยันลบ, Esc=ยกเลิก
# หมายเหตุ gemini: --resume ของตัว CLI เองรับแค่ "latest"/index ผูกกับ project ปัจจุบัน
#   ไม่มี resume-by-id ตรงๆ เลยใช้ --session-file แทน (ต้อง cd เข้า project เดิมก่อนเสมอ)
param(
  [switch]$All,
  [switch]$ListOnly,
  [switch]$PreviewLine,
  [string]$Line,
  [switch]$TabTransform,
  [string]$Sel,
  [string]$Cur,
  [switch]$DeletePath,
  [string]$Target,
  [switch]$Auto
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch {}
# progress bar ของ Invoke-WebRequest ใน PS 5.1 ทำให้โหลดไฟล์ใหญ่ช้าเป็นสิบเท่า
$ProgressPreference = 'SilentlyContinue'

# กันกรณี ccrm.cmd เวอร์ชันเก่าส่ง "update" ทะลุมาเป็น positional arg
if ($Line -eq 'update') {
  $u = 'https://github.com/cznpsk/ccrm/releases/latest/download/install.ps1?ts=' + [DateTimeOffset]::Now.ToUnixTimeSeconds()
  Invoke-Expression (Invoke-WebRequest -UseBasicParsing -Uri $u).Content
  exit 0
}

if ($DeletePath) {
  if ($Target) { Remove-Item -LiteralPath $Target -Recurse -Force -ErrorAction SilentlyContinue }
  exit 0
}

if ($TabTransform) {
  $cnt = 0
  [void][int]::TryParse($env:FZF_SELECT_COUNT, [ref]$cnt)
  $ps = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
  $allFlag = if ($All) { ' -All' } else { '' }
  if ($cnt -gt 0 -and $Sel -eq $Cur) {
    Write-Output ('execute-silent(' + $ps + ' -DeletePath -Target {1})+reload(' + $ps + ' -ListOnly' + $allFlag + ')+clear-selection')
  } else {
    Write-Output 'clear-selection+toggle'
  }
  exit 0
}

# อ่านไฟล์ผ่าน .NET ตรงๆ — เลี่ยง Get-Content -Encoding ที่เป็น dynamic param แล้วพังบนบางเครื่อง (PS 5.1)
function Read-FileLines([string]$p, [int]$max = 0) {
  try {
    if ($max -gt 0) { return @([System.IO.File]::ReadLines($p) | Select-Object -First $max) }
    return @([System.IO.File]::ReadAllLines($p))
  } catch { return @() }
}

function Read-FileRaw([string]$p) {
  try { return [System.IO.File]::ReadAllText($p) } catch { return $null }
}

function Format-Size([long]$bytes) {
  if ($bytes -ge 1GB) { return ("{0:N1}G" -f ($bytes / 1GB)) }
  elseif ($bytes -ge 1MB) { return ("{0:N1}M" -f ($bytes / 1MB)) }
  elseif ($bytes -ge 1KB) { return ("{0:N1}K" -f ($bytes / 1KB)) }
  else { return "$bytes" }
}

function Get-DirSize([string]$dir) {
  $sum = (Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
  if (-not $sum) { $sum = 0 }
  return [long]$sum
}

function Get-ClaudeLabel([string]$sPath) {
  # customTitle มาจาก /rename — โดน append ท้ายไฟล์ ต้อง scan ทั้งไฟล์ เอาอันล่าสุด
  $m = Select-String -LiteralPath $sPath -Pattern '"customTitle":"([^"]*)"' -ErrorAction SilentlyContinue | Select-Object -Last 1
  if ($m) {
    $val = $m.Matches[0].Groups[1].Value
    if ($val) { return $val.Substring(0, [Math]::Min(70, $val.Length)) }
  }
  $lines = Read-FileLines $sPath 200
  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $obj = $null
    try { $obj = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
    if ($obj.type -eq 'user' -and -not $obj.isMeta) {
      $content = $obj.message.content
      $text = $null
      if ($content -is [string]) {
        $text = $content
      } elseif ($content) {
        $parts = @()
        foreach ($p in $content) { if ($p.type -eq 'text') { $parts += $p.text } }
        $text = ($parts -join ' ')
      }
      if ($text -and -not $text.StartsWith('<')) {
        return $text.Substring(0, [Math]::Min(70, $text.Length))
      }
    }
  }
  return '(ว่าง)'
}

function Get-CodexLabel([string]$sPath) {
  $fname = [System.IO.Path]::GetFileNameWithoutExtension($sPath)
  if ($fname -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
    $id = $matches[1]
    $idx = Join-Path $HOME '.codex\session_index.jsonl'
    $m = Select-String -LiteralPath $idx -Pattern ('"' + $id + '"') -SimpleMatch -ErrorAction SilentlyContinue | Select-Object -Last 1
    if ($m) {
      try {
        $name = ($m.Line | ConvertFrom-Json).thread_name
        if ($name) { return $name.Substring(0, [Math]::Min(70, $name.Length)) }
      } catch {}
    }
  }
  $lines = Read-FileLines $sPath 200
  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $obj = $null
    try { $obj = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
    if ($obj.type -eq 'response_item' -and $obj.payload.role -eq 'user') {
      foreach ($c in $obj.payload.content) {
        if ($c.type -eq 'input_text' -and $c.text -and -not $c.text.StartsWith('<')) {
          return $c.text.Substring(0, [Math]::Min(70, $c.text.Length))
        }
      }
    }
  }
  return '(ว่าง)'
}

function Get-KimiLabel([string]$sessionDir) {
  $statePath = Join-Path $sessionDir 'state.json'
  $title = $null
  try {
    $state = Read-FileRaw $statePath | ConvertFrom-Json
    if ($state.title -and $state.title -ne 'New Session') { $title = $state.title }
  } catch {}
  if (-not $title) {
    $wirePath = Join-Path $sessionDir 'agents\main\wire.jsonl'
    $lines = Read-FileLines $wirePath
    foreach ($line in $lines) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      $obj = $null
      try { $obj = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
      if ($obj.type -eq 'turn.prompt' -and $obj.origin.kind -eq 'user') {
        foreach ($p in $obj.input) {
          if ($p.type -eq 'text' -and $p.text) { $title = $p.text; break }
        }
      }
      if ($title) { break }
    }
  }
  if (-not $title) { return '(ว่าง)' }
  return $title.Substring(0, [Math]::Min(70, $title.Length))
}

function Get-GeminiLabel([string]$sPath) {
  try {
    $data = Read-FileRaw $sPath | ConvertFrom-Json
  } catch { return '(ว่าง)' }
  foreach ($m in $data.messages) {
    if ($m.type -eq 'user') {
      foreach ($c in $m.content) {
        if ($c.text) { return $c.text.Substring(0, [Math]::Min(70, $c.text.Length)) }
      }
    }
  }
  return '(ว่าง)'
}

# หา customTitle เฉพาะช่วง byte ที่งอกใหม่ (jsonl append-only) — ไม่อ่านไฟล์ใหญ่ซ้ำทั้งไฟล์
function Get-TailTitle([string]$p, [long]$from) {
  try {
    $fs = [System.IO.File]::OpenRead($p)
    [void]$fs.Seek($from, [System.IO.SeekOrigin]::Begin)
    $sr = New-Object System.IO.StreamReader($fs)
    $txt = $sr.ReadToEnd()
    $sr.Close()
    $ms = [regex]::Matches($txt, '"customTitle":"([^"]*)"')
    if ($ms.Count -gt 0) {
      $v = $ms[$ms.Count - 1].Groups[1].Value
      if ($v) { return $v.Substring(0, [Math]::Min(70, $v.Length)) }
    }
  } catch {}
  return $null
}

function Get-SessionRows([bool]$includeAll) {
  $base = Join-Path $HOME '.claude\projects'
  $claudeFiles = @()
  if (Test-Path $base) {
    $claudeFiles = @(Get-ChildItem -Path (Join-Path $base '*\*.jsonl') -File -ErrorAction SilentlyContinue)
  }

  $codexDirs = @((Join-Path $HOME '.codex\sessions'), (Join-Path $HOME '.codex\archived_sessions')) | Where-Object { Test-Path $_ }
  $codexFiles = @()
  if ($codexDirs) {
    $codexFiles = @(Get-ChildItem -Path $codexDirs -Filter *.jsonl -File -Recurse -ErrorAction SilentlyContinue)
  }

  $kimiBase = Join-Path $HOME '.kimi-code\sessions'
  $kimiStateFiles = @()
  if (Test-Path $kimiBase) {
    $kimiStateFiles = @(Get-ChildItem -Path (Join-Path $kimiBase '*\*\state.json') -File -ErrorAction SilentlyContinue)
  }

  $geminiBase = Join-Path $HOME '.gemini\tmp'
  $geminiFiles = @()
  if (Test-Path $geminiBase) {
    $geminiFiles = @(Get-ChildItem -Path (Join-Path $geminiBase '*\chats\*.json') -File -ErrorAction SilentlyContinue)
  }

  $items = @()
  foreach ($f in $claudeFiles) { $items += [PSCustomObject]@{ Path = $f.FullName; RefPath = $f.FullName; Tag = 'claude'; Time = $f.LastWriteTime; Bytes = $f.Length } }
  foreach ($f in $codexFiles)  { $items += [PSCustomObject]@{ Path = $f.FullName; RefPath = $f.FullName; Tag = 'codex';  Time = $f.LastWriteTime; Bytes = $f.Length } }
  foreach ($f in $kimiStateFiles) {
    $dir = $f.Directory.FullName
    $items += [PSCustomObject]@{ Path = $dir; RefPath = $f.FullName; Tag = 'kimi'; Time = $f.LastWriteTime; Bytes = (Get-DirSize $dir) }
  }
  foreach ($f in $geminiFiles) { $items += [PSCustomObject]@{ Path = $f.FullName; RefPath = $f.FullName; Tag = 'gemini'; Time = $f.LastWriteTime; Bytes = $f.Length } }

  $items = @($items | Sort-Object Time -Descending)

  # cache ชื่อ session ตาม path+mtime — ไฟล์ใหญ่หลักร้อย MB สแกนหา customTitle ครั้งเดียวพอ
  $cacheFile = Join-Path $env:LOCALAPPDATA 'ccrm-labels.tsv'
  # มีวอลต์ = cache อยู่ในวอลต์ด้วย (เก็บข้อความแรกของแต่ละแชท ห้ามหลุดออกมาข้างนอก)
  if (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'ccrm\vault.hc')) {
    $cacheDir = Join-Path $HOME '.claude\.ccrm'
    New-Item -ItemType Directory -Force -Path $cacheDir -ErrorAction SilentlyContinue | Out-Null
    $cacheFile = Join-Path $cacheDir 'labels.tsv'
  }
  $cache = @{}
  $byPath = @{}   # entry ล่าสุดต่อ path — ไว้ทำ incremental scan ของ claude
  foreach ($ln in (Read-FileLines $cacheFile)) {
    $parts = $ln -split "`t", 3
    if ($parts.Count -eq 3) {
      $cache[$parts[0] + '|' + $parts[1]] = $parts[2]
      $n = 0L
      if ([long]::TryParse($parts[1], [ref]$n)) { $byPath[$parts[0]] = @{ Size = $n; Label = $parts[2] } }
    }
  }
  # codex rename เขียนแค่ session_index.jsonl ไม่แตะไฟล์ session — ผูก key กับ mtime ของ index ด้วย
  $codexIdx = Join-Path $HOME '.codex\session_index.jsonl'
  $codexIdxEp = if (Test-Path $codexIdx) { (Get-Item $codexIdx).LastWriteTime.Ticks } else { 0 }
  $newLines = New-Object System.Text.StringBuilder

  $rows = @()
  foreach ($item in $items) {
    $sz = Format-Size $item.Bytes
    $dt = $item.Time.ToString('dd/MM HH:mm')
    $ck = "$($item.Time.Ticks)"
    if ($item.Tag -eq 'codex') { $ck = "$ck-$codexIdxEp" }
    if ($item.Tag -eq 'claude') { $ck = "$($item.Bytes)" }   # jsonl append-only — key ตาม size
    $key = $item.RefPath + '|' + $ck
    if ($cache.ContainsKey($key)) {
      $label = $cache[$key]
    } else {
      $label = $null
      if ($item.Tag -eq 'claude' -and $byPath.ContainsKey($item.RefPath)) {
        $prev = $byPath[$item.RefPath]
        if ($prev.Size -lt $item.Bytes) {
          $nt = Get-TailTitle $item.RefPath $prev.Size
          $label = if ($nt) { $nt } else { $prev.Label }
        }
      }
      if (-not $label) {
        switch ($item.Tag) {
          'codex'  { $label = Get-CodexLabel $item.RefPath }
          'kimi'   { $label = Get-KimiLabel $item.Path }
          'gemini' { $label = Get-GeminiLabel $item.RefPath }
          default  { $label = Get-ClaudeLabel $item.RefPath }
        }
      }
      $label = $label -replace "[`t`r`n]", ' '
      [void]$newLines.AppendLine($item.RefPath + "`t" + $ck + "`t" + $label)
    }
    $rows += ($item.Path + "`t" + $item.Tag + "`t" + $dt + "`t" + $sz + "`t" + $label)
  }
  if ($newLines.Length -gt 0) {
    try {
      [System.IO.File]::AppendAllText($cacheFile, $newLines.ToString())
      $all = Read-FileLines $cacheFile
      if ($all.Count -gt 5000) { [System.IO.File]::WriteAllLines($cacheFile, $all[-2000..-1]) }
    } catch {}
  }
  return $rows
}

# ---------- vault: เข้ารหัส session ทุกค่ายด้วย VeraCrypt ----------
# คอนเทนเนอร์ AES mount เป็นไดรฟ์ แล้ว junction ~\.claude ~\.codex ~\.kimi-code ~\.gemini ชี้เข้าไป
# ล็อกแล้ว junction ชี้ไดรฟ์ที่ไม่มีอยู่ — เปิด CLI ตรงๆ ตอนล็อกจะเขียนอะไรไม่ได้ (กัน plaintext หลุด)
# .claude.json ทำ symlink ไฟล์ไม่ได้ถ้าไม่ใช่ admin — ตั้ง CLAUDE_CONFIG_DIR ให้ Claude ไปอ่านใน ~\.claude แทน
$vaultDir = Join-Path $env:LOCALAPPDATA 'ccrm'
$vaultFile = Join-Path $vaultDir 'vault.hc'
$vaultLinks = [ordered]@{ '.claude' = 'claude'; '.codex' = 'codex-data'; '.kimi-code' = 'kimi-data'; '.gemini' = 'gemini-data' }
$plainBackup = Join-Path $HOME '.ccrm-plain-backup'
$taskName = 'ccrm-sleeplock'

function Get-VcExe([string]$name) {
  foreach ($d in @("$env:ProgramFiles\VeraCrypt", "${env:ProgramFiles(x86)}\VeraCrypt")) {
    $p = Join-Path $d $name
    if (Test-Path -LiteralPath $p) { return $p }
  }
  return $null
}

function Test-VaultConfigured { return (Test-Path -LiteralPath $vaultFile) }

# ไดรฟ์ที่ mount วอลต์อยู่ — ดูจาก junction ~\.claude ว่าชี้ไดรฟ์ไหน และไดรฟ์นั้นมีอยู่จริง
function Get-VaultLetter {
  $j = Get-Item -LiteralPath (Join-Path $HOME '.claude') -Force -ErrorAction SilentlyContinue
  if ($j -and $j.LinkType -eq 'Junction') {
    $t = @($j.Target)[0]
    if ($t -match '^([A-Z]):\\' -and (Test-Path -LiteralPath ($matches[1] + ':\claude'))) { return $matches[1] }
  }
  return $null
}

function Test-VaultMounted { return [bool](Get-VaultLetter) }

function Get-FreeLetter {
  $used = @([System.IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0, 1) })
  foreach ($l in @('V', 'W', 'Y', 'Z', 'U', 'T', 'S', 'R', 'Q', 'P')) { if ($used -notcontains $l) { return $l } }
  return $null
}

function Read-Pw([string]$prompt) {
  $s = Read-Host -Prompt $prompt -AsSecureString
  $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

function Get-TreeSig([string]$p) {
  $files = @(Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue)
  $sum = ($files | Measure-Object -Property Length -Sum).Sum
  if (-not $sum) { $sum = 0 }
  return "$($files.Count) $sum"
}

# junction ห้ามลบด้วย Remove-Item -Recurse (PS 5.1 ลบไส้ในปลายทางด้วย) — ลบแค่ตัวลิงก์
function Remove-Junction([string]$p) { [System.IO.Directory]::Delete($p, $false) }

function Set-Junction([string]$p, [string]$target) {
  $it = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
  if ($it) {
    if ($it.LinkType -ne 'Junction') { return $false }
    if (@($it.Target)[0] -eq $target) { return $true }
    Remove-Junction $p
  }
  New-Item -ItemType Junction -Path $p -Target $target | Out-Null
  return $true
}

function Get-AiProcs {
  $names = 'claude', 'codex', 'kimi', 'gemini'
  $ps = @(Get-Process -Name $names -ErrorAction SilentlyContinue)
  $ps += @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match '[\\/](codex|gemini|kimi|claude-code)[\\/ ]' } |
    ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue })
  return @($ps | Where-Object { $_ -and $_.Id -ne $PID })
}

function Invoke-VcMount([string]$letter, [string]$pw) {
  $vc = Get-VcExe 'VeraCrypt.exe'
  & $vc /volume $vaultFile /letter $letter /password $pw /quit /silent /history n /nowaitdlg y | Out-Null
  # VeraCrypt คืนก่อน mount เสร็จบางที — รอไดรฟ์โผล่
  for ($i = 0; $i -lt 20; $i++) { if (Test-Path -LiteralPath ($letter + ':\')) { return $true }; Start-Sleep -Milliseconds 300 }
  return $false
}

function Invoke-VcDismount([string]$letter) {
  $vc = Get-VcExe 'VeraCrypt.exe'
  & $vc /dismount $letter /quit /silent | Out-Null
  for ($i = 0; $i -lt 10; $i++) { if (-not (Test-Path -LiteralPath ($letter + ':\'))) { return $true }; Start-Sleep -Milliseconds 300 }
  return $false
}

# ให้ทุก junction ชี้ไดรฟ์ปัจจุบัน — adopt = ย้ายโฟลเดอร์จริงที่ยังอยู่ข้างนอกเข้าวอลต์ (ตอน setup)
function Sync-VaultLinks([string]$letter, [bool]$adopt) {
  foreach ($k in $vaultLinks.Keys) {
    $src = Join-Path $HOME $k
    $dst = $letter + ':\' + $vaultLinks[$k]
    $it = Get-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue
    if ($it -and $it.LinkType -ne 'Junction') {
      if (-not $adopt) { continue }
      if (Test-Path -LiteralPath $dst) { Write-Host "  ! มีทั้ง ~\$k และในวอลต์ ไม่แตะ — รวมเองแล้วรัน ccrm lock-setup ใหม่"; continue }
      & robocopy $src $dst /E /COPY:DAT /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
      if ($LASTEXITCODE -ge 8) { Write-Host "  ✗ copy ~\$k ไม่สำเร็จ ไม่แตะของเดิม"; continue }
      $s1 = Get-TreeSig $src; $s2 = Get-TreeSig $dst
      if ($s1 -ne $s2) { Write-Host "  ✗ ~\$k copy ไม่ครบ ($s1 ≠ $s2) ไม่แตะของเดิม"; Remove-Item -LiteralPath $dst -Recurse -Force; continue }
      New-Item -ItemType Directory -Force -Path $plainBackup | Out-Null
      Move-Item -LiteralPath $src -Destination (Join-Path $plainBackup ($k + '.' + (Get-Date -Format 'yyyyMMdd-HHmmss')))
      Write-Host "  ✓ ย้าย ~\$k เข้าวอลต์แล้ว ($($s1.Split(' ')[0]) ไฟล์)"
    }
    if (-not (Test-Path -LiteralPath $dst)) {
      # .claude ต้องมีเสมอ (เป็นที่เก็บ .claude.json ด้วย) ค่ายอื่นสร้างเมื่อมีของ
      if ($k -ne '.claude') { continue }
      New-Item -ItemType Directory -Force -Path $dst | Out-Null
    }
    if (-not (Set-Junction $src $dst)) { Write-Host "  ! ~\$k ไม่ใช่ junction ข้ามไป" }
  }
  # .claude.json ข้างนอก (CLI รุ่นก่อนตั้ง CLAUDE_CONFIG_DIR เขียนไว้) — เก็บเข้าวอลต์
  $cj = Join-Path $HOME '.claude.json'
  $cjIn = $letter + ':\claude\.claude.json'
  if (Test-Path -LiteralPath $cj) {
    if ($adopt -or -not (Test-Path -LiteralPath $cjIn)) {
      Copy-Item -LiteralPath $cj -Destination $cjIn -Force
      New-Item -ItemType Directory -Force -Path $plainBackup | Out-Null
      Move-Item -LiteralPath $cj -Destination (Join-Path $plainBackup ('.claude.json.' + (Get-Date -Format 'yyyyMMdd-HHmmss')))
    }
  }
}

function Clear-ClaudeTemp {
  Remove-Item -LiteralPath (Join-Path $HOME '.claude.json.backup') -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Join-Path $env:TEMP 'claude') -Recurse -Force -ErrorAction SilentlyContinue
}

function Invoke-VaultUnlock {
  if (-not (Test-VaultConfigured)) { Write-Host 'ยังไม่ได้ตั้งค่าล็อก — พิมพ์ ccrm lock-setup'; return $false }
  if (-not (Get-VcExe 'VeraCrypt.exe')) { Write-Host 'ไม่พบ VeraCrypt — รัน ccrm lock-setup ใหม่เพื่อติดตั้ง'; return $false }
  $letter = Get-VaultLetter
  if ($letter) { Sync-VaultLinks $letter $false; Write-Host '🔓 ปลดล็อกอยู่แล้ว'; return $true }
  $letter = Get-FreeLetter
  if (-not $letter) { Write-Host 'ไม่มี drive letter ว่าง'; return $false }
  for ($i = 1; $i -le 3; $i++) {
    $pw = Read-Pw '🔒 รหัสผ่านวอลต์'
    if (-not $pw) { return $false }
    if (Invoke-VcMount $letter $pw) {
      Sync-VaultLinks $letter $false
      Write-Host '🔓 Unlocked'
      return $true
    }
    Write-Host "รหัสไม่ถูก ลองใหม่ ($i/3)"
  }
  Write-Host 'ปลดล็อกไม่สำเร็จ'
  return $false
}

# auto = มาจาก task ตอนเครื่อง sleep — ปิด AI CLI ให้เอง ไม่ใช้ /force (กันคอนเทนเนอร์พัง)
function Invoke-VaultLock([bool]$auto) {
  if (-not (Test-VaultConfigured)) { Write-Host 'ยังไม่ได้ตั้งค่าล็อก — พิมพ์ ccrm lock-setup'; return $false }
  Set-Location -LiteralPath $env:SystemRoot
  $letter = Get-VaultLetter
  if (-not $letter) { Clear-ClaudeTemp; Write-Host '🔒 ล็อกอยู่แล้ว'; return $true }
  Sync-VaultLinks $letter $false
  $ai = @(Get-AiProcs)
  if ($ai.Count -gt 0) {
    if (-not $auto) {
      Write-Host 'AI CLI ยังเปิดอยู่:'
      $ai | ForEach-Object { Write-Host ("  {0} {1}" -f $_.Id, $_.ProcessName) }
      $yn = Read-Host 'ปิดให้แล้วล็อกเลยไหม [y/N]'
      if ($yn -notmatch '^[Yy]') { Write-Host 'ยกเลิก — ยังไม่ล็อก'; return $false }
    }
    $ai | Stop-Process -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
  }
  if (-not (Invoke-VcDismount $letter)) {
    Start-Sleep -Seconds 1
    if (-not (Invoke-VcDismount $letter)) {
      Write-Host 'ยังล็อกไม่ได้ — มีโปรแกรมเปิดไฟล์ในวอลต์อยู่ (terminal/editor ที่อยู่ในโฟลเดอร์ ~\.claude ก็นับ) ปิดก่อนแล้วลองใหม่'
      return $false
    }
  }
  Clear-ClaudeTemp
  Write-Host '🔒 Locked'
  return $true
}

function Install-VaultWrappers {
  $bin = Join-Path $HOME 'bin'
  New-Item -ItemType Directory -Force -Path $bin | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $bin 'claude-lock.cmd'), "@echo off`r`ncall `"%~dp0ccrm.cmd`" lock %*`r`n")
  [System.IO.File]::WriteAllText((Join-Path $bin 'claude-unlock.cmd'), "@echo off`r`ncall `"%~dp0ccrm.cmd`" unlock %*`r`n")
}

# ล็อกอัตโนมัติตอน sleep — Task Scheduler ดัก event Kernel-Power 42 (sleep) / 506 (modern standby)
function Set-SleepTask([bool]$on) {
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
  if (-not $on) { Write-Host 'ปิดล็อกอัตโนมัติตอน sleep แล้ว'; return }
  $core = Join-Path $HOME 'bin\ccrm-core.ps1'
  $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  $q = "&lt;QueryList&gt;&lt;Query Id='0' Path='System'&gt;&lt;Select Path='System'&gt;*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and (EventID=42 or EventID=506)]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;"
  $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers><EventTrigger><Enabled>true</Enabled><Subscription>$q</Subscription></EventTrigger></Triggers>
  <Principals><Principal id="Author"><UserId>$user</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT2M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$core" lock -Auto</Arguments></Exec></Actions>
</Task>
"@
  try {
    Register-ScheduledTask -TaskName $taskName -Xml $xml -ErrorAction Stop | Out-Null
    Write-Host '  ✓ ล็อกอัตโนมัติตอนเครื่อง sleep — AI CLI ที่เปิดค้างจะถูกปิดให้ก่อนล็อก'
  } catch {
    Write-Host "  ! ตั้งล็อกอัตโนมัติไม่ได้: $($_.Exception.Message)"
  }
}

function Show-VaultStatus {
  if (-not (Test-VaultConfigured)) { Write-Host 'ยังไม่ได้ตั้งค่าล็อก — พิมพ์ ccrm lock-setup'; return }
  $l = Get-VaultLetter
  if ($l) { Write-Host "🔓 ปลดล็อกอยู่ (ไดรฟ์ ${l}:)" } else { Write-Host '🔒 ล็อกอยู่' }
  if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) { Write-Host 'ล็อกอัตโนมัติตอน sleep: เปิด' } else { Write-Host 'ล็อกอัตโนมัติตอน sleep: ปิด (ccrm lock-auto on)' }
  if (Test-Path -LiteralPath $plainBackup) { Write-Host '⚠ มีข้อมูลเดิมแบบไม่เข้ารหัสค้างที่ ~\.ccrm-plain-backup — ใช้งานได้ปกติแล้วสั่ง ccrm lock-cleanup' }
}

# ติดตั้ง VeraCrypt จาก MSI ของผู้ผลิตตรงๆ — winget มีแต่ x64 (ลงบน Windows ARM ไม่ได้ 1603)
function Install-VeraCrypt {
  if (Get-VcExe 'VeraCrypt.exe') { return $true }
  $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
  $a = if ($arch -eq 'ARM64') { 'arm64' } else { 'x64' }
  $vcVer = '1.26.29'
  # เวอร์ชันล่าสุดดูจาก manifest ของ winget (ถ้ามี)
  try {
    $w = & winget show -e --id IDRIX.VeraCrypt --disable-interactivity 2>$null | Out-String
    if ($w -match 'VeraCrypt_Setup_x64_([\d.]+)\.msi') { $vcVer = $matches[1] }
  } catch {}
  # [string] — Join-Path คืน PSObject ห่อ string ส่งเข้า COM แล้วได้ type mismatch
  $msi = [string](Join-Path $env:TEMP "VeraCrypt_Setup_${a}_$vcVer.msi")
  Write-Host "ดาวน์โหลด VeraCrypt $vcVer ($a) ..."
  try {
    Invoke-WebRequest -UseBasicParsing -Uri "https://launchpad.net/veracrypt/trunk/$vcVer/+download/VeraCrypt_Setup_${a}_$vcVer.msi" -OutFile $msi
  } catch { Write-Host "ดาวน์โหลดไม่สำเร็จ: $($_.Exception.Message)"; return $false }
  # ไฟล์ต้องเซ็นโดย IDRIX จริง — กันโดนสลับไฟล์ระหว่างทาง
  $sig = Get-AuthenticodeSignature -FilePath $msi
  if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'CN=IDRIX') {
    Write-Host "ลายเซ็น VeraCrypt ไม่ถูกต้อง ($($sig.Status)) — ยกเลิกการติดตั้ง"
    Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue
    return $false
  }
  if ($a -eq 'arm64') {
    # MSI arm64 ของ VeraCrypt ใส่ Template เป็น "arm64" ตัวเล็ก msiexec เลยปฏิเสธ (1633) — แก้เป็น "Arm64" หลังตรวจลายเซ็นแล้ว
    $inst = New-Object -ComObject WindowsInstaller.Installer
    $si = $inst.GetType().InvokeMember('SummaryInformation', 'GetProperty', $null, $inst, @($msi, 1))
    $si.GetType().InvokeMember('Property', 'SetProperty', $null, $si, @(7, 'Arm64;1033'))
    $si.GetType().InvokeMember('Persist', 'InvokeMethod', $null, $si, $null)
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($si)
  }
  # /passive = มีแถบความคืบหน้าแต่ไม่มี dialog ค้างรอกด (error ดูจาก exit code แทน)
  $msiArgs = "/i `"$msi`" /passive ACCEPTLICENSE=YES /norestart"
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  Write-Host 'ติดตั้ง VeraCrypt (มีหน้าต่างขอสิทธิ์ admin ให้กด Yes) ...'
  try {
    if ($isAdmin) { $p = Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru }
    else { $p = Start-Process msiexec.exe -ArgumentList $msiArgs -Verb RunAs -Wait -PassThru }
  } catch { Write-Host 'ไม่ได้กดอนุญาต — ยกเลิก'; return $false }
  Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue
  if (-not (Get-VcExe 'VeraCrypt.exe')) { Write-Host "ติดตั้ง VeraCrypt ไม่สำเร็จ (exit $($p.ExitCode))"; return $false }
  return $true
}

function Invoke-VaultSetup {
  if ($env:CLAUDECODE) { Write-Host 'รันจาก terminal ปกติ — ห้ามรันจากใน Claude Code (มันเปิดไฟล์ที่ต้องย้ายอยู่)'; return }
  $ai = @(Get-AiProcs)
  if ($ai.Count -gt 0) {
    Write-Host 'ปิด AI CLI ทุกตัวก่อน (claude/codex/kimi/gemini) แล้วรันใหม่:'
    $ai | ForEach-Object { Write-Host ("  {0} {1}" -f $_.Id, $_.ProcessName) }
    return
  }
  if (-not (Install-VeraCrypt)) { return }
  $letter = $null
  if (Test-VaultConfigured) {
    Write-Host "เจอวอลต์เดิมที่ $vaultFile — ใช้ต่อ (ไม่สร้างใหม่)"
    if (-not (Invoke-VaultUnlock)) { return }
    $letter = Get-VaultLetter
  } else {
    $need = 0L
    foreach ($k in $vaultLinks.Keys) {
      $p = Join-Path $HOME $k
      $it = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
      if ($it -and $it.LinkType -ne 'Junction') { $need += [long](Get-DirSize $p) }
    }
    $drive = New-Object System.IO.DriveInfo ($env:LOCALAPPDATA.Substring(0, 1))
    Write-Host 'จะเข้ารหัส session ของ Claude/Codex/Kimi/Gemini ไว้ในคอนเทนเนอร์ VeraCrypt (AES)'
    Write-Host ("  ข้อมูลที่ต้องย้าย: {0}B · ที่ว่างดิสก์: {1}B" -f (Format-Size $need), (Format-Size $drive.AvailableFreeSpace))
    if ($drive.AvailableFreeSpace -lt ($need + 1GB)) { Write-Host 'ที่ว่างไม่พอ (ต้องมากกว่าข้อมูล + 1 GB)'; return }
    Write-Host ''
    Write-Host '⚠ ลืมรหัสผ่าน = ข้อมูล session ทั้งหมดหายถาวร กู้ไม่ได้ (ไม่มีใครช่วยได้)'
    $yn = Read-Host 'เริ่มเลยไหม [y/N]'
    if ($yn -notmatch '^[Yy]') { Write-Host 'ยกเลิก'; return }
    while ($true) {
      $pw = Read-Pw 'ตั้งรหัสผ่าน (อย่างน้อย 8 ตัว ห้ามมี ")'
      if ($pw.Length -lt 8 -or $pw.Contains('"')) { Write-Host 'สั้นไปหรือมี " — ลองใหม่'; continue }
      $pw2 = Read-Pw 'พิมพ์ซ้ำอีกครั้ง'
      if ($pw -eq $pw2) { break }
      Write-Host 'ไม่ตรงกัน ลองใหม่'
    }
    New-Item -ItemType Directory -Force -Path $vaultDir | Out-Null
    # dynamic + quick = sparse file โตตามข้อมูลจริง ขนาดที่ตั้งเป็นแค่เพดาน (ไม่มี /quick จะจองเต็มก้อน)
    $cap = [Math]::Max(100, [Math]::Ceiling($need / 1GB) * 3)
    Write-Host "สร้างวอลต์ (เพดาน ${cap}G) ..."
    $fmt = Get-VcExe 'VeraCrypt Format.exe'
    & $fmt /create $vaultFile /size "${cap}G" /password $pw /encryption AES /hash sha512 /filesystem NTFS /dynamic /quick /silent /force | Out-Null
    if (-not (Test-Path -LiteralPath $vaultFile)) { Write-Host 'สร้างคอนเทนเนอร์ไม่สำเร็จ ข้อมูลเดิมไม่ถูกแตะ'; return }
    $letter = Get-FreeLetter
    if (-not (Invoke-VcMount $letter $pw)) { Write-Host 'mount ไม่สำเร็จ ข้อมูลเดิมไม่ถูกแตะ'; return }
  }
  Sync-VaultLinks $letter $true
  # Claude อ่าน .claude.json จาก CLAUDE_CONFIG_DIR — ชี้ไปใน ~\.claude (ซึ่งอยู่ในวอลต์)
  $cfg = Join-Path $HOME '.claude'
  [Environment]::SetEnvironmentVariable('CLAUDE_CONFIG_DIR', $cfg, 'User')
  $env:CLAUDE_CONFIG_DIR = $cfg
  # cache ชื่อ session ต้องอยู่ในวอลต์ด้วย
  $oldCache = Join-Path $env:LOCALAPPDATA 'ccrm-labels.tsv'
  if (Test-Path -LiteralPath $oldCache) {
    New-Item -ItemType Directory -Force -Path (Join-Path $cfg '.ccrm') | Out-Null
    Move-Item -LiteralPath $oldCache -Destination (Join-Path $cfg '.ccrm\labels.tsv') -Force
  }
  Install-VaultWrappers
  Set-SleepTask $true
  Write-Host ''
  Write-Host 'เสร็จแล้ว 🔓 ตอนนี้ปลดล็อกอยู่ (เปิด terminal ใหม่ก่อนใช้ claude ให้ค่า CLAUDE_CONFIG_DIR มีผล)'
  Write-Host '  ล็อก: claude-lock (หรือ ccrm lock, Ctrl-L ใน ccrm) · ปลดล็อก: claude-unlock หรือแค่เปิด ccrm'
  if (Test-Path -LiteralPath $plainBackup) { Write-Host '  ⚠ ข้อมูลเดิมแบบไม่เข้ารหัสยังอยู่ที่ ~\.ccrm-plain-backup — ลองใช้งานให้แน่ใจแล้วสั่ง ccrm lock-cleanup' }
}

function Invoke-VaultCleanup {
  if (-not (Test-Path -LiteralPath $plainBackup)) { Write-Host 'ไม่มีข้อมูลสำรองค้าง'; return }
  if (-not (Test-VaultMounted)) { Write-Host 'ปลดล็อกวอลต์ก่อน (ให้แน่ใจว่ารหัสใช้ได้) แล้วค่อยลบ'; return }
  Get-ChildItem -LiteralPath $plainBackup -Force | ForEach-Object { Write-Host ('  ' + $_.Name) }
  $yn = Read-Host 'ลบข้อมูลเดิมแบบไม่เข้ารหัสทั้งหมดนี้? (ในวอลต์ยังอยู่ครบ) [y/N]'
  if ($yn -notmatch '^[Yy]') { Write-Host 'ยกเลิก'; return }
  Remove-Item -LiteralPath $plainBackup -Recurse -Force
  Write-Host 'ลบแล้ว'
}

# คำสั่งย่อย — ccrm.cmd ส่ง %* มา: คำแรกตกที่ $Line คำที่สองตกที่ $Sel (positional)
switch ($Line) {
  'lock'         { if (Invoke-VaultLock $Auto.IsPresent) { exit 0 } else { exit 1 } }
  'unlock'       { if (Invoke-VaultUnlock) { exit 0 } else { exit 1 } }
  'lock-setup'   { Invoke-VaultSetup; exit 0 }
  'lock-status'  { Show-VaultStatus; exit 0 }
  'lock-cleanup' { Invoke-VaultCleanup; exit 0 }
  'lock-auto'    { Set-SleepTask ($Sel -ne 'off'); exit 0 }
}

if ($ListOnly) {
  Get-SessionRows -includeAll:$All | Write-Output
  exit 0
}

if ($PreviewLine) {
  $fields = $Line -split "`t"
  $sPath = $fields[0]
  $tag = $fields[1]
  if ($tag -eq 'kimi') {
    $wirePath = Join-Path $sPath 'agents\main\wire.jsonl'
    $lines = Read-FileLines $wirePath
    foreach ($ln in $lines) {
      if ([string]::IsNullOrWhiteSpace($ln)) { continue }
      $o = $null
      try { $o = $ln | ConvertFrom-Json -ErrorAction Stop } catch { continue }
      if ($o.type -eq 'turn.prompt' -and $o.origin.kind -eq 'user') {
        foreach ($p in $o.input) { if ($p.type -eq 'text') { $p.text } }
      }
    }
  } elseif ($tag -eq 'gemini') {
    try {
      $data = Read-FileRaw $sPath | ConvertFrom-Json
      foreach ($m in $data.messages) {
        if ($m.type -eq 'user') { foreach ($c in $m.content) { if ($c.text) { $c.text } } }
      }
    } catch {}
  } else {
    $lines = Read-FileLines $sPath 2000
    foreach ($ln in $lines) {
      if ([string]::IsNullOrWhiteSpace($ln)) { continue }
      $o = $null
      try { $o = $ln | ConvertFrom-Json -ErrorAction Stop } catch { continue }
      if ($tag -eq 'codex') {
        if ($o.type -eq 'response_item' -and $o.payload.role -eq 'user') {
          foreach ($c in $o.payload.content) {
            if ($c.type -eq 'input_text' -and $c.text -and -not $c.text.StartsWith('<')) { $c.text }
          }
        }
      } else {
        if ($o.type -eq 'user' -and -not $o.isMeta) {
          $c = $o.message.content
          if ($c -is [string]) { $c }
          elseif ($c) { foreach ($p in $c) { if ($p.type -eq 'text') { $p.text } } }
        }
      }
    }
  }
  exit 0
}

# ล็อกอยู่ — ปลดก่อนค่อยโชว์ session (Enter ว่าง = ออก)
$lockNote = ''
if (Test-VaultConfigured) {
  if (-not (Test-VaultMounted)) {
    Write-Host '🔒 session ถูกล็อกอยู่ (Enter ว่าง = ออก)'
    if (-not (Invoke-VaultUnlock)) { exit 1 }
  }
  $lockNote = '  🔓 Ctrl-L=ล็อก'
} elseif (-not (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'ccrm-lock-nag-off')) -and (Get-Command fzf -ErrorAction SilentlyContinue)) {
  $choice = @('ตั้งค่าเลย (ccrm lock-setup)', 'ไว้ทีหลัง', 'ไม่ต้องถามอีก') | fzf --header '🔐 ใหม่: เข้ารหัส session ทุกค่ายด้วยรหัสผ่าน + ล็อกอัตโนมัติตอน sleep' --no-multi --reverse --no-info --height ~6 --prompt 'เลือก> '
  if ($choice -like 'ตั้งค่า*') { Invoke-VaultSetup; exit 0 }
  if ($choice -like 'ไม่ต้อง*') { [System.IO.File]::WriteAllText((Join-Path $env:LOCALAPPDATA 'ccrm-lock-nag-off'), '1') }
}

$rows = @(Get-SessionRows -includeAll:$All)
if ($rows.Count -eq 0) {
  Write-Host 'ไม่พบ session'
  exit 0
}

$fzf = Get-Command fzf -ErrorAction SilentlyContinue
if (-not $fzf) {
  Write-Host 'ไม่พบ fzf ติดตั้งก่อน: winget install -e --id junegunn.fzf'
  exit 1
}

$ver = 22
$verCache = Join-Path $env:LOCALAPPDATA 'ccrm-latest'
# เช็คเวอร์ชันใหม่แบบ background ไม่บล็อกการใช้งาน — ผลไปโผล่ครั้งถัดไป
Start-Process -WindowStyle Hidden powershell -ArgumentList '-NoProfile', '-Command', "try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 ('https://github.com/cznpsk/ccrm/releases/latest/download/VERSION?ts=' + [DateTimeOffset]::Now.ToUnixTimeSeconds())).Content.Trim() | Set-Content -LiteralPath '$verCache' } catch {}" -ErrorAction SilentlyContinue
$updateNote = ''
if (Test-Path $verCache) {
  $latest = Read-FileRaw $verCache
  if ($latest) { $latest = $latest.Trim() }
  $ln = 0
  if ([int]::TryParse($latest, [ref]$ln) -and $ln -gt $ver) { $updateNote = "  |  v$latest มาแล้ว" }
}

# มีเวอร์ชันใหม่ — เมนูเลือกก่อนเปิด (ลูกศรขึ้นลง + Enter, Esc = ข้าม)
if ($updateNote) {
  $choice = @("อัพเดทเป็น v$latest เลย", "ข้ามไปก่อน (ใช้ v$ver ต่อ)") | fzf --header "⬆ มีเวอร์ชันใหม่ของ ccrm" --no-multi --reverse --no-info --height ~6 --prompt 'เลือก> '
  if ($choice -like 'อัพเดท*') {
    $u = 'https://github.com/cznpsk/ccrm/releases/latest/download/install.ps1?ts=' + [DateTimeOffset]::Now.ToUnixTimeSeconds()
    Invoke-Expression (Invoke-WebRequest -UseBasicParsing -Uri $u).Content
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $HOME 'bin\ccrm-core.ps1')
    exit 0
  }
}

$scriptPath = $PSCommandPath
$psBase = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '"'
$header = "รวม $($rows.Count) sessions  |  Enter=resume  Tab=เลือกลบ (กด Tab อีกครั้งยืนยัน)  Ctrl-A=รีเฟรช  Esc=ยกเลิก$lockNote$updateNote"
$previewCmd = $psBase + ' -PreviewLine -Line "{r}"'
$allFlag = if ($All) { ' -All' } else { '' }
$tabBind = 'tab:transform:' + $psBase + ' -TabTransform -Sel {+1} -Cur {1}' + $allFlag

$refreshBind = 'ctrl-a:reload(' + $psBase + ' -ListOnly)'
# fzf บน Windows ไม่มี become — execute แล้ว abort แทน
$lockBind = if ($lockNote) { @('--bind', ('ctrl-l:execute(' + $psBase + ' lock)+abort')) } else { @() }
$picked = $rows | fzf --multi --delimiter "`t" --with-nth 2.. --header $header --preview $previewCmd --preview-window right:50%:wrap --bind $tabBind --bind $refreshBind @lockBind

if (-not $picked) {
  # Ctrl-L ล็อกแล้ว fzf ล้างจอทิ้ง — บอกผลอีกที
  if ($lockNote -and -not (Test-VaultMounted)) { Write-Host '🔒 Locked' }
  exit 0
}

$fields = $picked -split "`t"
$spath = $fields[0]
$tag = $fields[1].Trim()

switch ($tag) {
  'codex' {
    $fname = [System.IO.Path]::GetFileNameWithoutExtension($spath)
    if ($fname -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
      $id = $matches[1]
    } else {
      Write-Host 'หา session id ไม่เจอ'
      exit 1
    }
    & codex resume $id --yolo
  }
  'kimi' {
    $id = Split-Path -Leaf $spath
    try {
      $state = Read-FileRaw (Join-Path $spath 'state.json') | ConvertFrom-Json
      $wd = if ($state.cwd) { $state.cwd } elseif ($state.workDir) { $state.workDir } else { $null }
      if ($wd) { Set-Location -LiteralPath $wd }
    } catch {}
    & kimi -r $id --yolo
  }
  'gemini' {
    $projDir = Split-Path -Parent (Split-Path -Parent $spath)
    $rootFile = Join-Path $projDir '.project_root'
    if (Test-Path $rootFile) {
      $root = Read-FileRaw $rootFile
      if ($root) { $root = $root.Trim() }
      if ($root) { Set-Location -LiteralPath $root }
    }
    & gemini --session-file $spath -y
  }
  default {
    $id = [System.IO.Path]::GetFileNameWithoutExtension($spath)
    & claude --resume $id --dangerously-skip-permissions
  }
}
