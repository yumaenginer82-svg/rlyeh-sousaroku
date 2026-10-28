# Turn raw Gemini images (gen-raw\) into game assets (assets\).
#   m-* g-* x-*  item icons  -> white background removed (incl. enclosed gaps), soft edge, PNG with alpha
#   f-*          engraved finds -> paper tint neutralised to pure white (they are drawn with multiply), PNG
#   bg-*         scene backdrops -> JPEG
#   .\tools\process.ps1 [-Only m-0-4,g-0]
param([string[]]$Only, [int]$IconSize = 320, [int]$FindSize = 256, [int]$BgWidth = 2400)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class Cut {
  static Bitmap Resize(Image src, int w, int h) {
    var b = new Bitmap(w, h, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(b)) {
      g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
      g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
      g.DrawImage(src, 0, 0, w, h);
    }
    return b;
  }
  static byte[] Read(Bitmap b) {
    var d = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
    var px = new byte[d.Stride * b.Height];
    Marshal.Copy(d.Scan0, px, 0, px.Length); b.UnlockBits(d); return px;
  }
  static void Write(Bitmap b, byte[] px) {
    var d = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
    Marshal.Copy(px, 0, d.Scan0, px.Length); b.UnlockBits(d);
  }

  // Background = near-white regions touching the border, plus enclosed near-white regions big enough
  // to be gaps (between tentacles, inside net loops) rather than highlights.
  public static string Icon(string src, string dst, int size) {
    using (var img = Image.FromFile(src))
    using (var b = Resize(img, size, size)) {
      int W = size, H = size, N = W * H;
      var p = Read(b);
      Func<int, bool> nearWhite = i => {
        int bl = p[i*4], gr = p[i*4+1], r = p[i*4+2];
        int mn = Math.Min(r, Math.Min(gr, bl)), mx = Math.Max(r, Math.Max(gr, bl));
        return mn >= 222 && mx - mn <= 28;
      };
      var label = new int[N]; // 0 = unvisited, -1 = object, k>0 = near-white component id
      var touches = new List<bool> { false }; var sizes = new List<int> { 0 }; var sums = new List<long> { 0 };
      var q = new Stack<int>();
      for (int s = 0; s < N; s++) {
        if (label[s] != 0) continue;
        if (!nearWhite(s)) { label[s] = -1; continue; }
        int id = sizes.Count; sizes.Add(0); touches.Add(false); sums.Add(0);
        q.Push(s); label[s] = id;
        while (q.Count > 0) {
          int i = q.Pop(); sizes[id]++;
          sums[id] += Math.Min(p[i*4+2], Math.Min(p[i*4+1], p[i*4]));
          int x = i % W, y = i / W;
          if (x == 0 || y == 0 || x == W - 1 || y == H - 1) touches[id] = true;
          int[] nb = { x > 0 ? i - 1 : -1, x < W - 1 ? i + 1 : -1, y > 0 ? i - W : -1, y < H - 1 ? i + W : -1 };
          foreach (int j in nb) if (j >= 0 && label[j] == 0) { if (nearWhite(j)) { label[j] = id; q.Push(j); } else label[j] = -1; }
        }
      }
      // Big enclosed white areas are gaps. Small ones are gaps only when flat paper-white
      // (painted highlights are smaller and rarely that bright on average).
      int minGap = Math.Max(12, N / 900), minFlat = Math.Max(6, N / 8000);
      var isBg = new bool[sizes.Count]; int holes = 0;
      for (int id = 1; id < sizes.Count; id++) {
        double mean = (double)sums[id] / sizes[id];
        isBg[id] = touches[id] || sizes[id] >= minGap || (sizes[id] >= minFlat && mean >= 242);
        if (isBg[id] && !touches[id]) holes++;
      }
      var bg = new bool[N];
      for (int i = 0; i < N; i++) { int id = label[i]; bg[i] = id > 0 && isBg[id]; }
      // distance (in px, up to 3) from the background, to fade the white sticker outline
      var dist = new int[N];
      for (int i = 0; i < N; i++) dist[i] = bg[i] ? 0 : 99;
      for (int pass = 1; pass <= 3; pass++)
        for (int i = 0; i < N; i++) if (dist[i] == 99) {
          int x = i % W, y = i / W;
          if ((x > 0 && dist[i-1] == pass-1) || (x < W-1 && dist[i+1] == pass-1) || (y > 0 && dist[i-W] == pass-1) || (y < H-1 && dist[i+W] == pass-1)) dist[i] = pass;
        }
      for (int i = 0; i < N; i++) {
        if (bg[i]) { p[i*4+3] = 0; continue; }
        if (dist[i] > 3) continue;
        int bl = p[i*4], gr = p[i*4+1], r = p[i*4+2];
        int mn = Math.Min(r, Math.Min(gr, bl));
        // light fringe pixels fade out; darker edge pixels stay solid
        double a = mn <= 170 ? 1.0 : Math.Max(0.0, (235.0 - mn) / 65.0);
        if (dist[i] == 1) a = Math.Min(a, 0.85);
        if (a <= 0.02) { p[i*4+3] = 0; continue; }
        // un-mix the white the edge was blended with
        p[i*4]   = (byte)Math.Max(0, Math.Min(255, (bl - 255 * (1 - a)) / a));
        p[i*4+1] = (byte)Math.Max(0, Math.Min(255, (gr - 255 * (1 - a)) / a));
        p[i*4+2] = (byte)Math.Max(0, Math.Min(255, (r  - 255 * (1 - a)) / a));
        p[i*4+3] = (byte)(a * 255);
      }
      Write(b, p);
      b.Save(dst, ImageFormat.Png);
      return "holes removed: " + holes;
    }
  }

  // Engravings are composited with multiply, so the paper colour must become pure white.
  public static string Find(string src, string dst, int size) {
    using (var img = Image.FromFile(src))
    using (var b = Resize(img, size, size)) {
      int W = size, H = size; var p = Read(b);
      // paper colour = brightest common colour near the border
      var rs = new List<int>(); var gs = new List<int>(); var bs = new List<int>();
      for (int i = 0; i < W * H; i++) { int x = i % W, y = i / W; if (x < 6 || y < 6 || x >= W - 6 || y >= H - 6) { bs.Add(p[i*4]); gs.Add(p[i*4+1]); rs.Add(p[i*4+2]); } }
      rs.Sort(); gs.Sort(); bs.Sort();
      int k = (int)(rs.Count * 0.7);
      double pr = Math.Max(120, rs[k]), pg = Math.Max(120, gs[k]), pb = Math.Max(120, bs[k]);
      for (int i = 0; i < W * H; i++) {
        double r = p[i*4+2] / pr, g = p[i*4+1] / pg, bl = p[i*4] / pb;
        // desaturate to ink, then push near-paper to white
        double l = Math.Min(1.0, 0.3 * r + 0.59 * g + 0.11 * bl);
        l = l > 0.9 ? 1.0 : l / 0.9;
        byte v = (byte)(Math.Pow(l, 1.15) * 255);
        p[i*4] = v; p[i*4+1] = v; p[i*4+2] = v; p[i*4+3] = 255;
      }
      Write(b, p);
      b.Save(dst, ImageFormat.Png);
      return string.Format("paper was {0:0},{1:0},{2:0}", pr, pg, pb);
    }
  }

  public static string Backdrop(string src, string dst, int width) {
    using (var img = Image.FromFile(src)) {
      int w = Math.Min(width, img.Width), h = (int)Math.Round(img.Height * (double)w / img.Width);
      using (var b = Resize(img, w, h)) {
        var codec = Array.Find(ImageCodecInfo.GetImageEncoders(), c => c.MimeType == "image/jpeg");
        var ep = new EncoderParameters(1); ep.Param[0] = new EncoderParameter(Encoder.Quality, 84L);
        b.Save(dst, codec, ep);
        return w + "x" + h;
      }
    }
  }
}
'@
$root = Split-Path $PSScriptRoot -Parent
$raw = Join-Path $root 'gen-raw'; $assets = Join-Path $root 'assets'
New-Item -ItemType Directory -Force $assets | Out-Null
Get-ChildItem $raw -File | Where-Object { $_.Extension -in '.jpg', '.png', '.webp' } | ForEach-Object {
  $name = $_.BaseName
  if ($name -like 'sheet-*') { return }   # 2x2 sheets are split by split-sheet.ps1 first
  if ($Only -and ($Only -notcontains $name)) { return }
  if ($name -like 'bg-*' -or $name -like 'hs-*') { $out = Join-Path $assets "$name.jpg"; $info = [Cut]::Backdrop($_.FullName, $out, $BgWidth) }
  elseif ($name -like 'f-*') { $out = Join-Path $assets "$name.png"; $info = [Cut]::Find($_.FullName, $out, $FindSize) }
  else { $out = Join-Path $assets "$name.png"; $info = [Cut]::Icon($_.FullName, $out, $IconSize) }
  "{0,-12} {1,6:N0} KB  {2}" -f $name, ((Get-Item $out).Length / 1KB), $info
}
