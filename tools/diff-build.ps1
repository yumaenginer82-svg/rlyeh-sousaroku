# Build one scene's spot-the-difference pieces from a hand-checked list, and the images to check them by.
#   .\tools\diff-build.ps1 -Scene 3
# The list is gen-raw\df<scene>-final.json: one entry per difference, in this form
#   { "from": "df3-cut4", "n": [1],            the region(s) cut by diff-cut.ps1 (several = one change that came out in parts)
#     "keep": [ ["e", cx, cy, rx, ry], ["r", x0, y0, x1, y1] ],   optional: keep only these shapes (picture px), to leave out
#                                                                  a nearby change that was not asked for
#     "k": "color", "lv": 1, "t": "..." }       kind, difficulty and what changed (copied into DIFF_SETS)
# Out: assets\df<scene>\p<i>.png (i = position in the list), gen-raw\df<scene>-final.js (the DIFF_SETS lines),
#      gen-raw\df<scene>-whole.jpg (the change across the whole picture with every piece in: nothing may show outside the boxes)
#      gen-raw\df<scene>-review.jpg (each piece: before | after | where it changed).
param([Parameter(Mandatory)][int]$Scene)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$raw = Join-Path $root 'gen-raw'
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class DiffBuild {
  public static byte[] Px(Bitmap b) { var d = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
    var a = new byte[d.Stride * b.Height]; Marshal.Copy(d.Scan0, a, 0, a.Length); b.UnlockBits(d); return a; }
  public static void Put(Bitmap b, byte[] a) { var d = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
    Marshal.Copy(a, 0, d.Scan0, a.Length); b.UnlockBits(d); }
  // keep[]: shapes as {kind(0 = ellipse, 1 = rect), a, b, c, d} in piece px; alpha fades over `f` px outside them
  public static void Clip(byte[] p, int w, int h, double[][] keep, double f) {
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
      double best = 1e9;
      foreach (var s in keep) {
        double d;
        if (s[0] == 0) { double nx = (x - s[1]) / s[3], ny = (y - s[2]) / s[4], r = Math.Sqrt(nx * nx + ny * ny); d = (r - 1) * Math.Min(s[3], s[4]); }
        else { double dx = Math.Max(Math.Max(s[1] - x, x - s[3]), 0), dy = Math.Max(Math.Max(s[2] - y, y - s[4]), 0); d = Math.Sqrt(dx * dx + dy * dy); }
        if (d < best) best = d;
      }
      double k = best <= 0 ? 1 : best >= f ? 0 : 1 - best / f;
      int i = (y * w + x) * 4 + 3; p[i] = (byte)Math.Round(p[i] * k);
    }
  }
  // the box around every pixel with alpha > 8
  public static int[] Box(byte[] p, int w, int h) {
    int x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) if (p[(y * w + x) * 4 + 3] > 8) { if (x < x0) x0 = x; if (y < y0) y0 = y; if (x > x1) x1 = x; if (y > y1) y1 = y; }
    return new int[] { x0, y0, x1, y1 };
  }
  // change between two same-size pictures, as a grey picture (x4 so faint change shows)
  public static void Heat(byte[] a, byte[] b, byte[] o) {
    for (int i = 0; i < a.Length; i += 4) {
      int d = Math.Max(Math.Abs(a[i] - b[i]), Math.Max(Math.Abs(a[i + 1] - b[i + 1]), Math.Abs(a[i + 2] - b[i + 2])));
      byte v = (byte)Math.Min(255, d * 4); o[i] = v; o[i + 1] = v; o[i + 2] = v; o[i + 3] = 255;
    }
  }
}
'@
$spec = Get-Content (Join-Path $raw "df$Scene-final.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$baseImg = [System.Drawing.Image]::FromFile((Join-Path $root "assets\bg-df$Scene.jpg"))
$W = $baseImg.Width; $H = $baseImg.Height
$A = New-Object System.Drawing.Bitmap $W, $H, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($A); $g.DrawImage($baseImg, 0, 0, $W, $H); $g.Dispose(); $baseImg.Dispose()
$Bimg = $A.Clone(); $gB = [System.Drawing.Graphics]::FromImage($Bimg)
$outDir = Join-Path $root "assets\df$Scene"
if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
New-Item -ItemType Directory -Force $outDir | Out-Null
$js = @(); $boxes = @(); $i = 0
foreach ($e in $spec) {
  $src = Join-Path $raw $e.from
  $meta = Get-Content (Join-Path $src 'pieces.json') -Raw | ConvertFrom-Json
  $parts = @($e.n | ForEach-Object { $n = $_; $meta | Where-Object { $_.n -eq $n } })
  $x0 = ($parts | ForEach-Object x | Measure-Object -Minimum).Minimum; $y0 = ($parts | ForEach-Object y | Measure-Object -Minimum).Minimum
  $x1 = ($parts | ForEach-Object { $_.x + $_.w } | Measure-Object -Maximum).Maximum; $y1 = ($parts | ForEach-Object { $_.y + $_.h } | Measure-Object -Maximum).Maximum
  $pc = New-Object System.Drawing.Bitmap ($x1 - $x0), ($y1 - $y0), ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $gp = [System.Drawing.Graphics]::FromImage($pc)
  foreach ($p in $parts) { $im = [System.Drawing.Image]::FromFile((Join-Path $src "p$($p.n).png")); $gp.DrawImage($im, $p.x - $x0, $p.y - $y0, $p.w, $p.h); $im.Dispose() }
  $gp.Dispose()
  $px = [DiffBuild]::Px($pc)
  if ($e.keep) {
    $shapes = [double[][]]@($e.keep | ForEach-Object { if ($_[0] -eq 'e') { ,[double[]]@(0, ($_[1] - $x0), ($_[2] - $y0), $_[3], $_[4]) } else { ,[double[]]@(1, ($_[1] - $x0), ($_[2] - $y0), ($_[3] - $x0), ($_[4] - $y0)) } })
    [DiffBuild]::Clip($px, $pc.Width, $pc.Height, $shapes, 6)
  }
  $bx = [DiffBuild]::Box($px, $pc.Width, $pc.Height)
  [DiffBuild]::Put($pc, $px)
  $cw = $bx[2] - $bx[0] + 1; $ch = $bx[3] - $bx[1] + 1
  $piece = $pc.Clone((New-Object System.Drawing.Rectangle $bx[0], $bx[1], $cw, $ch), $pc.PixelFormat); $pc.Dispose()
  $px0 = $x0 + $bx[0]; $py0 = $y0 + $bx[1]
  $piece.Save((Join-Path $outDir "p$i.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $gB.DrawImage($piece, $px0, $py0, $cw, $ch); $piece.Dispose()
  $boxes += , @($px0, $py0, $cw, $ch)
  $js += "    { f: $i, x: $px0, y: $py0, w: $cw, h: $ch, k: '$($e.k)', lv: $($e.lv), t: '$($e.t)' },"
  $i++
}
$gB.Dispose()
$js | Set-Content -Encoding utf8 (Join-Path $raw "df$Scene-final.js")

# whole picture: where B differs from A, with each piece's box in green
$pa = [DiffBuild]::Px($A); $pb = [DiffBuild]::Px($Bimg); $ph = New-Object byte[] $pa.Length
[DiffBuild]::Heat($pa, $pb, $ph)
$heat = New-Object System.Drawing.Bitmap $W, $H, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb); [DiffBuild]::Put($heat, $ph)
$gh = [System.Drawing.Graphics]::FromImage($heat); $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Lime), 2
$font = New-Object System.Drawing.Font 'Arial', 16, ([System.Drawing.FontStyle]::Bold)
for ($k = 0; $k -lt $boxes.Count; $k++) { $b = $boxes[$k]; $gh.DrawRectangle($pen, $b[0] - 3, $b[1] - 3, $b[2] + 6, $b[3] + 6); $gh.DrawString("$k", $font, [System.Drawing.Brushes]::Lime, $b[0], [math]::Max(0, $b[1] - 24)) }
$gh.Dispose()
$heat.Save((Join-Path $raw "df$Scene-whole.jpg"), [System.Drawing.Imaging.ImageFormat]::Jpeg)
# per piece: before | after | change, each crop with a margin
$cell = 260; $sheet = New-Object System.Drawing.Bitmap ($cell * 3 + 20), ($boxes.Count * ($cell + 24))
$gs = [System.Drawing.Graphics]::FromImage($sheet); $gs.Clear([System.Drawing.Color]::Black); $gs.InterpolationMode = 'HighQualityBicubic'
for ($k = 0; $k -lt $boxes.Count; $k++) {
  $b = $boxes[$k]; $m = 24
  $cx = [math]::Max(0, $b[0] - $m); $cy = [math]::Max(0, $b[1] - $m); $cw = [math]::Min($W - $cx, $b[2] + 2 * $m); $chh = [math]::Min($H - $cy, $b[3] + 2 * $m)
  $sc = $cell / [math]::Max($cw, $chh); $dw = [int]($cw * $sc); $dh = [int]($chh * $sc); $oy = $k * ($cell + 24) + 22
  $srcR = New-Object System.Drawing.Rectangle $cx, $cy, $cw, $chh
  # this piece alone on the original (as the game shows it when only this one is drawn), and its change
  $before = $A.Clone($srcR, $A.PixelFormat); $after = $A.Clone($srcR, $A.PixelFormat)
  $ga = [System.Drawing.Graphics]::FromImage($after); $pim = [System.Drawing.Image]::FromFile((Join-Path $outDir "p$k.png"))
  $ga.DrawImage($pim, $b[0] - $cx, $b[1] - $cy, $b[2], $b[3]); $pim.Dispose(); $ga.Dispose()
  $q1 = [DiffBuild]::Px($before); $q2 = [DiffBuild]::Px($after); $q3 = New-Object byte[] $q1.Length; [DiffBuild]::Heat($q1, $q2, $q3)
  $hk = New-Object System.Drawing.Bitmap $cw, $chh, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb); [DiffBuild]::Put($hk, $q3)
  $gs.DrawImage($before, 0, $oy, $dw, $dh); $gs.DrawImage($after, $cell + 10, $oy, $dw, $dh); $gs.DrawImage($hk, 2 * $cell + 20, $oy, $dw, $dh)
  $before.Dispose(); $after.Dispose(); $hk.Dispose()
  $gs.DrawString("$k  $($spec[$k].t)", (New-Object System.Drawing.Font 'Meiryo', 11), [System.Drawing.Brushes]::Yellow, 0, $oy - 21)
}
$gs.Dispose(); $sheet.Save((Join-Path $raw "df$Scene-review.jpg"), [System.Drawing.Imaging.ImageFormat]::Jpeg); $sheet.Dispose()
$heat.Dispose(); $A.Dispose(); $Bimg.Dispose()
Write-Output "df$Scene : $($boxes.Count) pieces -> assets\df$Scene, gen-raw\df$Scene-final.js, -whole.jpg, -review.jpg"
