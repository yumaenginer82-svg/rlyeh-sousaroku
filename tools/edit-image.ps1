# Edit an existing picture with the Gemini API (the picture goes in with the prompt) and keep the result in gen-raw\.
#   .\tools\edit-image.ps1 -Src assets\bg-df0.jpg -Name df0-edit -Prompt "..."
# The API key is read from .env (GEMINI_API_KEY=...) and never printed.
param(
  [Parameter(Mandatory)][string]$Src,
  [Parameter(Mandatory)][string]$Name,
  [Parameter(Mandatory)][string]$Prompt,
  [string]$Aspect = '4:3',
  [string]$Model = 'gemini-3.1-flash-image'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$raw = Join-Path $root 'gen-raw'
New-Item -ItemType Directory -Force $raw | Out-Null
$envLine = Get-Content (Join-Path $root '.env') | Where-Object { $_ -like 'GEMINI_API_KEY=*' } | Select-Object -First 1
if (-not $envLine) { throw '.env has no GEMINI_API_KEY line' }
$key = ($envLine -replace '^GEMINI_API_KEY=', '').Trim()

$srcPath = if ([System.IO.Path]::IsPathRooted($Src)) { $Src } else { Join-Path $root $Src }
$bytes = [System.IO.File]::ReadAllBytes($srcPath)
$mime = if ($bytes[0] -eq 0xFF) { 'image/jpeg' } else { 'image/png' }
$body = @{
  contents         = @(@{ parts = @(@{ inlineData = @{ mimeType = $mime; data = [Convert]::ToBase64String($bytes) } }, @{ text = $Prompt }) })
  generationConfig = @{ responseModalities = @('IMAGE'); imageConfig = @{ aspectRatio = $Aspect } }
} | ConvertTo-Json -Depth 8
$uri = "https://generativelanguage.googleapis.com/v1beta/models/${Model}:generateContent"
for ($try = 1; $try -le 3; $try++) {
  try {
    $res = Invoke-RestMethod -Method Post -Uri $uri -Headers @{ 'x-goog-api-key' = $key } -ContentType 'application/json; charset=utf-8' `
      -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 300
    $part = $res.candidates[0].content.parts | Where-Object { $_.inlineData } | Select-Object -First 1
    if (-not $part) { throw 'no image in response' }
    $out = Join-Path $raw "$Name.png"
    [System.IO.File]::WriteAllBytes($out, [Convert]::FromBase64String($part.inlineData.data))
    Add-Type -AssemblyName System.Drawing
    $i = [System.Drawing.Image]::FromFile($out); $w = $i.Width; $h = $i.Height; $i.Dispose()
    Write-Output "ok    $Name -> gen-raw\$Name.png (${w}x${h})"
    exit 0
  } catch {
    $msg = $_.Exception.Message
    if ($try -eq 3) { Write-Output "FAIL  $Name : $msg"; exit 1 }
    Start-Sleep -Seconds (5 * $try)
  }
}
