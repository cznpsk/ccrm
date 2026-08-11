# ติดตั้ง ccrm สำหรับ Windows PowerShell
$ErrorActionPreference = 'Stop'

$raw = 'https://raw.githubusercontent.com/cznpsk/ccrm/main'
$dir = if ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $null }
$binDir = Join-Path $HOME 'bin'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
  Write-Host 'ติดตั้ง fzf ...'
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install -e --id junegunn.fzf
  } else {
    Write-Host 'ไม่มี winget ในเครื่องนี้ ติดตั้ง fzf เองจาก https://github.com/junegunn/fzf/releases แล้วรัน install.ps1 ใหม่'
    exit 1
  }
}

Remove-Item (Join-Path $binDir 'ccrm.ps1') -ErrorAction SilentlyContinue
foreach ($f in 'ccrm-core.ps1', 'ccrm.cmd') {
  $dest = Join-Path $binDir $f
  if ($dir -and (Test-Path (Join-Path $dir $f))) {
    Copy-Item (Join-Path $dir $f) $dest -Force
  } else {
    $ts = [DateTimeOffset]::Now.ToUnixTimeSeconds()
    Invoke-WebRequest -UseBasicParsing -Uri "$raw/$f`?ts=$ts" -OutFile $dest
  }
}
Write-Host "ติดตั้ง ccrm ไปที่ $binDir แล้ว"

try {
  $policy = Get-ExecutionPolicy -Scope CurrentUser
  if ($policy -eq 'Restricted' -or $policy -eq 'AllSigned' -or $policy -eq 'Undefined') {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
    Write-Host 'ตั้ง ExecutionPolicy เป็น RemoteSigned (CurrentUser) แล้ว'
  }
} catch {
  Write-Host 'ตั้ง ExecutionPolicy ไม่ได้ (เครื่องนี้อาจล็อกด้วย Group Policy) — ไม่เป็นไร ccrm.cmd ใช้ -ExecutionPolicy Bypass เฉพาะตัวอยู่แล้ว'
}

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$binDir*") {
  [Environment]::SetEnvironmentVariable('Path', "$userPath;$binDir", 'User')
  Write-Host "เพิ่ม $binDir เข้า PATH แล้ว (ต้องเปิด terminal ใหม่ถึงจะเห็นผล)"
}

foreach ($c in 'claude', 'codex') {
  if (-not (Get-Command $c -ErrorAction SilentlyContinue)) {
    Write-Host "หมายเหตุ: ยังไม่มี $c CLI ในเครื่องนี้ — ต้องติดตั้งแยกเองก่อนใช้ ccrm resume $c session"
  }
}

$verLine = Select-String -LiteralPath (Join-Path $binDir 'ccrm-core.ps1') -Pattern '^\$ver = (\d+)' | Select-Object -First 1
$installedVer = if ($verLine) { $verLine.Matches[0].Groups[1].Value } else { '?' }
Write-Host ''
Write-Host "ติดตั้งเสร็จ v$installedVer — เปิด terminal ใหม่แล้วพิมพ์ ccrm"
