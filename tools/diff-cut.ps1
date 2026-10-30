# Cut an AI-edited copy of a picture into separate difference pieces.
#   .\tools\diff-cut.ps1 -Base assets\bg-df0.jpg -Edit gen-raw\df0-edit.png -Out gen-raw\df0-cut [-Thresh 40] [-MinArea 250]
# The edited copy is scaled to the base, nudged into line (small shifts), and compared pixel by pixel.
# Each separate changed region becomes a piece: <Out>\p<n>.png (the edited pixels, soft-edged) plus pieces.json,
# and <Out>-map.jpg shows the numbered regions on the edited picture, to pick the intended changes and drop stray ones.
param(
  [Parameter(Mandatory)][string]$Base,
  [Parameter(Mandatory)][string]$Edit,
  [Parameter(Mandatory)][string]$Out,
  [int]$Thresh = 40,
  [int]$MinArea = 250,
  [int]$Grow = 5,
  [int]$Low = 0      # with e.g. 16: let each clear change take in the fainter change it touches (whole objects)
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
function Abs([string]$p) { if ([System.IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $root $p } }

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Collections.Generic; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class DiffCut {
  public static byte[] Px(Bitmap b) {
    var d = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
    var a = new byte[d.Stride * b.Height]; Marshal.Copy(d.Scan0, a, 0, a.Length); b.UnlockBits(d); return a;
  }
  public static Bitmap FromPx(byte[] a, int w, int h) {
    var b = new Bitmap(w, h, PixelFormat.Format32bppArgb);
    var d = b.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
    Marshal.Copy(a, 0, d.Scan0, a.Length); b.UnlockBits(d); return b;
  }
  static float[] Gray(byte[] p, int w, int h) { var g = new float[w * h]; for (int i = 0; i < w * h; i++) g[i] = .3f * p[i * 4 + 2] + .59f * p[i * 4 + 1] + .11f * p[i * 4]; return g; }
  // best shift of e against b, searched over +-r px on a sparse grid
  public static int[] Align(byte[] b, byte[] e, int w, int h, int r) {
    var gb = Gray(b, w, h); var ge = Gray(e, w, h); double best = double.MaxValue; int bx = 0, by = 0;
    for (int dy = -r; dy <= r; dy++) for (int dx = -r; dx <= r; dx++) {
      double s = 0; int n = 0;
      for (int y = r + 4; y < h - r - 4; y += 6) for (int x = r + 4; x < w - r - 4; x += 6) { s += Math.Abs(gb[y * w + x] - ge[(y + dy) * w + x + dx]); n++; }
      s /= n; if (s < best) { best = s; bx = dx; by = dy; }
    }
    return new int[] { bx, by, (int)(best * 100) };
  }
  public static byte[] Shift(byte[] e, int w, int h, int dx, int dy) {
    var o = new byte[e.Length];
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
      int sx = Math.Min(w - 1, Math.Max(0, x + dx)), sy = Math.Min(h - 1, Math.Max(0, y + dy));
      Buffer.BlockCopy(e, (sy * w + sx) * 4, o, (y * w + x) * 4, 4);
    }
    return o;
  }
  static float[] Blur(float[] v, int w, int h, int r) {
    var t = new float[w * h]; var o = new float[w * h];
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) { float s = 0; int n = 0; for (int k = -r; k <= r; k++) { int xx = x + k; if (xx < 0 || xx >= w) continue; s += v[y * w + xx]; n++; } t[y * w + x] = s / n; }
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) { float s = 0; int n = 0; for (int k = -r; k <= r; k++) { int yy = y + k; if (yy < 0 || yy >= h) continue; s += t[yy * w + x]; n++; } o[y * w + x] = s / n; }
    return o;
  }
  // per-pixel change (largest colour channel difference, after a light blur so noise and jpeg grain drop out)
  public static float[] Change(byte[] b, byte[] e, int w, int h) {
    var d = new float[w * h];
    for (int c = 0; c < 3; c++) {
      var cb = new float[w * h]; var ce = new float[w * h];
      for (int i = 0; i < w * h; i++) { cb[i] = b[i * 4 + c]; ce[i] = e[i * 4 + c]; }
      cb = Blur(cb, w, h, 2); ce = Blur(ce, w, h, 2);
      for (int i = 0; i < w * h; i++) d[i] = Math.Max(d[i], Math.Abs(cb[i] - ce[i]));
    }
    return d;
  }
  // regions: threshold, grow by g px, label connected parts; returns label map (0 = none) and per-label raw area.
  // With lo > 0, each clearly changed part (>= t) also takes in the fainter change (>= lo) it touches, so a dark
  // object whose colour changed only a little at its edges still comes out whole (hysteresis, as in edge finding).
  public static int[] Regions(float[] d, int w, int h, int t, int lo, int g, out List<int> areas) {
    var on = new bool[w * h]; for (int i = 0; i < w * h; i++) on[i] = d[i] >= t;
    if (lo > 0) {
      var q = new Stack<int>(); for (int i = 0; i < w * h; i++) if (on[i]) q.Push(i);
      while (q.Count > 0) { int p = q.Pop(), x = p % w, y = p / w;
        foreach (int n in new int[] { x > 0 ? p - 1 : -1, x < w - 1 ? p + 1 : -1, y > 0 ? p - w : -1, y < h - 1 ? p + w : -1 })
          if (n >= 0 && !on[n] && d[n] >= lo) { on[n] = true; q.Push(n); } }
    }
    var grown = new bool[w * h];
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) if (on[y * w + x])
      for (int yy = Math.Max(0, y - g); yy <= Math.Min(h - 1, y + g); yy++) for (int xx = Math.Max(0, x - g); xx <= Math.Min(w - 1, x + g); xx++) grown[yy * w + xx] = true;
    var lab = new int[w * h]; areas = new List<int> { 0 }; var st = new Stack<int>();
    for (int i = 0; i < w * h; i++) if (grown[i] && lab[i] == 0) {
      int id = areas.Count, a = 0; areas.Add(0); lab[i] = id; st.Push(i);
      while (st.Count > 0) { int p = st.Pop(); if (on[p]) a++; int x = p % w, y = p / w;
        if (x > 0 && grown[p - 1] && lab[p - 1] == 0) { lab[p - 1] = id; st.Push(p - 1); }
        if (x < w - 1 && grown[p + 1] && lab[p + 1] == 0) { lab[p + 1] = id; st.Push(p + 1); }
        if (y > 0 && grown[p - w] && lab[p - w] == 0) { lab[p - w] = id; st.Push(p - w); }
        if (y < h - 1 && grown[p + w] && lab[p + w] == 0) { lab[p + w] = id; st.Push(p + w); } }
      areas[id] = a;
    }
    return lab;
  }
  // id, x0, y0, x1, y1, area of every region with at least minArea changed px, largest first
  public static List<int[]> Boxes(int[] lab, int[] areas, int minArea, int w, int h) {
    var b = new Dictionary<int, int[]>();
    for (int i = 0; i < lab.Length; i++) { int id = lab[i]; if (id == 0 || areas[id] < minArea) continue; int x = i % w, y = i / w;
      int[] r; if (!b.TryGetValue(id, out r)) { b[id] = new int[] { id, x, y, x, y, areas[id] }; continue; }
      if (x < r[1]) r[1] = x; if (y < r[2]) r[2] = y; if (x > r[3]) r[3] = x; if (y > r[4]) r[4] = y; }
    var l = new List<int[]>(b.Values); l.Sort((p, q) => q[5].CompareTo(p[5])); return l;
  }
  // one piece: the edited pixels inside the region, with an alpha that fades over a few px at its edge
  public static Bitmap Piece(byte[] e, int[] lab, int id, int w, int x0, int y0, int pw, int ph) {
    var m = new float[pw * ph];
    for (int y = 0; y < ph; y++) for (int x = 0; x < pw; x++) m[y * pw + x] = lab[(y0 + y) * w + x0 + x] == id ? 1f : 0f;
    m = Blur(m, pw, ph, 3);
    var o = new byte[pw * ph * 4];
    for (int y = 0; y < ph; y++) for (int x = 0; x < pw; x++) {
      int s = ((y0 + y) * w + x0 + x) * 4, q = (y * pw + x) * 4;
      o[q] = e[s]; o[q + 1] = e[s + 1]; o[q + 2] = e[s + 2]; o[q + 3] = (byte)Math.Round(Math.Min(1f, m[y * pw + x] * 1.6f) * 255);
    }
    return FromPx(o, pw, ph);
  }
}
'@

