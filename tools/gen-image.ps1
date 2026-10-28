# Generate images with the Gemini API and save game-ready copies.
#   Single:  .\tools\gen-image.ps1 -Name octopus -Prompt "..." -Aspect 1:1 -Size 256
#   Batch:   .\tools\gen-image.ps1 -Manifest tools\images.json [-Only name1,name2] [-Force]
# The API key is read from .env (GEMINI_API_KEY=...) and never printed.
# Full-size originals go to gen-raw\ (not shipped); resized copies go to assets\.
param(
  [string]$Name,
  [string]$Prompt,
  [string]$Aspect = '1:1',
  [int]$Size = 256,          # longest edge of the shipped copy, in px
  [ValidateSet('png', 'jpg')][string]$Format = 'png',
  [string]$Manifest,
  [string[]]$Only,
  [switch]$Force,
  [string]$Model = 'gemini-3.1-flash-image'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$raw = Join-Path $root 'gen-raw'
$assets = Join-Path $root 'assets'
New-Item -ItemType Directory -Force $raw, $assets | Out-Null

$envLine = Get-Content (Join-Path $root '.env') | Where-Object { $_ -like 'GEMINI_API_KEY=*' } | Select-Object -First 1
if (-not $envLine) { throw '.env has no GEMINI_API_KEY line' }
$key = ($envLine -replace '^GEMINI_API_KEY=', '').Trim()

function Save-Resized([string]$src, [string]$dst, [int]$edge, [string]$fmt) {
  $img = [System.Drawing.Image]::FromFile($src)
  try {
    $scale = [Math]::Min(1.0, $edge / [Math]::Max($img.Width, $img.Height))
    $w = [int]($img.Width * $scale); $h = [int]($img.Height * $scale)
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'
    $g.DrawImage($img, 0, 0, $w, $h)
    $g.Dispose()
    if ($fmt -eq 'jpg') {
      $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
      $ep = New-Object System.Drawing.Imaging.EncoderParameters 1
      $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 82L
      $bmp.Save($dst, $codec, $ep)
    } else {
      $bmp.Save($dst, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    $bmp.Dispose()
  } finally { $img.Dispose() }
}

function New-GeminiImage([string]$name, [string]$prompt, [string]$aspect, [int]$size, [string]$fmt) {
  $out = Join-Path $assets "$name.$fmt"
  if ((Test-Path $out) -and -not $Force) { Write-Output "skip  $name (exists)"; return }
  $body = @{
    contents         = @(@{ parts = @(@{ text = $prompt }) })
    generationConfig = @{ responseModalities = @('IMAGE'); imageConfig = @{ aspectRatio = $aspect } }
  } | ConvertTo-Json -Depth 8
  $uri = "https://generativelanguage.googleapis.com/v1beta/models/${Model}:generateContent"
  for ($try = 1; $try -le 3; $try++) {
    try {
      $res = Invoke-RestMethod -Method Post -Uri $uri -Headers @{ 'x-goog-api-key' = $key } -ContentType 'application/json; charset=utf-8' `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 180
      $part = $res.candidates[0].content.parts | Where-Object { $_.inlineData } | Select-Object -First 1
      if (-not $part) { throw 'no image in response' }
      $rawFile = Join-Path $raw "$name.png"
      [System.IO.File]::WriteAllBytes($rawFile, [Convert]::FromBase64String($part.inlineData.data))
      Save-Resized $rawFile $out $size $fmt
      Write-Output ("ok    {0} -> assets\{0}.{1} ({2:N0} KB)" -f $name, $fmt, ((Get-Item $out).Length / 1KB))
      return
    } catch {
      $msg = $_.Exception.Message
      if ($try -eq 3) { Write-Output "FAIL  $name : $msg"; return }
      Start-Sleep -Seconds (5 * $try)
    }
  }
}

if ($Manifest) {
  $items = Get-Content $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($it in $items) {
    if ($Only -and ($Only -notcontains $it.name)) { continue }
    $a = if ($it.aspect) { $it.aspect } else { '1:1' }
    $s = if ($it.size) { [int]$it.size } else { 256 }
    $f = if ($it.format) { $it.format } else { 'png' }
    New-GeminiImage $it.name $it.prompt $a $s $f
  }
} elseif ($Name -and $Prompt) {
  New-GeminiImage $Name $Prompt $Aspect $Size $Format
} else {
  throw 'Pass -Name and -Prompt, or -Manifest'
}
