# Builds latest.html: a phone-first digest of the current NWS products for Isaias and for Fairhope, AL.
# Every value on the page is NWS text, quoted verbatim or reformatted (case, line wraps, UTC -> CDT) without
# changing its meaning. Nothing is computed from model data here; that is index.html's job.
#   powershell -ExecutionPolicy Bypass -File tools/build_latest.ps1 -Root <repo path>
# Raw products are saved to data/raw/nws/ (git-ignored) so every line on the page can be checked against them.
param([string]$Root = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Storm = 'AL092026'; $Bin = 'AT4'; $Office = 'MOB'
$Place = 'Fairhope, AL'; $Lat = '30.5229'; $Lon = '-87.9033'
$PwsPlaces = @('MOBILE AL', 'PENSACOLA FL', 'WHITING FLD FL', 'GULFPORT MS', 'DESTIN EXEC AP', 'MONTGOMERY AL')
$Hdr = @{ 'User-Agent' = 'static_hurricane_info_site (github.com/LukeMcCulloch/static_hurricane_info_site)'; 'Accept' = 'application/geo+json' }
$Raw = Join-Path $Root 'data\raw\nws'
New-Item -ItemType Directory -Force $Raw | Out-Null
$Central = [TimeZoneInfo]::FindSystemTimeZoneById('Central Standard Time')

function Get-Api([string]$url) {
  for ($i = 1; $i -le 5; $i++) {
    try { return Invoke-RestMethod -Uri $url -Headers $Hdr -TimeoutSec 60 } catch { if ($i -eq 5) { throw "GET $url failed: $($_.Exception.Message)" }; Start-Sleep 4 }
  }
}
function Get-Product([string]$type, [string]$loc, [string]$must) {
  $list = Get-Api "https://api.weather.gov/products/types/$type/locations/$loc"
  foreach ($item in $list.'@graph' | Select-Object -First 3) {
    $p = Get-Api $item.'@id'
    $t = ($p.productText -replace "`r", '')
    if (-not $must -or $t -match $must) {
      [IO.File]::WriteAllText((Join-Path $Raw "$type.txt"), $t, (New-Object Text.UTF8Encoding $false))
      return [pscustomobject]@{ Text = $t; Lines = ($t -split "`n"); Issued = [DateTimeOffset]::Parse($p.issuanceTime); Wmo = "$($p.wmoCollectiveId) $($p.issuingOffice)"; Id = $p.id }
    }
  }
  throw "No $type for $loc matching '$must'"
}
function Esc([string]$s) { [Net.WebUtility]::HtmlEncode($s) }
function CDT([DateTimeOffset]$t) { [TimeZoneInfo]::ConvertTime($t, $Central).ToString('ddd h:mm tt', [Globalization.CultureInfo]::InvariantCulture) + ' CDT' }
function Utc([DateTimeOffset]$t) { $t.UtcDateTime.ToString('HH:mm') + 'Z' }
function Stamp([DateTimeOffset]$t) { "$(CDT $t) ($(Utc $t))" }
# Paragraphs: split on blank lines, unwrap each into one line.
function Paras([string[]]$lines) {
  $out = @(); $cur = @()
  foreach ($l in $lines) { if ($l.Trim() -eq '') { if ($cur) { $out += (($cur -join ' ') -replace '\s+', ' ').Trim(); $cur = @() } } else { $cur += $l.Trim() } }
  if ($cur) { $out += (($cur -join ' ') -replace '\s+', ' ').Trim() }
  return ,$out
}
# Lines between the first line matching $from (exclusive) and the next line matching $to (exclusive).
function Between([string[]]$lines, [string]$from, [string]$to) {
  $a = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $from) { $a = $i + 1; break } }
  if ($a -lt 0) { return ,@() }
  if ($a -lt $lines.Count -and $lines[$a] -match '^\s*-{3,}\s*$') { $a++ }
  $b = $lines.Count; for ($i = $a; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $to) { $b = $i; break } }
  if ($b -le $a) { return ,@() }
  return ,$lines[$a..($b - 1)]
}
# "- item" bullet lists with indented continuation lines, unwrapped.
function Bullets([string[]]$lines) {
  $out = @()
  foreach ($l in $lines) {
    if ($l -match '^\s*-\s+(.*)$') { $out += $Matches[1].Trim() }
    elseif ($l.Trim() -ne '' -and $out.Count) { $out[$out.Count - 1] = ($out[$out.Count - 1] + ' ' + $l.Trim()) }
  }
  return ,$out
}
function Sentence([string]$s) { # NHC/NWS all-caps text -> sentence case for reading on a phone; meaning unchanged.
  $s = $s.ToLower(); if ($s.Length) { $s = $s.Substring(0, 1).ToUpper() + $s.Substring(1) }; return $s
}

# ---------- NHC products ----------
$tcp = Get-Product 'TCP' $Bin $Storm
$tcd = Get-Product 'TCD' $Bin $Storm
$pws = Get-Product 'PWS' $Bin $Storm
$tcm = Get-Product 'TCM' $Bin $Storm