$bImg = [System.Drawing.Bitmap]::new((Abs $Base))
$W = $bImg.Width; $H = $bImg.Height
$base32 = New-Object System.Drawing.Bitmap $W, $H, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($base32); $g.DrawImage($bImg, 0, 0, $W, $H); $g.Dispose(); $bImg.Dispose()
$eImg = [System.Drawing.Bitmap]::new((Abs $Edit))
$edit32 = New-Object System.Drawing.Bitmap $W, $H, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($edit32); $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'; $g.DrawImage($eImg, 0, 0, $W, $H); $g.Dispose()
Write-Output ("edited copy {0}x{1} scaled to {2}x{3}" -f $eImg.Width, $eImg.Height, $W, $H); $eImg.Dispose()

$pb = [DiffCut]::Px($base32); $pe = [DiffCut]::Px($edit32)
$al = [DiffCut]::Align($pb, $pe, $W, $H, 10)
Write-Output ("shift {0},{1}  mean diff after shift {2:N2}" -f $al[0], $al[1], ($al[2] / 100))
$pe = [DiffCut]::Shift($pe, $W, $H, $al[0], $al[1])
$d = [DiffCut]::Change($pb, $pe, $W, $H)
$areas = $null
$lab = [DiffCut]::Regions($d, $W, $H, $Thresh, $Low, $Grow, [ref]$areas)

