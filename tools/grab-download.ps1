# Take the image the browser just downloaded and copy it into gen-raw\<Name>.<ext>.
# The built-in browser leaves finished downloads as *.tmp, so the newest file is checked by its bytes.
#   .\tools\grab-download.ps1 -Name m-1-5 [-SinceSeconds 120]
param([Parameter(Mandatory)][string]$Name, [int]$SinceSeconds = 120, [int]$WaitSeconds = 40)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$raw = Join-Path $root 'gen-raw'
New-Item -ItemType Directory -Force $raw | Out-Null
$dl = Join-Path $env:USERPROFILE 'Downloads'
$since = (Get-Date).AddSeconds(-$SinceSeconds)
$deadline = (Get-Date).AddSeconds($WaitSeconds)
$pick = $null
while (-not $pick -and (Get-Date) -lt $deadline) {
  # Only the browser's own downloads (*.tmp, or Gemini's file names): never pick up, or delete, a file the user saved.
  $cand = Get-ChildItem $dl -File | Where-Object { $_.LastWriteTime -gt $since -and $_.Length -gt 20KB -and ($_.Extension -eq '.tmp' -or $_.Name -like 'Gemini*') } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($cand) {
    $len = $cand.Length; Start-Sleep -Milliseconds 1500
    $cand.Refresh()
    if ($cand.Length -eq $len) { $pick = $cand }
  } else { Start-Sleep -Seconds 1 }
}
if (-not $pick) { Write-Output "FAIL  $Name : no new download in $dl"; exit 1 }
$b = [System.IO.File]::ReadAllBytes($pick.FullName)
$ext = if ($b[0] -eq 0xFF -and $b[1] -eq 0xD8) { 'jpg' } elseif ($b[0] -eq 0x89 -and $b[1] -eq 0x50) { 'png' } elseif ($b[8] -eq 0x57 -and $b[9] -eq 0x45) { 'webp' } else { 'bin' }
$dst = Join-Path $raw "$Name.$ext"
[System.IO.File]::WriteAllBytes($dst, $b)
$i = [System.Drawing.Image]::FromFile($dst); $w = $i.Width; $h = $i.Height; $i.Dispose()
Remove-Item $pick.FullName -ErrorAction SilentlyContinue   # our own download; keep the user's Downloads tidy
Write-Output ("ok    {0} -> gen-raw\{0}.{1} ({2}x{3}, {4:N0} KB)" -f $Name, $ext, $w, $h, ($b.Length / 1KB))
