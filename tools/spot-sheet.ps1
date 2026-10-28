# Contact sheet of every recorded spot in a scene: one zoomed tile per item copy, with its hit circle,
# so each spot can be checked against what is actually drawn there.
#   .\tools\spot-sheet.ps1 -Scene tools\scenes\hs-1.json -Src gen-raw\hs-1.jpg -Out $env:TEMP\s.png [-Cols 8]
param([Parameter(Mandatory)][string]$Scene, [Parameter(Mandatory)][string]$Src, [Parameter(Mandatory)][string]$Out,
  [int]$Cols = 8, [int]$Tile = 150)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$sc = Get-Content $Scene -Raw -Encoding UTF8 | ConvertFrom-Json
$img = [System.Drawing.Image]::FromFile((Resolve-Path $Src))
$spots = foreach ($it in $sc.items) { $n = 0; foreach ($b in $it.at) { $n++; [pscustomobject]@{ id = $it.id; ja = $it.ja; n = $n; x = $b[0]; y = $b[1]; r = $b[2] } } }
$rows = [Math]::Ceiling($spots.Count / $Cols); $lab = 18
$bmp = New-Object System.Drawing.Bitmap ($Cols * $Tile), ($rows * ($Tile + $lab))
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::White); $g.InterpolationMode = 'HighQualityBicubic'
$red = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(220, 230, 20, 20)), 2
$font = New-Object System.Drawing.Font 'Meiryo', 8, ([System.Drawing.FontStyle]::Bold)
$i = 0
foreach ($s in $spots) {
  $cx = ($i % $Cols) * $Tile; $cy = [Math]::Floor($i / $Cols) * ($Tile + $lab)
  $half = [Math]::Max(45, [int]($s.r * 2.2))   # show the object plus some surroundings
  $box = New-Object System.Drawing.Rectangle ($s.x - $half), ($s.y - $half), (2 * $half), (2 * $half)
  $g.DrawImage($img, (New-Object System.Drawing.Rectangle $cx, ($cy + $lab), $Tile, $Tile), $box, [System.Drawing.GraphicsUnit]::Pixel)
  $k = $Tile / (2.0 * $half); $rr = $s.r * $k
  $g.DrawEllipse($red, $cx + $Tile / 2 - $rr, $cy + $lab + $Tile / 2 - $rr, 2 * $rr, 2 * $rr)
  $g.DrawString("$i $($s.ja) #$($s.n)", $font, [System.Drawing.Brushes]::Black, $cx + 2, $cy + 1)
  $i++
}
$g.Dispose(); $img.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
"saved $Out ($($spots.Count) spots)"