$tcpTitle = ($tcp.Lines | Where-Object { $_ -match 'Advisory Number' } | Select-Object -First 1).Trim()
$stormName = if ($tcpTitle -match '^(.*?) (Intermediate )?(Public )?Advisory') { $Matches[1] } else { 'Isaias' }
$tcpHead = Between $tcp.Lines '^\d{3,4} (AM|PM) [A-Z]{3} ' '^SUMMARY OF'
# Lines before the first "..." headline are a correction notice (e.g. "Corrected storm surge values"), shown separately.
$tcpNote = ''; $hl = @(); $inHead = $false
foreach ($l in $tcpHead) { $t = $l.Trim(); if ($t -match '^\.\.\.') { $inHead = $true }; if ($inHead) { $hl += $t } elseif ($t) { $tcpNote = ($tcpNote + ' ' + $t).Trim() } }
$headlines = @((($hl -join ' ') -split '\.\.\.\s*\.\.\.') | ForEach-Object { $_.Trim(' ', '.') } | Where-Object { $_ })
$summary = [ordered]@{}
$tcpTitle = $tcpTitle -replace '\s+', ' '
foreach ($l in (Between $tcp.Lines '^SUMMARY OF' '^WATCHES AND WARNINGS')) { if ($l -match '^(ABOUT) (.+)$' -or $l -match '^([A-Z ]+?)\.\.\.(.+)$') { $k = $Matches[1]; if ($summary.Contains($k)) { $summary[$k] += '; ' + $Matches[2].Trim() } else { $summary[$k] = $Matches[2].Trim() } } }
foreach ($k in 'LOCATION', 'MAXIMUM SUSTAINED WINDS', 'PRESENT MOVEMENT', 'MINIMUM CENTRAL PRESSURE') { if (-not $summary.Contains($k)) { throw "TCP summary missing $k" } }

# Watches/warnings: stop at the boilerplate definitions ("A Hurricane Warning means ...").
$ww = Between $tcp.Lines '^WATCHES AND WARNINGS' '^DISCUSSION AND OUTLOOK'
$changes = @(); $groups = @(); $mode = ''
foreach ($l in $ww) {
  $t = $l.Trim()
  if ($t -match '^An? .*(Warning|Watch) means' -or $t -match '^For storm information specific') { break }
  if ($t -match '^CHANGES WITH THIS ADVISORY') { $mode = 'c'; continue }
  if ($t -match '^SUMMARY OF WATCHES AND WARNINGS') { $mode = 's'; continue }
  if ($t -eq '') { continue }
  if ($mode -eq 'c') { if ($t -match '^\*\s*(.*)$') { $changes += $Matches[1] } elseif ($changes.Count -and $t -notmatch '^(The|A|An) ') { $changes[$changes.Count - 1] += ' ' + $t } else { $changes += $t } }
  elseif ($mode -eq 's') {
    if ($t -match '^(An? .+?) (is|are) in effect for') { $groups += [pscustomobject]@{ Name = $Matches[1] -replace '^An? ', ''; Areas = @() } }
    elseif ($t -match '^\*\s*(.*)$' -and $groups.Count) { $groups[$groups.Count - 1].Areas += $Matches[1] }
  }
}
if (-not $groups.Count) { throw 'TCP: no watches/warnings parsed' }
$outlook = Paras (Between $tcp.Lines '^DISCUSSION AND OUTLOOK' '^HAZARDS AFFECTING LAND')

# Hazards: "STORM SURGE: ...", "WIND: ...". Keep surge-height lists as lists.
$hz = Between $tcp.Lines '^HAZARDS AFFECTING LAND' '^NEXT ADVISORY'
$hazards = [ordered]@{}; $key = $null; $buf = @()
$blocks = @(); $cur = @()
foreach ($l in $hz) { if ($l.Trim() -eq '') { if ($cur) { $blocks += ,$cur; $cur = @() } } else { $cur += $l.Trim() } }
if ($cur) { $blocks += ,$cur }
foreach ($b in $blocks) {
  $first = $b[0]
  if ($first -match '^([A-Z][A-Z ]+):\s*(.*)$') { $key = $Matches[1]; $hazards[$key] = @(); $b = @($Matches[2]) + @($b | Select-Object -Skip 1) }
  if (-not $key) { continue }
  $joined = (($b -join ' ') -replace '\s+', ' ').Trim()
  if ($joined -match '^(For a complete depiction|A depiction of|Key messages for)') { continue }
  if (@($b | Where-Object { $_ -match '\.\.\.\s*[\d-]+\s*ft\s*$' }).Count -eq $b.Count) { $hazards[$key] += ,([pscustomobject]@{ List = @($b | ForEach-Object { $_ -replace '\.\.\.', ': ' }) }) }
  elseif ($joined) { $hazards[$key] += ,([pscustomobject]@{ Text = $joined }) }
}
foreach ($k in 'STORM SURGE', 'WIND', 'RAINFALL') { if (-not $hazards.Contains($k)) { Write-Warning "TCP: no $k hazard paragraph" } }
$nextAdv = (Paras (Between $tcp.Lines '^NEXT ADVISORY' '^\$\$')) -join ' '

