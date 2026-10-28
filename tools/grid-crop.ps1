# Crop part of an image, enlarge it, and draw a labelled coordinate grid, for locating hidden objects.
# Optionally draw boxes from a scene file to check them: -Boxes tools\scenes\hs-0.json
#   .\tools\grid-crop.ps1 -Src gen-raw\hs-0.jpg -X 0 -Y 0 -W 640 -H 430 -Out $env:TEMP\c.png [-Step 50] [-Scale 1.6]
param([Parameter(Mandatory)][string]$Src, [int]$X = 0, [int]$Y = 0, [int]$W = 0, [int]$H = 0,
  [Parameter(Mandatory)][string]$Out, [int]$Step = 50, [double]$Scale = 1.6, [string]$Boxes)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile((Resolve-Path $Src))
if ($W -le 0) { $W = $img.Width - $X }; if ($H -le 0) { $H = $img.Height - $Y }
$ow = [int]($W * $Scale); $oh = [int]($H * $Scale)
$bmp = New-Object System.Drawing.Bitmap $ow, $oh
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = 'HighQualityBicubic'
$g.DrawImage($img, (New-Object System.Drawing.Rectangle 0, 0, $ow, $oh), (New-Object System.Drawing.Rectangle $X, $Y, $W, $H), [System.Drawing.GraphicsUnit]::Pixel)
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(150, 0, 160, 255)), 1
$font = New-Object System.Drawing.Font 'Arial', 9, ([System.Drawing.FontStyle]::Bold)
$brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 0, 90, 200))
$bg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(200, 255, 255, 255))
for ($gx = [Math]::Ceiling($X / $Step) * $Step; $gx -lt $X + $W; $gx += $Step) {
  $px = ($gx - $X) * $Scale; $g.DrawLine($pen, $px, 0, $px, $oh)
  $g.FillRectangle($bg, $px + 1, 1, 28, 13); $g.DrawString("$gx", $font, $brush, $px + 1, 1)
}
for ($gy = [Math]::Ceiling($Y / $Step) * $Step; $gy -lt $Y + $H; $gy += $Step) {
  $py = ($gy - $Y) * $Scale; $g.DrawLine($pen, 0, $py, $ow, $py)
  $g.FillRectangle($bg, 1, $py + 1, 28, 13); $g.DrawString("$gy", $font, $brush, 1, $py + 1)
}
if ($Boxes) {
  $scene = Get-Content $Boxes -Raw -Encoding UTF8 | ConvertFrom-Json
  $red = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(230, 230, 30, 30)), 2
  $rb = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 200, 0, 0))
  foreach ($it in $scene.items) { foreach ($b in $it.at) {
    $cx = ($b[0] - $X) * $Scale; $cy = ($b[1] - $Y) * $Scale; $r = $b[2] * $Scale
    $g.DrawEllipse($red, $cx - $r, $cy - $r, 2 * $r, 2 * $r)
    $g.FillRectangle($bg, $cx - $r, $cy - $r - 13, 60, 13); $g.DrawString($it.id, $font, $rb, $cx - $r, $cy - $r - 13)
  } }
}
$g.Dispose(); $img.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
"saved $Out (${ow}x${oh})"
