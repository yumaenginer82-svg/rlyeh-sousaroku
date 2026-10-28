# Split a 2x2 sheet from gen-raw\ into four images (top-left, top-right, bottom-left, bottom-right).
# Each quarter is cropped a little inside its edges so any grid lines Gemini draws are left out.
#   .\tools\split-sheet.ps1 -Sheet sheet-01 -Names f-oldkey,f-anchor,f-candle,f-oillamp
param([Parameter(Mandatory)][string]$Sheet, [Parameter(Mandatory)][string[]]$Names, [double]$Inset = 0.035)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if ($Names.Count -ne 4) { throw 'Pass exactly 4 names' }
$raw = Join-Path (Split-Path $PSScriptRoot -Parent) 'gen-raw'
$src = Get-ChildItem $raw -File | Where-Object { $_.BaseName -eq $Sheet } | Select-Object -First 1
if (-not $src) { throw "no gen-raw\$Sheet.*" }
$img = [System.Drawing.Image]::FromFile($src.FullName)
try {
  $hw = [int]($img.Width / 2); $hh = [int]($img.Height / 2)
  $pad = [int]([Math]::Min($hw, $hh) * $Inset)
  $side = [Math]::Min($hw, $hh) - 2 * $pad
  for ($k = 0; $k -lt 4; $k++) {
    $x = ($k % 2) * $hw + $pad; $y = [Math]::Floor($k / 2) * $hh + $pad
    $bmp = New-Object System.Drawing.Bitmap $side, $side
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::White)
    $g.DrawImage($img, (New-Object System.Drawing.Rectangle 0, 0, $side, $side), (New-Object System.Drawing.Rectangle $x, $y, $side, $side), [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    $out = Join-Path $raw ($Names[$k] + '.png')
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    "ok    {0} <- {1} quarter {2}" -f $Names[$k], $Sheet, $k
  }
} finally { $img.Dispose() }