# TCD: key messages, forecast table, forecaster reasoning.
$tcdTitle = ($tcd.Lines | Where-Object { $_ -match 'Discussion Number' } | Select-Object -First 1) -replace '\s+', ' '
$km = Between $tcd.Lines '^\s*Key Messages:' '^FORECAST POSITIONS'
$keyMsgs = @(); foreach ($p in (Paras $km)) { if ($p -match '^\d+\.\s*(.*)$') { $keyMsgs += $Matches[1] } elseif ($keyMsgs.Count) { $keyMsgs[$keyMsgs.Count - 1] += ' ' + $p } }
if (-not $keyMsgs.Count) { Write-Warning 'TCD: no key messages' }
$reason = Paras (Between $tcd.Lines '^\d{3,4} (AM|PM) [A-Z]{3} ' '^\s*Key Messages:')
$fc = @()
$iss = $tcd.Issued.UtcDateTime
foreach ($l in (Between $tcd.Lines '^FORECAST POSITIONS' '^\$\$')) {
  if ($l -match '^\s*(INIT|\d+H)\s+(\d\d)/(\d\d)(\d\d)Z\s+(.*)$') {
    $day = [int]$Matches[2]; $mon = $iss.Month; $yr = $iss.Year
    if ($day -lt $iss.Day - 7) { $mon++; if ($mon -gt 12) { $mon = 1; $yr++ } }
    $t = New-Object DateTimeOffset ($yr, $mon, $day, [int]$Matches[3], [int]$Matches[4], 0, [TimeSpan]::Zero)
    $rest = $Matches[5].Trim(); $row = [pscustomobject]@{ Tau = $Matches[1]; Time = $t; Pos = ''; Kt = ''; Mph = ''; Note = '' }
    if ($rest -match '^([\d.]+[NS])\s+([\d.]+[EW])\s+(\d+)\s*KT\s+(\d+)\s*MPH\s*(\.\.\.(.*))?$') {
      $row.Pos = "$($Matches[1]) $($Matches[2])"; $row.Kt = $Matches[3]; $row.Mph = $Matches[4]; $row.Note = $Matches[6]
    } else { $row.Note = $rest.Trim('.', ' ') }
    $fc += $row
  }
}
if ($fc.Count -lt 3) { throw 'TCD: forecast table not parsed' }

# PWS: cumulative (5-day) probability = last value in the row.
$pwsStart = ''
if ($pws.Text -match 'OCCURRING BETWEEN\s+(\d\d)Z (\w{3})') { # e.g. "18Z THU" -> "1 PM CDT Thu (18Z)"
  $days = 'SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'; $h = [int]$Matches[1] - 5; $d = [array]::IndexOf($days, $Matches[2])
  if ($h -lt 0) { $h += 24; $d = ($d + 6) % 7 }
  $h12 = if ($h % 12 -eq 0) { 12 } else { $h % 12 }; $ap = if ($h -lt 12) { 'AM' } else { 'PM' }
  $pwsStart = "$h12 $ap CDT $((Get-Culture).TextInfo.ToTitleCase($days[$d].ToLower())) ($($Matches[1])Z)"
}
$pwsRows = [ordered]@{}
foreach ($l in $pws.Lines) {
  if ($l -match '^(.{14})\s*(34|50|64)\s+(.*)$') {
    $loc = $Matches[1].Trim(); $kt = $Matches[2]
    if ($PwsPlaces -notcontains $loc) { continue }
    $cps = [regex]::Matches($Matches[3], '\(\s*(X|\d+)\)'); if (-not $cps.Count) { continue }
    $v = $cps[$cps.Count - 1].Groups[1].Value
    if (-not $pwsRows.Contains($loc)) { $pwsRows[$loc] = @{} }
    $pwsRows[$loc][$kt] = $(if ($v -eq 'X') { '<1%' } else { "$v%" })
  }
}
$tcmNote = if ($tcm.Text -match '(ERRORS FOR TRACK HAVE AVERAGED[^\n]*\n[^\n]*)') { Sentence (($Matches[1] -replace '\s+', ' ').Trim()) } else { '' }

# NHC graphics for this advisory (hotlinked, public domain).
$gfx = @{}
try {
  $g = (Invoke-WebRequest -UseBasicParsing -Uri "https://www.nhc.noaa.gov/graphics_$($Bin.ToLower()).shtml" -UserAgent $Hdr['User-Agent'] -TimeoutSec 60).Content
  # The graphics page lists 60-px thumbnails (..._sm.png); the full-size image drops "_sm". Keep only ones that resolve.
  foreach ($name in '5day_cone_sm', 'peak_surge_sm') {
    $m = [regex]::Match($g, '"(/storm_graphics/[A-Z0-9]+/refresh/[^"]*' + [regex]::Escape($name) + '\.png)"')
    if (-not $m.Success) { continue }
    $full = 'https://www.nhc.noaa.gov' + ($m.Groups[1].Value -replace '_sm\+png', '+png' -replace '_sm\.png$', '.png')
    try { $h = Invoke-WebRequest -UseBasicParsing -Method Head -Uri $full -UserAgent $Hdr['User-Agent'] -TimeoutSec 60; if ($h.Headers['Content-Type'] -like 'image/*') { $gfx[$name] = $full } } catch { Write-Warning "graphic $full unavailable" }
  }
} catch { Write-Warning "NHC graphics page unavailable: $($_.Exception.Message)" }

