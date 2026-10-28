# Rebuild the HIDDEN table in index.html from tools\scenes\hs-*.json, so the game always matches the annotations.
#   .\tools\sync-hidden.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$asset = @{ 'hs-0' = 'hs-0b' }   # the first tavern picture was replaced; its asset keeps the new name
$nl = "`n"
$body = foreach ($f in Get-ChildItem (Join-Path $PSScriptRoot 'scenes') -Filter 'hs-*.json' | Sort-Object Name) {
  $j = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
  $key = if ($asset[$j.image]) { $asset[$j.image] } else { $j.image }
  "  '$key': { w: $($j.w), h: $($j.h), items: ["
  foreach ($it in $j.items) { $at = ($it.at | ForEach-Object { '[' + ($_ -join ',') + ']' }) -join ','; "    { id: '$($it.id)', ja: '$($it.ja)', at: [$at] }," }
  '  ] },'
}
$f = Join-Path $root 'index.html'
$t = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)
$crlf = $t.Contains("`r`n"); if ($crlf) { $t = $t.Replace("`r`n", "`n") }
$a = $t.IndexOf("const HIDDEN = {$nl"); $b = $t.IndexOf("$nl};$nl", $a)
if ($a -lt 0 -or $b -lt 0) { throw 'HIDDEN block not found' }
$t = $t.Substring(0, $a) + "const HIDDEN = {$nl" + ($body -join $nl) + $t.Substring($b)
if ($crlf) { $t = $t.Replace("`n", "`r`n") }
[IO.File]::WriteAllText($f, $t, (New-Object Text.UTF8Encoding $false))
"HIDDEN rebuilt: $(($body | Where-Object { $_ -like "  '*" }).Count) scenes"
