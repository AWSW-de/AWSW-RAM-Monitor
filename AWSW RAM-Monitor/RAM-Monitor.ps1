
# RAM Monitor - Final Version

# === Konfiguration ===
$prozessNamen = @("powershell", "explorer", "notepad", "firefox")
$prozessFarben = @{
    "powershell" = "#FF00FF"
    "explorer" = "#0000FF"
    "notepad" = "#00FF00"
    "firefox" = "#00FFFF"
}
# Limits für Anzeig der Warnung in der Legende
$prozessWarnschwellen = @{
    "powershell" = 1000
    "explorer" = 500
    "notepad" = 100
    "firefox" = 3500
}
$intervallSekunden = 15
$maxDateiGroesseMB = 10

# === Dateipfade ===
$scriptPfad = Split-Path -Parent $MyInvocation.MyCommand.Definition
$dateinameCSV = Join-Path $scriptPfad "ram_usage.csv"
$dateinameHTML = Join-Path $scriptPfad "ram_usage.html"
$archivOrdner = Join-Path $scriptPfad "Archiv"

# === Initialisierung ===
if (Test-Path $dateinameCSV) { Remove-Item $dateinameCSV }
"Timestamp,Process,MemoryMB" | Out-File -FilePath $dateinameCSV -Encoding utf8