# ---------- NWS Mobile ----------
$hls = Get-Product 'HLS' $Office $Storm
$hlsHead = @([regex]::Matches(($hls.Text -replace '\s*\n\s*', ' '), '\*\*(.+?)\*\*') | ForEach-Object { $_.Groups[1].Value.Trim() })
$hlsWW = Bullets (Between $hls.Lines '^\* CURRENT WATCHES AND WARNINGS' '^\* STORM INFORMATION')
$hlsInfo = Bullets (Between $hls.Lines '^\* STORM INFORMATION' '^SITUATION OVERVIEW')
$hlsOver = Paras (Between $hls.Lines '^SITUATION OVERVIEW' '^POTENTIAL IMPACTS')
$hlsImp = Between $hls.Lines '^POTENTIAL IMPACTS' '^PRECAUTIONARY'
$hlsNext = (Paras (Between $hls.Lines '^NEXT UPDATE' '^\$\$')) -join ' '
if (-not $hlsOver.Count) { throw 'HLS: no situation overview' }

$al = Get-Api "https://api.weather.gov/alerts/active?point=$Lat,$Lon"
$alerts = @($al.features | ForEach-Object { $_.properties } | Where-Object { $_.event -ne 'Tropical Cyclone Local Statement' })
$rank = @('Hurricane Warning', 'Tropical Storm Warning', 'Hurricane Watch', 'Tropical Storm Watch', 'Storm Surge Warning', 'Storm Surge Watch')
$zone = $alerts | Where-Object { $_.description -match '\* WIND' -and $_.description -match 'LOCATIONS AFFECTED' } | Sort-Object { $i = $rank.IndexOf($_.event); if ($i -lt 0) { 99 } else { $i } } | Select-Object -First 1
[IO.File]::WriteAllText((Join-Path $Raw 'alerts.txt'), (($alerts | ForEach-Object { "=== $($_.event) | sent $($_.sent) | ends $($_.ends) | $($_.areaDesc)`n$($_.description)`n" }) -join "`n"), (New-Object Text.UTF8Encoding $false))
$zoneSec = [ordered]@{}; $zoneLocs = @()
if ($zone) {
  $zl = ($zone.description -replace "`r", '') -split "`n"; $name = $null; $acc = @()
  foreach ($l in $zl + '* END') {
    if ($l -match '^\* (.+?)\s*$') { if ($name) { $zoneSec[$name] = Bullets $acc }; $name = $Matches[1].Trim(':'); $acc = @() } else { $acc += $l }
  }
  if ($zoneSec.Contains('LOCATIONS AFFECTED')) { $zoneLocs = $zoneSec['LOCATIONS AFFECTED'] }
}

# ---------- HTML ----------
$built = [DateTimeOffset]::UtcNow
$sb = New-Object Text.StringBuilder
function W([string]$s) { [void]$sb.AppendLine($s) }
function Img([string]$k, [string]$alt, [string]$cap) {
  if ($gfx[$k]) { W "<figure><a href=""https://www.nhc.noaa.gov/graphics_$($Bin.ToLower()).shtml""><img class=""nwsimg"" src=""$($gfx[$k])"" alt=""$(Esc $alt)"" loading=""lazy""></a><figcaption>$cap</figcaption></figure>" }
}
# NWS Mobile products lag NHC by up to a few hours; say so when one predates the current NHC advisory.
function Older([DateTimeOffset]$t, [string]$what) {
  if (($tcp.Issued - $t).TotalMinutes -gt 30) { W "<p class=""note warn small"">$what was issued before NHC's $(Esc (CDT $tcp.Issued)) advisory, so its storm details (position, wind) can be out of date. NWS Mobile usually updates within a few hours.</p>" }
}
function ZoneCard([string]$sec, [string]$title) {
  if (-not $zoneSec.Contains($sec)) { return }
  $items = $zoneSec[$sec]; $fcst = @(); $threat = ''; $trend = ''; $acts = @(); $impLvl = ''; $imps = @(); $state = 'f'
  foreach ($it in $items) {
    if ($it -match '^THREAT TO LIFE AND PROPERTY.*?:\s*(.*)$') { $threat = $Matches[1]; $state = 't'; continue }
    if ($it -match '^POTENTIAL IMPACTS:\s*(.*)$') { $impLvl = $Matches[1]; $state = 'i'; continue }
    if ($state -eq 'f') { $fcst += $it }
    elseif ($state -eq 't') { if ($it -match '^(PLAN|PREPARE|ACT):\s*(.*)$') { $acts += "<b>$(Esc (Sentence $Matches[1])):</b> $(Esc $Matches[2])" } elseif ($it -match 'threat has') { $trend = $it } else { $acts += (Esc $it) } }
    else { $imps += $it }
  }
  W "<article class=""hz""><h3>$title</h3>"
  W '<dl class="kv">'
  foreach ($f in $fcst) { if ($f -match '^([^:]{3,60}):\s*(.*)$') { $k = $Matches[1]; $v = $Matches[2]; if ($k -eq 'LATEST LOCAL FORECAST') { $k = 'Latest local forecast' }; if ($v -eq '') { continue }; W "<div><dt>$(Esc $k)</dt><dd>$(Esc $v)</dd></div>" } else { W "<div><dt>Latest local forecast</dt><dd>$(Esc $f)</dd></div>" } }
  if ($threat) { W "<div class=""threat""><dt>Threat, allowing for typical forecast error in track, size and intensity</dt><dd>$(Esc $threat)</dd></div>" }
  W '</dl>'
  if ($trend) { W "<p class=""small"">$(Esc $trend)</p>" }
  if ($acts.Count -or $imps.Count) {
    W "<details><summary>What NWS Mobile advises$(if ($impLvl) { " · potential impacts: $(Esc $impLvl)" })</summary>"
    if ($acts.Count) { W '<ul>'; foreach ($a in $acts) { W "<li>$a</li>" }; W '</ul>' }
    if ($imps.Count) { W "<p class=""small"">Potential impacts ($(Esc $impLvl)):</p><ul>"; foreach ($i in $imps) { W "<li>$(Esc $i)</li>" }; W '</ul>' }
    W '</details>'
  }
  W '</article>'
}

