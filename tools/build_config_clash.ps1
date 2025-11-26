param(
    [string]$SubUrl = "https://troynichek-live.ru/subvlftun/f761a39dd58742ba91f20462398edc25",
    [string]$OutputPath = "config.yaml"
)

Write-Host "Downloading subscription from $SubUrl ..."
try {
    $raw = (Invoke-WebRequest -UseBasicParsing -Uri $SubUrl -TimeoutSec 10).Content
} catch {
    Write-Error "Failed to download subscription: $($_.Exception.Message)"
    exit 1
}

$raw = $raw.Trim()
if (-not $raw) {
    Write-Error "Subscription is empty"
    exit 1
}

# Берём первую строку
$line = $raw.Split("`n")[0].Trim()

# Пробуем base64 -> vless://
$vless = $null
try {
    $bytes   = [Convert]::FromBase64String($line)
    $decoded = [Text.Encoding]::UTF8.GetString($bytes).Trim()
    if ($decoded -like "vless://*") { $vless = $decoded }
} catch { }

# Или прямой vless://
if (-not $vless) {
    if ($line -like "vless://*") { $vless = $line }
    else {
        Write-Error "Not a vless URL in any form"
        exit 1
    }
}

Write-Host "VLESS:"
Write-Host $vless

# ===== Parse vless URL =====
# vless://UUID@SERVER:PORT?key=value&...

$noScheme = $vless.Substring(8)              # skip "vless://"
$parts    = $noScheme.Split("?",2)
if ($parts.Count -lt 2) {
    Write-Error "Invalid VLESS URL: no query part"
    exit 1
}
$left     = $parts[0]
$query    = $parts[1]

$uuidAndRest = $left.Split("@",2)
if ($uuidAndRest.Count -lt 2) {
    Write-Error "Invalid VLESS URL: no @ part"
    exit 1
}
$uuid        = $uuidAndRest[0]
$serverPort  = $uuidAndRest[1]

$spParts = $serverPort.Split(":",2)
if ($spParts.Count -lt 2) {
    Write-Error "Invalid VLESS URL: no :port part"
    exit 1
}
$serverName = $spParts[0]
$portStr    = $spParts[1]
$port       = [int]$portStr

# Query params -> hashtable
$kv = @{}
foreach ($pair in $query.Split("&")) {
    if (-not $pair) { continue }
    $p = $pair.Split("=",2)
    if ($p.Count -eq 2) { $kv[$p[0]] = $p[1] }
}

$security = $kv["security"]
$flow     = $kv["flow"]
$sni      = $kv["sni"]
$fp       = $kv["fp"]
$pbk      = $kv["pbk"]
$sid      = $kv["sid"]

if (-not $sni) { $sni = $serverName }
if (-not $fp)  { $fp  = "random" }

# ===== Build Clash Meta YAML =====
# TUN: включён, всё через VLF, локалки в обход (можно потом усложнить правилами)

$yaml = @"
port: 7890
socks-port: 7891
mixed-port: 0
allow-lan: false
mode: rule
log-level: info
ipv6: false

dns:
  enabled: true
  ipv6: false
  listen: 0.0.0.0:1053
  default-nameserver:
    - 1.1.1.1
    - 8.8.8.8
  nameserver:
    - https://1.1.1.1/dns-query
    - https://dns.google/dns-query

tun:
  enable: true
  stack: system
  auto-route: true
  auto-detect-interface: true

proxies:
  - name: "VLF-FIN"
    type: vless
    server: "$serverName"
    port: $port
    uuid: "$uuid"
    flow: "$flow"
    udp: true
    tls: true
    servername: "$sni"
    reality-opts:
      public-key: "$pbk"
      short-id: "$sid"
    client-fingerprint: "$fp"

proxy-groups:
  - name: "VLF"
    type: select
    proxies:
      - "VLF-FIN"

rules:
  - GEOIP,private,DIRECT
  - MATCH,VLF
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($OutputPath, $yaml, $utf8NoBom)

Write-Host "config.yaml generated"
