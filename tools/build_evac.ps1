# Builds evacuations.html from data/evacuations.json (hand-curated from official government pages; see the
# "note" in that file) plus two automatic NWS feeds: civil-authority alerts relayed through api.weather.gov
# for the counties listed, and the EVACUATIONS paragraph of NWS Mobile's local statement.
#   powershell -ExecutionPolicy Bypass -File tools/build_evac.ps1 -Root <repo path>
param([string]$Root = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Hdr = @{ 'User-Agent' = 'static_hurricane_info_site (github.com/LukeMcCulloch/static_hurricane_info_site)'; 'Accept' = 'application/geo+json' }
$Central = [TimeZoneInfo]::FindSystemTimeZoneById('Central Standard Time')
# SAME (FIPS) codes for the counties on the page: Baldwin, Mobile AL; Escambia, Santa Rosa, Okaloosa FL.
$Same = @('001003', '001097', '012033', '012113', '012091')
$Civil = @('Evacuation Immediate', 'Civil Emergency Message', 'Local Area Emergency', 'Shelter In Place Warning', 'Civil Danger Warning', 'Law Enforcement Warning', 'Hazardous Materials Warning')

function Get-Api([string]$url) {
  for ($i = 1; $i -le 5; $i++) { try { return Invoke-RestMethod -Uri $url -Headers $Hdr -TimeoutSec 60 } catch { if ($i -eq 5) { throw "GET $url failed: $($_.Exception.Message)" }; Start-Sleep 4 } }
}
function Esc([string]$s) { [Net.WebUtility]::HtmlEncode($s) }
function Stamp([DateTimeOffset]$t) { [TimeZoneInfo]::ConvertTime($t, $Central).ToString('ddd d MMM, h:mm tt', [Globalization.CultureInfo]::InvariantCulture) + ' CDT (' + $t.UtcDateTime.ToString('HH:mm') + 'Z)' }
function Link([string]$s) { # Escape, then turn bare https URLs into links.
  [regex]::Replace((Esc $s), 'https?://[^\s<)"]+[^\s<)".,;]', { param($m) "<a href=""$($m.Value)"">$($m.Value -replace '^https?://', '')</a>" })
}

$ev = Get-Content (Join-Path $Root 'data\evacuations.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$read = [DateTimeOffset]::Parse($ev.read)

# NWS-relayed civil alerts for these counties.
$al = Get-Api 'https://api.weather.gov/alerts/active?area=AL,FL'
$civil = @($al.features | ForEach-Object { $_.properties } | Where-Object { $Civil -contains $_.event -and (@($_.geocode.SAME | Where-Object { $Same -contains $_ }).Count) })
# NWS Mobile local statement: the EVACUATIONS paragraph.
$list = Get-Api 'https://api.weather.gov/products/types/HLS/locations/MOB'
$hls = Get-Api $list.'@graph'[0].'@id'
$hlsT = [DateTimeOffset]::Parse($hls.issuanceTime)
$hlsEvac = ''
if (($hls.productText -replace "`r", '') -match '(?s)\* EVACUATIONS:\s*\n(.+?)\n\s*\n') { $hlsEvac = ($Matches[1] -replace '\s+', ' ').Trim() }
$built = [DateTimeOffset]::UtcNow

$sb = New-Object Text.StringBuilder
function W([string]$s) { [void]$sb.AppendLine($s) }
$typeLabel = @{ mandatory = 'Mandatory evacuation'; voluntary = 'Voluntary evacuation'; order = 'Evacuation order'; request = 'Evacuation request' }

W @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Isaias Evacuation Notices</title>
<meta name="description" content="Official evacuation orders for Hurricane Isaias in Baldwin and Mobile counties, Alabama, and the western Florida Panhandle, with sources and the time each was read. Unofficial; always check with local officials.">
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
      <a href="latest.html">Latest NWS</a>
      <a href="evacuations.html" aria-current="page">Evacuations</a>
      <a href="./">Analysis</a>
      <a href="models.html">Model key</a>
      <a href="methods.html">Methods &amp; data</a>
    </nav>
  </header>

  <aside class="disclaimer" role="note">
    <p><b>Unofficial summary.</b> Evacuation orders come from state and local officials and can change at any time. This page can lag them by an hour or more. Use it to find the right official source, then confirm there or by phone. If officials tell you to leave, follow their instructions.</p>
  </aside>

  <div class="hero">
    <p class="stamp">Official sources read $(Esc (Stamp $read)) · page built $(Esc (Stamp $built))</p>
    <h1>Isaias: evacuation notices</h1>
    <p class="dek">What each county and the State of Alabama has ordered, in their words, with links to the original notices. Covers the coastal counties served by NWS Mobile, starting with Fairhope's.</p>
  </div>
"@

# Summary table.
W '  <section id="summary"><div class="prose"><h2>At a glance</h2></div>'
W '  <div class="scroll"><table class="data fc"><thead><tr><th>County</th><th>Orders in effect</th></tr></thead><tbody>'
foreach ($j in $ev.jurisdictions) {
  $cells = ($j.orders | ForEach-Object { "<span class=""chip$(if (@('mandatory', 'order') -contains $_.type) { ' warn' })""><b>$(Esc $typeLabel[$_.type])</b></span> <span class=""small"">$(Esc $_.who): $(Esc $_.where)</span>" }) -join '<br>'
  W "    <tr><td><a href=""#$($j.id)""><b>$(Esc $j.name)</b></a></td><td>$cells</td></tr>"
}
W '  </tbody></table></div></section>'

foreach ($j in $ev.jurisdictions) {
  W "  <section id=""$($j.id)""><div class=""prose""><h2>$(Esc $j.name)</h2><p class=""small"">Includes $(Esc $j.includes). Source agency: $(Esc $j.agency).</p></div>"
  W '  <div class="hzgrid">'
  foreach ($o in $j.orders) {
    W "<article class=""hz""><h3><span class=""chip$(if (@('mandatory', 'order') -contains $o.type) { ' warn' })""><b>$(Esc $typeLabel[$o.type])</b></span></h3><dl class=""kv"">"
    W "<div><dt>Who</dt><dd>$(Esc $o.who)</dd></div><div><dt>Where</dt><dd>$(Esc $o.where)</dd></div><div><dt>Effective</dt><dd>$(Esc $o.effective)</dd></div><div><dt>Issued by</dt><dd>$(Esc $o.by)</dd></div></dl>"
    if ($o.quote) { W "<blockquote class=""q"">&ldquo;$(Esc $o.quote)&rdquo;</blockquote>" }
    W "<p class=""small"">Source: <a href=""$(Esc $o.source)"">$(Esc $o.source_label)</a></p></article>"
  }
  W '  </div><div class="prose">'
  if ($j.notes) { W '<ul class="small">'; foreach ($n in $j.notes) { W "<li>$(Link $n)</li>" }; W '</ul>' }
  if ($j.shelters) { W '<h3>Shelters and transport</h3><ul>'; foreach ($s in $j.shelters) { W "<li>$(Link $s)</li>" }; W '</ul>' }
  $tel = $j.phone -replace '[^\d]', ''
  W "<p class=""chips""><a class=""chip"" href=""tel:+1$tel""><b>Call</b> $(Esc $j.phone_label): $(Esc $j.phone)</a> <a class=""chip"" href=""$(Esc $j.zones_url)""><b>Evacuation zones</b> and county updates</a></p>"
  W '  </div></section>'
}

# Proclamation.
$p = $ev.proclamation
W '  <section id="proclamation"><div class="prose">'
W "<h2>The Alabama order, in full</h2><p class=""small"">$(Esc $p.title). The operative text, as signed:</p>"
foreach ($t in $p.text) { W "<blockquote class=""q"">$(Esc $t)</blockquote>" }
W "<p class=""small""><a href=""$(Esc $p.source)"">Signed proclamation (PDF)</a> · <a href=""$(Esc $p.release)"">Governor's press release</a>. The press release names only Dauphin Island in Mobile County; the proclamation covers all of Zone 1.</p>"
W '  </div></section>'

# NWS.
W '  <section id="nws"><div class="prose"><h2>From the National Weather Service</h2>'
if ($civil.Count) {
  foreach ($c in $civil) { W "<article class=""hz""><h3>$(Esc $c.event)</h3><p class=""small"">$(Esc $c.senderName), sent $(Esc (Stamp ([DateTimeOffset]::Parse($c.sent)))) · $(Esc $c.areaDesc)</p><pre class=""nws"">$(Esc (($c.description + "`n`n" + $c.instruction).Trim()))</pre></article>" }
} else {
  W "<p>No evacuation or civil-emergency messages from officials were being relayed through NWS alerts for these counties when this page was built, $(Esc (Stamp $built)). Officials can issue orders without them, so check the county sources above.</p>"
}
if ($hlsEvac) { W "<p><b>NWS Mobile local statement</b> ($(Esc (Stamp $hlsT))): &ldquo;$(Esc $hlsEvac)&rdquo;</p>" }
W '<p class="small">Forecasts, watches and warnings for Fairhope are on the <a href="latest.html">Latest NWS</a> page.</p>'
W '  </div></section>'

W @"
  <footer>
    <p><b>Unofficial summary of official notices.</b> For decisions, contact your county emergency management agency, follow instructions from local officials, and check <a href="https://www.weather.gov/mob">NWS Mobile</a> and the <a href="https://www.nhc.noaa.gov">National Hurricane Center</a>.</p>
  </footer>
</div>
</body>
</html>
"@

[IO.File]::WriteAllText((Join-Path $Root 'evacuations.html'), $sb.ToString(), (New-Object Text.UTF8Encoding $false))
"evacuations.html built $(Stamp $built): sources read $(Stamp $read), $($ev.jurisdictions.Count) counties, NWS civil alerts $($civil.Count), HLS $(Stamp $hlsT)"