W @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Isaias, Latest from NWS</title>
<meta name="description" content="The latest National Weather Service information on Hurricane $stormName for the Mobile Bay and Fairhope area, gathered on one phone-friendly page. Unofficial; always check NWS directly.">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo:wdth,wght@62..125,500..800&family=IBM+Plex+Mono:wght@400;600&family=Source+Serif+4:opsz,wght@8..60,400;8..60,600&display=swap">
<link rel="stylesheet" href="assets/style.css">
<link rel="stylesheet" href="assets/latest.css">
</head>
<body>
<div class="page">

  <header class="mast">
    <a class="brand" href="./">AL092026 · ISAIAS</a>
    <nav aria-label="Site">
      <a href="latest.html" aria-current="page">Latest NWS</a>
      <a href="evacuations.html">Evacuations</a>
      <a href="./">Analysis</a>
      <a href="models.html">Model key</a>
      <a href="methods.html">Methods &amp; data</a>
    </nav>
  </header>

  <aside class="disclaimer" role="note">
    <p><b>Unofficial summary.</b> Everything below is copied from National Weather Service products, with the time each was issued. It can lag the NWS by an hour or more. For decisions, use <a href="https://www.hurricanes.gov">hurricanes.gov</a>, <a href="https://www.weather.gov/mob">NWS Mobile</a> and your local officials, and follow any evacuation order.</p>
  </aside>

  <div class="hero">
    <p class="stamp">Page built $(Esc (Stamp $built)) · NHC $(Esc $tcpTitle)</p>
    <h1>$(Esc $stormName): the latest</h1>
"@
if ($tcpNote) { W "    <p class=""note warn small"">NHC note on this advisory: $(Esc $tcpNote)</p>" }
foreach ($h in $headlines) { W "    <p class=""headline"">$(Esc $h)</p>" }
W '  </div>'

W "  <div class=""readout"" aria-label=""Storm now, from NHC $(Esc (Stamp $tcp.Issued))"">"
$wnd = $summary['MAXIMUM SUSTAINED WINDS'] -split '\.\.\.'
$prs = $summary['MINIMUM CENTRAL PRESSURE'] -split '\.\.\.'
$mv = $summary['PRESENT MOVEMENT']
if ($mv -match '^(\w+) OR (\d+) DEGREES AT (\d+) MPH\.\.\.(\d+) KM/H') { $mvV = "$($Matches[1]) at $($Matches[3]) mph"; $mvN = "toward $($Matches[2])°, $($Matches[4]) km/h" } else { $mvV = $mv; $mvN = '' }
W "    <div><span class=""k"">Max sustained wind</span><span class=""v"">$(Esc $wnd[0].ToLower())</span><span class=""n"">$(Esc ($wnd[1..9] -join ' ').ToLower()) · NHC $(Esc (CDT $tcp.Issued))</span></div>"
W "    <div><span class=""k"">Moving</span><span class=""v"">$(Esc $mvV)</span><span class=""n"">$(Esc $mvN)</span></div>"
W "    <div><span class=""k"">Central pressure</span><span class=""v"">$(Esc $prs[0].ToLower())</span><span class=""n"">$(Esc ($prs[1..9] -join ' ').ToLower())</span></div>"
W "    <div><span class=""k"">Center</span><span class=""v"">$(Esc $summary['LOCATION'])</span><span class=""n"">About $(Esc (($summary['ABOUT'] -split '; ')[-1] -replace '\.\.\.', ' / '))</span></div>"
W '  </div>'
W "  <p class=""small next"">$(Esc $nextAdv)</p>"

