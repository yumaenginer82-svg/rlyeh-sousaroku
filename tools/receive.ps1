# Tiny local receiver: the browser POSTs generated images here and they land in gen-raw\.
#   POST http://localhost:8766/upload?name=m-0-4   (body = image bytes)
# Listens on localhost only; stop it with Ctrl+C or by ending the process.
param([int]$Port = 8766)
$root = Split-Path $PSScriptRoot -Parent
$raw = Join-Path $root 'gen-raw'
New-Item -ItemType Directory -Force $raw | Out-Null
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Output "receiving into $raw on http://localhost:$Port/"
while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $req = $ctx.Request; $res = $ctx.Response
  $res.Headers.Add('Access-Control-Allow-Origin', '*')
  $res.Headers.Add('Access-Control-Allow-Methods', 'POST, OPTIONS')
  $res.Headers.Add('Access-Control-Allow-Headers', '*')
  $res.Headers.Add('Access-Control-Allow-Private-Network', 'true')
  if ($req.HttpMethod -eq 'POST' -and $req.Url.AbsolutePath -eq '/upload') {
    $name = $req.QueryString['name'] -replace '[^A-Za-z0-9_\-]', ''
    if ($name) {
      $ms = New-Object System.IO.MemoryStream
      $req.InputStream.CopyTo($ms)
      $ext = if ($req.ContentType -like '*jpeg*') { 'jpg' } elseif ($req.ContentType -like '*webp*') { 'webp' } else { 'png' }
      $file = Join-Path $raw "$name.$ext"
      [System.IO.File]::WriteAllBytes($file, $ms.ToArray())
      Write-Output ("saved {0}.{1} ({2:N0} KB)" -f $name, $ext, ($ms.Length / 1KB))
      $bytes = [System.Text.Encoding]::UTF8.GetBytes("ok $name.$ext $($ms.Length)")
    } else { $res.StatusCode = 400; $bytes = [System.Text.Encoding]::UTF8.GetBytes('bad name') }
  } else { $bytes = [System.Text.Encoding]::UTF8.GetBytes('ready') }
  $res.OutputStream.Write($bytes, 0, $bytes.Length)
  $res.Close()
}