# === HTML-Erstellungsfunktion ===
function Erstelle-HTML {
    $data = Import-Csv -Path $dateinameCSV
    if (-not $data) { return }

    $labels = $data | Select-Object -ExpandProperty Timestamp -Unique
    $labelsJS = ($labels | ForEach-Object { "`"$_`"" }) -join ", "

    $datasetsJS = @()
    $legendenJS = @()
    $tabelleJS = @()

    foreach ($prozess in $prozessNamen) {
        $farbe = $prozessFarben[$prozess]
        if (-not $farbe) { $farbe = "#{0:X6}" -f (Get-Random -Minimum 0 -Maximum 0xFFFFFF) } 

        $werte = @()
        foreach ($label in $labels) {
            $eintrag = $data | Where-Object { $_.Timestamp -eq $label -and $_.Process -eq $prozess }
            if ($eintrag) {
                $gesamtRam = ($eintrag | Measure-Object -Property MemoryMB -Sum).Sum
                $werte += [math]::Round($gesamtRam, 2)
            } else {
                $werte += "null"
            }
        }
        $datenString = ($werte -join ", ")

        $letzterWert = ($werte | Where-Object { $_ -ne "null" } | Select-Object -Last 1)
        $warnung = ($prozessWarnschwellen[$prozess] -and $letzterWert -gt $prozessWarnschwellen[$prozess])

        if ($warnung) {
            $datasetsJS += "{label: '$prozess', data: [$datenString], borderColor: '#FF0000', borderWidth: 4, fill: false, hidden: false}"
        } else {
            $datasetsJS += "{label: '$prozess', data: [$datenString], borderColor: '$farbe', borderWidth: 2, fill: false, hidden: false}"
        }

        $status = if ($warnung) { "Warnung > " + $prozessWarnschwellen[$prozess] + "MB" } else { "OK < " + $prozessWarnschwellen[$prozess] + "MB"}
        $statusFarbe = if ($warnung) { "red" } else { "green" }

        $legendenJS += "<div class='legend-item' onclick='toggleDataset(`"$prozess`")'><div class='color-box' style='background-color: $farbe;'></div><span title='Aktueller Verbrauch: $letzterWert MB'>$prozess</span></div>`n"
        $tabelleJS += "<tr><td>$prozess</td><td>$letzterWert</td><td style='color:$statusFarbe;'>$status</td></tr>`n"
    }

    $datasetsJSString = $datasetsJS -join ","

    $html = @"
<!DOCTYPE html>
<html><head>
<title>RAM Monitor</title>
<script src="./chart.js"></script>
<style>
body { font-family: Arial; }
.legend-container { display: flex; justify-content: space-between; flex-wrap: wrap; margin-top: 20px; }
.legend { display: flex; flex-wrap: wrap; font-size: 14px; }
.legend-item { margin-right: 15px; display: flex; align-items: center; cursor: pointer; padding: 3px 5px; margin-bottom: 5px; }
.legend-item:hover { background-color: #f0f0f0; border-radius: 5px; }
.color-box { width: 12px; height: 12px; margin-right: 5px; display: inline-block; }
.buttons { display: flex; flex-wrap: wrap; gap: 8px; }
.refresh-button { padding: 5px 10px; font-size: 12px; }
#ramChart { width: 100%; height: 65vh; max-height: 65vh; }
.live-table { margin-top: 30px; }
.live-table table { width: 60%; border-collapse: collapse; }
.live-table th, .live-table td { padding: 8px; text-align: center; border: 1px solid #ccc; font-size: 14px; }
</style>
</head><body>
<h2>RAM-Auslastung der Prozesse:</h2>
<div class='legend-container'>
<div class='legend' id='customLegend'>
$legendenJS
</div>
<div class='buttons'>
<button class='refresh-button' onclick='location.reload();'>Seite aktualisieren</button>
<button class='refresh-button' onclick='showAll();'>Alle Linien anzeigen</button>
<button class='refresh-button' onclick='hideAll();'>Alle Linien verstecken</button>
</div>
</div>
<canvas id='ramChart'></canvas>
<div class='live-table'>
<h3>Aktuelle RAM-Auslastung</h3>
<table>
<thead><tr><th>Prozess</th><th>RAM (MB)</th><th>Status</th></tr></thead>
<tbody>
$tabelleJS
</tbody>
</table>
</div>
<script>
const ctx = document.getElementById('ramChart').getContext('2d');
const ramChart = new Chart(ctx, {
type: 'line',
data: { labels: [$labelsJS], datasets: [$datasetsJSString] },
options: {
responsive: true,
animation: { duration: 1000 },
plugins: { legend: { display: false } }
}
});
function toggleDataset(label) { const dataset = ramChart.data.datasets.find(d => d.label === label); dataset.hidden = !dataset.hidden; ramChart.update(); }
function showAll() { ramChart.data.datasets.forEach(d => d.hidden = false); ramChart.update(); }
function hideAll() { ramChart.data.datasets.forEach(d => d.hidden = true); ramChart.update(); }
setInterval(() => { location.reload(); }, 30000);
</script>
</body></html>
"@

    $html | Out-File -FilePath $dateinameHTML -Encoding utf8
}
# <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>

Write-Host "RAM Monitor gestartet. Öffne 'ram_usage.html' im Browser."

# Browser pr fen und ggf.  ffnen
$ramUsageOffen = Get-Process | Where-Object { $_.MainWindowTitle -like "*ram_usage.html*" }
if (-not $ramUsageOffen) {
    Start-Process $dateinameHTML
}


# === Haupt berwachungsschleife ===
try {
    while ($true) {
        if (Test-Path $archivOrdner) {
            Get-ChildItem -Path $archivOrdner -Filter "ram_usage_*.csv" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | Remove-Item -Force
        }
        if (Test-Path $dateinameCSV) {
            $csvGroesseMB = (Get-Item $dateinameCSV).Length / 1MB
            if ($csvGroesseMB -gt $maxDateiGroesseMB) {
                if (-not (Test-Path $archivOrdner)) { New-Item -ItemType Directory -Path $archivOrdner | Out-Null }
                $zeitstempel = Get-Date -Format "yyyyMMdd_HHmmss"
                $archivDateiname = Join-Path $archivOrdner "ram_usage_$zeitstempel.csv"
                Move-Item -Path $dateinameCSV -Destination $archivDateiname
                "Timestamp,Process,MemoryMB" | Out-File -FilePath $dateinameCSV -Encoding utf8
            }
        }
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        foreach ($prozess in $prozessNamen) {
            $prozesse = Get-Process -Name $prozess -ErrorAction SilentlyContinue
            if ($prozesse) {
                $ramMB = ($prozesse | Measure-Object -Property WorkingSet64 -Sum).Sum
                $ramMB = [math]::Round($ramMB / 1MB, 2)
            } else {
                $ramMB = 0
            }
            "$timestamp,$prozess,$ramMB" | Out-File -FilePath $dateinameCSV -Append -Encoding utf8
        }
        Erstelle-HTML
        Start-Sleep -Seconds $intervallSekunden
    }
}
catch {
    Write-Host "RAM Monitor gestoppt."
}