# Fairhope
W '  <section id="local">'
W "    <div class=""prose""><h2>$(Esc $Place) and Baldwin County</h2>"
if ($zone) {
  $zt = [DateTimeOffset]::Parse($zone.sent)
  W "<p class=""small"">From NWS Mobile's <b>$(Esc $zone.event)</b> for the <b>$(Esc $zone.areaDesc)</b> zone ($(Esc (($zoneLocs) -join ', '))), issued $(Esc (Stamp $zt)). This is the NWS forecast for the zone that includes Fairhope.</p>"
  Older $zt 'This zone forecast'
} else { W '<p class="small">NWS Mobile has no tropical zone forecast in effect for Fairhope right now.</p>' }
W '</div>'
W '    <div class="chips" aria-label="Active NWS alerts at Fairhope">'
foreach ($a in ($alerts | Sort-Object { $i = $rank.IndexOf($_.event); if ($i -lt 0) { 99 } else { $i } })) {
  $cls = if ($a.event -match 'Warning') { 'chip warn' } else { 'chip' }
  $end = if ($a.ends) { ' until ' + (CDT ([DateTimeOffset]::Parse($a.ends))) } else { '' }
  W "      <span class=""$cls""><b>$(Esc $a.event)</b>$(Esc $end)</span>"
}
if (-not $alerts.Count) { W '      <span class="chip">No active NWS alerts at Fairhope</span>' }
W '    </div>'
W '    <div class="hzgrid">'
ZoneCard 'WIND' 'Wind'
ZoneCard 'STORM SURGE' 'Storm surge'
ZoneCard 'FLOODING RAIN' 'Flooding rain'
ZoneCard 'TORNADO' 'Tornadoes'
W '    </div>'
foreach ($a in ($alerts | Where-Object { $_.event -match 'Flood' })) {
  $what = if ($a.description -match '(?s)\* WHEN\.\.\.(.+?)(\n\s*\n|\n\*)') { ($Matches[1] -replace '\s+', ' ').Trim() } else { '' }
  W "    <p class=""small""><b>$(Esc $a.event)</b> ($(Esc $a.senderName), issued $(Esc (Stamp ([DateTimeOffset]::Parse($a.sent))))): $(Esc $what)</p>"
}
W '  </section>'

# Forecast
W '  <section id="forecast">'
W "    <div class=""prose""><h2>NHC forecast</h2><p class=""small"">From $(Esc $tcdTitle.Trim()), issued $(Esc (Stamp $tcd.Issued)). Times converted from UTC to Central Daylight Time.</p></div>"
W '    <div class="scroll"><table class="data fc"><thead><tr><th>Valid (CDT)</th><th>Center</th><th>Max wind</th><th></th></tr></thead><tbody>'
foreach ($r in $fc) {
  $w = if ($r.Mph) { "<span class=""nowrap"">$($r.Mph) mph</span><span class=""sub"">$($r.Kt) kt</span>" } else { '' }
  $lab = if ($r.Tau -eq 'INIT') { 'now' } else { '+' + $r.Tau.TrimEnd('H') + ' h' }
  $lt = [TimeZoneInfo]::ConvertTime($r.Time, $Central); $ci = [Globalization.CultureInfo]::InvariantCulture
  $when = if ($lt.Minute -eq 0) { $lt.ToString('ddd h tt', $ci) } else { $lt.ToString('ddd h:mm tt', $ci) }
  W "      <tr><td><b class=""nowrap"">$(Esc $when)</b><span class=""sub"">$lab · $(Esc (Utc $r.Time))</span></td><td class=""mono"">$(Esc $r.Pos)</td><td>$w</td><td>$(Esc (Sentence $r.Note))</td></tr>"
}
W '    </tbody></table></div>'
Img '5day_cone_sm' 'NHC forecast cone' "NHC cone graphic for this advisory. The cone shows where the <i>center</i> is likely to go; NHC says the center stays inside it about 60–70% of the time, and hazards extend well outside it (<a href=""https://www.nhc.noaa.gov/aboutcone.shtml"">about the cone</a>)."
if ($outlook.Count) { W '<div class="prose">'; foreach ($p in $outlook) { W "<p>$(Esc $p)</p>" }; W "<p class=""small"">NHC public advisory, $(Esc (Stamp $tcp.Issued)).</p></div>" }
W '  </section>'