$outDir = Abs $Out
if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
New-Item -ItemType Directory -Force $outDir | Out-Null
$boxes = [DiffCut]::Boxes($lab, $areas.ToArray(), $MinArea, $W, $H)
$map = New-Object System.Drawing.Bitmap $W, $H
$gm = [System.Drawing.Graphics]::FromImage($map); $gm.DrawImage($edit32, 0, 0, $W, $H)
# shift the edited picture's map the same way as the pixels
$gm.Dispose(); $map.Dispose()
$alignedEdit = [DiffCut]::FromPx($pe, $W, $H)
$map = New-Object System.Drawing.Bitmap $W, $H
$gm = [System.Drawing.Graphics]::FromImage($map); $gm.DrawImage($alignedEdit, 0, 0, $W, $H)
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Red), 3
$font = New-Object System.Drawing.Font 'Arial', 22, ([System.Drawing.FontStyle]::Bold)
$list = @(); $n = 0
foreach ($b in $boxes) {
  $pad = 4
  $x0 = [math]::Max(0, $b[1] - $pad); $y0 = [math]::Max(0, $b[2] - $pad); $x1 = [math]::Min($W - 1, $b[3] + $pad); $y1 = [math]::Min($H - 1, $b[4] + $pad)
  $pw = $x1 - $x0 + 1; $ph = $y1 - $y0 + 1
  $piece = [DiffCut]::Piece($pe, $lab, $b[0], $W, $x0, $y0, $pw, $ph)
  $piece.Save((Join-Path $outDir "p$n.png"), [System.Drawing.Imaging.ImageFormat]::Png); $piece.Dispose()
  $list += [ordered]@{ n = $n; x = $x0; y = $y0; w = $pw; h = $ph; area = $b[5] }
  $gm.DrawRectangle($pen, $x0, $y0, $pw, $ph)
  $gm.FillRectangle([System.Drawing.Brushes]::Black, $x0, [math]::Max(0, $y0 - 28), 40, 28)
  $gm.DrawString("$n", $font, [System.Drawing.Brushes]::Yellow, $x0 + 2, [math]::Max(0, $y0 - 28))
  $n++
}
$gm.Dispose()
$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 85L
$map.Save("$outDir-map.jpg", $codec, $ep); $map.Dispose()
$alignedEdit.Save("$outDir-aligned.png", [System.Drawing.Imaging.ImageFormat]::Png); $alignedEdit.Dispose()
($list | ConvertTo-Json -Depth 3) | Set-Content -Encoding utf8 (Join-Path $outDir 'pieces.json')
Write-Output ("{0} regions of {1}+ changed px  (map: {2}-map.jpg)" -f $n, $MinArea, $Out)
$list | ForEach-Object { Write-Output ("  p{0}: x{1} y{2} {3}x{4} area {5}" -f $_.n, $_.x, $_.y, $_.w, $_.h, $_.area) }
