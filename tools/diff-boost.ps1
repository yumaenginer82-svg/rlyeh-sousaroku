# Make the colour differences easier to see: each colour piece is pushed further from the original picture
# (new = original + k * (piece - original), per pixel and channel) until its mean colour change reaches a floor,
# both for normal sight and for red-green colour blindness (deuteranopia). Shapes and edges stay as they are.
#   .\tools\diff-boost.ps1 [-Normal 30] [-Deut 18] [-MaxK 2.4]
# The pieces before boosting are kept in gen-raw\df<n>-preboost\.
param([double]$Normal = 30, [double]$Deut = 18, [double]$MaxK = 2.4)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class Boost {
  static double F(double t) { return t > 0.008856 ? Math.Pow(t, 1.0 / 3) : 7.787 * t + 16.0 / 116; }
  static double Lin(double c) { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.Pow((c + 0.055) / 1.055, 2.4); }
  static double[] Lab(double r, double g, double b) {
    double R = Lin(r), G = Lin(g), B = Lin(b);
    double X = (0.4124 * R + 0.3576 * G + 0.1805 * B) / 0.95047, Y = 0.2126 * R + 0.7152 * G + 0.0722 * B, Z = (0.0193 * R + 0.1192 * G + 0.9505 * B) / 1.08883;
    return new double[] { 116 * F(Y) - 16, 500 * (F(X) - F(Y)), 200 * (F(Y) - F(Z)) };
  }
  static double C(double v) { return v < 0 ? 0 : v > 255 ? 255 : v; }
  static double[] Deu(double r, double g, double b) { return new double[] { C(0.367 * r + 0.861 * g - 0.228 * b), C(0.280 * r + 0.673 * g + 0.047 * b), C(-0.012 * r + 0.043 * g + 0.969 * b) }; }
  static double D(double[] a, double[] b) { return Math.Sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]) + (a[2] - b[2]) * (a[2] - b[2])); }
  static byte[] Px(Bitmap b) { var d = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb); var a = new byte[d.Stride * b.Height]; Marshal.Copy(d.Scan0, a, 0, a.Length); b.UnlockBits(d); return a; }
  // mean change (normal, deuteranopia) of a piece pushed by k over the original
  public static double[] Score(byte[] o, byte[] p, double k) {
    double s = 0, sd = 0; int n = 0;
    for (int i = 0; i < p.Length; i += 4) {
      if (p[i + 3] < 200) continue;
      double b = C(o[i] + k * (p[i] - o[i])), g = C(o[i + 1] + k * (p[i + 1] - o[i + 1])), r = C(o[i + 2] + k * (p[i + 2] - o[i + 2]));
      s += D(Lab(o[i + 2], o[i + 1], o[i]), Lab(r, g, b));
      double[] od = Deu(o[i + 2], o[i + 1], o[i]), pd = Deu(r, g, b);
      sd += D(Lab(od[0], od[1], od[2]), Lab(pd[0], pd[1], pd[2])); n++;
    }
    return new double[] { s / Math.Max(1, n), sd / Math.Max(1, n) };
  }
  public static byte[] Under(Bitmap baseImg, int x0, int y0, int w, int h) {
    using (var c = baseImg.Clone(new Rectangle(x0, y0, w, h), PixelFormat.Format32bppArgb)) return Px(c);
  }
  public static byte[] Pixels(Bitmap b) { using (var c = b.Clone(new Rectangle(0, 0, b.Width, b.Height), PixelFormat.Format32bppArgb)) return Px(c); }
  public static Bitmap Make(byte[] o, byte[] p, double k, int w, int h) {
    var q = new byte[p.Length];
    for (int i = 0; i < p.Length; i += 4) { for (int c = 0; c < 3; c++) q[i + c] = (byte)Math.Round(C(o[i + c] + k * (p[i + c] - o[i + c]))); q[i + 3] = p[i + 3]; }
    var b = new Bitmap(w, h, PixelFormat.Format32bppArgb);
    var d = b.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb); Marshal.Copy(q, 0, d.Scan0, q.Length); b.UnlockBits(d);
    return b;
  }
}
'@
for ($s = 0; $s -le 5; $s++) {
  $keep = Join-Path $root "gen-raw\df$s-preboost"; New-Item -ItemType Directory -Force $keep | Out-Null
  $base = New-Object System.Drawing.Bitmap (Join-Path $root "assets\bg-df$s.jpg")
  foreach ($l in (Get-Content (Join-Path $root "gen-raw\df$s-final.js") -Encoding UTF8)) {
    $m = [regex]::Match($l, "f: (\d+), x: (\d+), y: (\d+), w: (\d+), h: (\d+), k: 'color'")
    if (-not $m.Success) { continue }
    $f = $m.Groups[1].Value; $x = [int]$m.Groups[2].Value; $y = [int]$m.Groups[3].Value; $w = [int]$m.Groups[4].Value; $h = [int]$m.Groups[5].Value
    $src = Join-Path $keep "p$f.png"
    if (-not (Test-Path $src)) { Copy-Item (Join-Path $root "assets\df$s\p$f.png") $src }   # always boost from the original piece
    $pc = New-Object System.Drawing.Bitmap $src
    $o = [Boost]::Under($base, $x, $y, $w, $h); $p = [Boost]::Pixels($pc)
    $k = 1.0; $sc = [Boost]::Score($o, $p, $k); $before = $sc
    while (($sc[0] -lt $Normal -or $sc[1] -lt $Deut) -and $k -lt $MaxK) { $k = [math]::Round($k + 0.1, 2); $sc = [Boost]::Score($o, $p, $k) }
    $out = [Boost]::Make($o, $p, $k, $w, $h); $pc.Dispose()
    $out.Save((Join-Path $root "assets\df$s\p$f.png"), [System.Drawing.Imaging.ImageFormat]::Png); $out.Dispose()
    "df{0} p{1}  k {2:N1}  dE {3,5:N1} -> {4,5:N1}   deut {5,5:N1} -> {6,5:N1}" -f $s, $f, $k, $before[0], $sc[0], $before[1], $sc[1]
  }
  $base.Dispose()
}