# Wind probabilities
if ($pwsRows.Count) {
  W '  <section id="windprob">'
  W "    <div class=""prose""><h2>Chance of damaging winds</h2><p>NHC's chance that each place gets <b>sustained</b> winds of at least 39, 58 or 74 mph at any time in the next 5 days (from $(Esc $pwsStart)). Gusts can be higher. Mobile is the closest listed place to Fairhope; NHC does not list Fairhope itself.</p></div>"
  W '    <div class="scroll"><table class="data"><thead><tr><th>Place</th><th>39+ mph<span class="sub">trop. storm</span></th><th>58+ mph</th><th>74+ mph<span class="sub">hurricane</span></th></tr></thead><tbody>'
  foreach ($loc in $PwsPlaces) {
    if (-not $pwsRows.Contains($loc)) { continue }
    # A missing row means NHC left it out: 34/50 kt rows below 3% (5-day), 64 kt rows below 1%.
    $r = $pwsRows[$loc]; $c = { param($k) if ($r.ContainsKey($k)) { $r[$k] } elseif ($k -eq '64') { '<1%' } else { '<3%' } }
    $pm = [regex]::Match($loc, '^(.*?)( AL| FL| MS| LA)?$')
    $name = (Get-Culture).TextInfo.ToTitleCase($pm.Groups[1].Value.ToLower()) -replace 'Fld', 'Field' -replace 'Exec Ap', 'airport'
    if ($pm.Groups[2].Success) { $name += ',' + $pm.Groups[2].Value }
    W "      <tr><td>$(Esc $name)</td><td>$(Esc (& $c '34'))</td><td>$(Esc (& $c '50'))</td><td>$(Esc (& $c '64'))</td></tr>"
  }
  W '    </tbody></table></div>'
  W "    <p class=""small"">NHC wind speed probabilities, $(Esc (Stamp $pws.Issued)). &lt;1% means NHC printed X (less than 1%). Where NHC leaves a row out, its rules mean the 5-day chance is below 3% (39 and 58 mph) or below 1% (74 mph).</p>"
  W '  </section>'
}

# Hazards (NHC)
W '  <section id="hazards">'
W "    <div class=""prose""><h2>Hazards: what NHC expects</h2><p class=""small"">From the NHC public advisory, $(Esc (Stamp $tcp.Issued)).</p></div>"
W '    <div class="hzgrid">'
$names = @{ 'STORM SURGE' = 'Storm surge'; 'WIND' = 'Wind'; 'RAINFALL' = 'Rain'; 'TORNADOES' = 'Tornadoes'; 'SURF' = 'Surf and rip currents' }
foreach ($k in $hazards.Keys) {
  $title = if ($names[$k]) { $names[$k] } else { Sentence $k }
  W "<article class=""hz""><h3>$(Esc $title)</h3>"
  foreach ($p in $hazards[$k]) {
    if ($p.List) { W '<ul class="surge">'; foreach ($i in $p.List) { $q = $i -split ': ', 2; W "<li><span>$(Esc $q[0])</span><b>$(Esc $q[1])</b></li>" }; W '</ul>' }
    else { W "<p>$(Esc $p.Text)</p>" }
  }
  W '</article>'
}
W '    </div>'
Img 'peak_surge_sm' 'NHC peak storm surge graphic' 'NHC peak storm surge graphic for this advisory.'
W '  </section>'

# Watches & warnings
W '  <section id="warnings">'
W "    <div class=""prose""><h2>Watches and warnings</h2><p class=""small"">NHC coastal watches and warnings, $(Esc (Stamp $tcp.Issued)). Changes with this advisory: $(Esc ($changes -join ' '))</p>"
foreach ($g in $groups) { W "<h3>$(Esc $g.Name)</h3><ul>"; foreach ($a in $g.Areas) { W "<li>$(Esc $a)</li>" }; W '</ul>' }
if ($hlsWW.Count) { W "<h3>NWS Mobile counties and zones</h3><ul>"; foreach ($b in $hlsWW) { W "<li>$(Esc $b)</li>" }; W "</ul><p class=""small"">NWS Mobile local statement, $(Esc (Stamp $hls.Issued)).</p>" }
W '</div>'
W '  </section>'

# Key messages + reasoning
W '  <section id="messages">'
W "    <div class=""prose""><h2>NHC key messages</h2><ol>"
foreach ($m in $keyMsgs) { W "<li>$(Esc $m)</li>" }
W "</ol><p class=""small"">$(Esc $tcdTitle.Trim()), $(Esc (Stamp $tcd.Issued)).</p>"
W '<details><summary>The forecaster''s reasoning (full discussion)</summary>'
foreach ($p in $reason) { W "<p>$(Esc $p)</p>" }
if ($tcmNote) { W "<p class=""small"">From the forecast advisory: $(Esc $tcmNote)</p>" }
W '</details></div>'
W '  </section>'

# HLS
W '  <section id="mobile">'
W "    <div class=""prose""><h2>NWS Mobile local statement</h2><p class=""small"">Issued $(Esc (Stamp $hls.Issued)). $(Esc $hlsNext)</p>"
Older $hls.Issued 'This statement'
foreach ($h in $hlsHead) { W "<p class=""headline"">$(Esc $h)</p>" }
foreach ($p in $hlsOver) { W "<p>$(Esc $p)</p>" }
if ($hlsInfo.Count) { W "<p class=""small"">Storm information: $(Esc ($hlsInfo -join ' · '))</p>" }
W '<details><summary>Potential impacts for the region (full text)</summary><pre class="nws">'
W (Esc (($hlsImp -join "`n").Trim()))
W '</pre></details></div>'
W '  </section>'

