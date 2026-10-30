# Cut a 2x2 sheet from gen-raw\ into four images (top-left, top-right, bottom-left, bottom-right).
#   .\tools\split-grid.ps1 -Sheet sheet-m0 -Names x-m0,x-m1,x-m2,x-m3
param([Parameter(Mandatory)][string]$Sheet, [Parameter(Mandatory)][string[]]$Names)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$raw = Join-Path (Split-Path $PSScriptRoot -Parent) 'gen-raw'
$src = [System.Drawing.Image]::FromFile((Join-Path $raw "$Sheet.jpg"))
$w = [int]($src.Width / 2); $h = [int]($src.Height / 2)
for ($k = 0; $k -lt 4; $k++) {
  $b = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($b)
  $g.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $w, $h), (New-Object System.Drawing.Rectangle (($k % 2) * $w), ([math]::Floor($k / 2) * $h), $w, $h), [System.Drawing.GraphicsUnit]::Pixel)
  $g.Dispose()
  $b.Save((Join-Path $raw "$($Names[$k]).jpg"), [System.Drawing.Imaging.ImageFormat]::Jpeg)
  $b.Dispose()
  Write-Output "cut   $($Names[$k])"
}
$src.Dispose()