# Sources
W '  <section id="sources">'
W '    <div class="prose"><h2>Sources</h2><p>All from the National Weather Service, through <a href="https://www.weather.gov/documentation/services-web-api">api.weather.gov</a> and <a href="https://www.nhc.noaa.gov">nhc.noaa.gov</a>. The text is copied as issued; this page only changes capitals, line breaks and UTC times into Central time.</p><ul>'
foreach ($s in @(@('NHC public advisory', $tcp, "https://www.nhc.noaa.gov/text/MIATCP$Bin.shtml"), @('NHC forecast discussion', $tcd, "https://www.nhc.noaa.gov/text/MIATCD$Bin.shtml"), @('NHC forecast advisory', $tcm, "https://www.nhc.noaa.gov/text/MIATCM$Bin.shtml"), @('NHC wind speed probabilities', $pws, "https://www.nhc.noaa.gov/text/MIAPWS$Bin.shtml"), @('NWS Mobile local statement', $hls, 'https://www.weather.gov/mob/'))) {
  W "<li><a href=""$($s[2])"">$($s[0])</a> <span class=""mono small"">$(Esc $s[1].Wmo)</span>, issued $(Esc (Stamp $s[1].Issued))</li>"
}
W "<li><a href=""https://api.weather.gov/alerts/active?point=$Lat,$Lon"">NWS alerts in effect at $Place</a>, read $(Esc (Stamp $built))</li>"
W "<li><a href=""https://forecast.weather.gov/MapClick.php?lat=$Lat&amp;lon=$Lon"">NWS point forecast for $Place</a> (not copied here; check it directly)</li>"
W '</ul></div>'
W '  </section>'

W @"
  <footer>
    <p><b>Unofficial summary of NWS information, not a forecast.</b> Always check the <a href="https://www.nhc.noaa.gov">National Hurricane Center</a>, <a href="https://www.weather.gov/mob">NWS Mobile</a> and local officials for the latest, and follow evacuation orders.</p>
  </footer>
</div>
</body>
</html>
"@

[IO.File]::WriteAllText((Join-Path $Root 'latest.html'), $sb.ToString(), (New-Object Text.UTF8Encoding $false))

# Key values for the Mobile Bay / Fairhope area, compared with the last build so the update job can judge
# whether the local forecast changed materially. Printed as "field: old -> new".
function ZoneVal([string]$sec, [string]$pat) { if ($zoneSec.Contains($sec)) { ($zoneSec[$sec] | Where-Object { $_ -match $pat } | Select-Object -First 1) } else { '' } }
$surgeMB = ''; if ($hazards.Contains('STORM SURGE')) { foreach ($p in $hazards['STORM SURGE']) { if ($p.List) { $surgeMB = ($p.List | Where-Object { $_ -match '^(Lower |Upper )?Mobile Bay' }) -join '; ' } } }
$state = [ordered]@{
  nhc_advisory = $tcpTitle; nhc_max_wind = $summary['MAXIMUM SUSTAINED WINDS']
  nhc_track = (($fc | Where-Object { $_.Pos } | ForEach-Object { "$($_.Tau) $($_.Pos) $($_.Kt)kt" }) -join '; ')
  hurricane_warning = (($groups | Where-Object { $_.Name -eq 'Hurricane Warning' } | ForEach-Object { $_.Areas }) -join '; ')
  surge_mobile_bay = $surgeMB
  pws_mobile = $(if ($pwsRows.Contains('MOBILE AL')) { "34kt $($pwsRows['MOBILE AL']['34']) 50kt $($pwsRows['MOBILE AL']['50']) 64kt $($pwsRows['MOBILE AL']['64'])" } else { 'not listed' })
  fairhope_alerts = (($alerts | ForEach-Object { $_.event } | Sort-Object -Unique) -join ', ')
  zone_issued = $(if ($zone) { $zone.sent } else { '' })
  zone_wind_latest = ZoneVal 'WIND' '^LATEST LOCAL'; zone_wind_peak = ZoneVal 'WIND' '^Peak Wind'; zone_wind_threat = ZoneVal 'WIND' '^THREAT'
  zone_surge_peak = ZoneVal 'STORM SURGE' '^Peak Storm Surge'; zone_surge_threat = ZoneVal 'STORM SURGE' '^THREAT'
  zone_rain_peak = ZoneVal 'FLOODING RAIN' '^Peak Rainfall'; zone_tornado_threat = ZoneVal 'TORNADO' '^THREAT'
}
$stFile = Join-Path $Root 'data\latest_state.json'
if (Test-Path $stFile) {
  $old = Get-Content $stFile -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($k in $state.Keys) { $o = "$($old.$k)"; if ($o -ne "$($state[$k])") { "CHANGED $k`n   was: $o`n   now: $($state[$k])" } }
}
[IO.File]::WriteAllText($stFile, ($state | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
"latest.html built $(Stamp $built): TCP $(Stamp $tcp.Issued), TCD $(Stamp $tcd.Issued), PWS $(Stamp $pws.Issued), HLS $(Stamp $hls.Issued), alerts $($alerts.Count), zone $($zone.event), graphics $($gfx.Count)"
