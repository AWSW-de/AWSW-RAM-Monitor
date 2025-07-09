# RAM-Monitor.ps1 by AWSW - https://github.com/AWSW-de/AWSW-RAM-Monitor


#################################################################################
# Set your configuration here only:
#################################################################################
# Process configuration:
$prozessList = @(
    @{ Name = "firefox"; Farbe = "#FFCC00"; Schwellwert = 1000 },
    @{ Name = "notepad";  Farbe = "#00FF00"; Schwellwert = 1500 },
    @{ Name = "explorer";  Farbe = "#0000FF"; Schwellwert = 1000 }
    @{ Name = "thunderbird";  Farbe = "#00FFFF"; Schwellwert = 1000 }
)

# Delete old values on startup:
$delteOldValues = 1 # 1 = delete previous used .CSV and .HTML file on start / 0 = delete previous used .CSV and .HTML file on start 

# Interval in seconds:
$intervallSek = 10  # to collect the process data
$autoReloadSek = 10 # to update the HTML dashboard
#################################################################################
# Do not perform changes from here on!
#################################################################################

# Script version:
$ScriptVersion = "V2.1.0"

Write-Host "RAM-Monitor $ScriptVersion started"

# Script folder:
$scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Definition
# Write-Host "Skript folder: $scriptFolder"

# Files to collect and shot the prozess data:
$csvFile = Join-Path $scriptFolder "ram_log.csv"
$htmlFile = Join-Path $scriptFolder "ram_dashboard.html"
# Write-Host "ram_log.csv path: $csvFile"
# Write-Host "ram_dashboard.html path: $htmlFile"

# Delete old values on start:
If ($delteOldValues -eq 1) {
    Remove-Item -Path $csvFile -ErrorAction SilentlyContinue -Force
    Remove-Item -Path $htmlFile -ErrorAction SilentlyContinue -Force
    Write-Host " "
    # Write-Host "Previous used .CSV and .HTML file deleted..."
    # Write-Host " "
}

# Output information on startup:
# Write-Host " "
# Write-Host "Interval for data collection: $intervallSek seconds"
# Write-Host "Interval for refreshing the HTML page: $autoReloadSek seconds"
Write-Host "Determine new processes with 'Get-Process -name ProcessName*'"
Write-Host "and enter them in the format shown above in RAM-Monitor.ps1."
Write-Host " "
Write-Host "Starting process data collection in 5 seconds..."
Start-Sleep -Seconds 1
Write-Host "Starting process data collection in 4 seconds..."
Start-Sleep -Seconds 1
Write-Host "Starting process data collection in 3 seconds..."
Start-Sleep -Seconds 1
Write-Host "Starting process data collection in 2 seconds..."
Start-Sleep -Seconds 1
Write-Host "Starting process data collection in 1 seconds..."
Start-Sleep -Seconds 1
Write-Host " "
Write-Host "Data collection will start now and the HTML page will open..."
Start-Sleep -Seconds 1

$firstUsage = $true

# Helper function: Load .CSV
function Load-CSV-Data {
    if (Test-Path $csvFile) {
        try {
            return Import-Csv $csvFile
        } catch {
            Write-Warning "Error on loading the .CSV file: $_"
            return @()
        }
    } else {
        return @()
    }
}

while ($true) {
    $zeit = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $werte = @()
    foreach ($prozess in $prozessList) {
        $p = Get-Process -Name $prozess.Name -ErrorAction SilentlyContinue
        if ($p) {
            $totalWorkingSet = ($p | Measure-Object -Property WorkingSet64 -Sum).Sum
            $totalPrivateMemory = ($p | Measure-Object -Property PrivateMemorySize64 -Sum).Sum
            $ramMB = [math]::Round($totalWorkingSet / 1MB, 2)
            $privateMB = [math]::Round($totalPrivateMemory / 1MB, 2)
        } else {
            $ramMB = 0
            $privateMB = 0
        }

        $werte += [PSCustomObject]@{
            Zeit = $zeit
            Prozess = $prozess.Name
            WorkingSet64 = $ramMB
            PrivateMemorySize64 = $privateMB
        }
    }

    try {
        if (!(Test-Path $csvFile)) {
            $werte | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
        } else {
            $werte | Export-Csv -Path $csvFile -NoTypeInformation -Append -Encoding UTF8
        }
    } catch {
        Write-Warning "Error while writing the .CSV: $_"
    }

    $alleDaten = Load-CSV-Data
    if ($alleDaten.Count -eq 0) {
        Start-Sleep -Seconds $intervallSek
        continue
    }

    # Chart Labels
    $labels = $alleDaten | Where-Object { $_.Prozess -eq $prozessList[0].Name } | Select-Object -ExpandProperty Zeit
    $labelsJS = ($labels | ForEach-Object { "'$_'" }) -join ", "
    $labelsJS = "[" + $labelsJS + "]"

    # Chart Datasets
    $datasetsObjekte = @()
    foreach ($prozess in $prozessList) {
        $farbe = $prozess.Farbe
        $werteWorking = $alleDaten | Where-Object { $_.Prozess -eq $prozess.Name } | Select-Object -ExpandProperty WorkingSet64
        $werteWorking = $werteWorking | ForEach-Object {
            try {
                [double]::Parse($_.ToString().Replace(',', '.'), [System.Globalization.CultureInfo]::InvariantCulture)
            } catch { 0 }
        }

        $wertePrivate = $alleDaten | Where-Object { $_.Prozess -eq $prozess.Name } | Select-Object -ExpandProperty PrivateMemorySize64
        $wertePrivate = $wertePrivate | ForEach-Object {
            try {
                [double]::Parse($_.ToString().Replace(',', '.'), [System.Globalization.CultureInfo]::InvariantCulture)
            } catch { 0 }
        }

        $datasetsObjekte += @{
            label = "$($prozess.Name) WorkingSet"
            data = $werteWorking
            borderColor = $farbe
            borderWidth = 2
            fill = $false
        }
        $datasetsObjekte += @{
            label = "$($prozess.Name) Private"
            data = $wertePrivate
            borderColor = $farbe
            borderWidth = 2
            fill = $false
            borderDash = @(8,4)
        }
    }

    $datasetsJSON = $datasetsObjekte | ConvertTo-Json -Depth 5

    # Letzte Werte-Tabelle vorbereiten
    $letzteWerte = $alleDaten | Group-Object Prozess | ForEach-Object {
        $_.Group | Sort-Object Zeit | Select-Object -Last 1
    }

    $tabelleHTML = "<table border='1' cellpadding='6' style='border-collapse:collapse; margin-top:20px;'>
<tr style='background:#eee; font-weight:bold;'>
<th>Time</th><th>Process</th><th>Working RAM (MB)</th><th>Private RAM (MB)</th><th>Color</th><th>Threshold</th>
</tr>"

    foreach ($eintrag in $letzteWerte) {
        $prozessDef = $prozessList | Where-Object { $_.Name -eq $eintrag.Prozess }
        $farbe = $prozessDef.Farbe
        $schwellwert = $prozessDef.Schwellwert

        $working = [double]::Parse($eintrag.WorkingSet64.ToString().Replace(',', '.'), [System.Globalization.CultureInfo]::InvariantCulture)
        $private = [double]::Parse($eintrag.PrivateMemorySize64.ToString().Replace(',', '.'), [System.Globalization.CultureInfo]::InvariantCulture)

        $workingHTML = if ($working -gt $schwellwert) { "<span style='color:red;font-weight:bold'>$working</span>" } else { "$working" }
        $privateHTML = if ($private -gt $schwellwert) { "<span style='color:red;font-weight:bold'>$private</span>" } else { "$private" }

        $tabelleHTML += "<tr>
<td>$($eintrag.Zeit)</td>
<td>$($eintrag.Prozess)</td>
<td>$workingHTML</td>
<td>$privateHTML</td>
<td><span style='color:$farbe;'>$farbe</span></td>
<td>$schwellwert</td>
</tr>"
    }

    $tabelleHTML += "</table>"

    # HTML erzeugen
    $html = @"
<!DOCTYPE html>
<html lang='de'>
<head>
  <meta charset='UTF-8'>
  <title>RAM Monitor</title>
  <meta http-equiv='refresh' content='$autoReloadSek'>
  <script src='https://cdn.jsdelivr.net/npm/chart.js'></script>
  <style>
    body { font-family: sans-serif; margin: 20px; }
    canvas { max-width: 100%; }
    table { font-size: 14px; }
  </style>
</head>
<body>
  <h2>RAM usage of processes:</h2>
  <canvas id='ramChart' width='900' height='400'></canvas>

  <script>
    const labels = $labelsJS;
    const datasets = $datasetsJSON;
    const ctx = document.getElementById('ramChart').getContext('2d');
    const ramChart = new Chart(ctx, {
      type: 'line',
      data: {
        labels: labels,
        datasets: datasets
      },
      options: {
        responsive: true,
        animation: { duration: 0 },
        plugins: {
          legend: { display: true }
        },
        interaction: {
          mode: 'nearest',
          axis: 'x',
          intersect: false
        },
        scales: {
          y: {
            title: { display: true, text: 'RAM (MB)' },
            beginAtZero: true
          },
          x: {
            title: { display: true, text: 'TIME' }
          }
        }
      }
    });
  </script>

  <h3>Last measured values</h3>
  $tabelleHTML
</body>
</html>
"@

    try {
        Set-Content -Path $htmlFile -Value $html -Encoding UTF8
        if ($firstUsage) {
            Start-Process $htmlFile
            $firstUsage = $false
        }
    } catch {
        Write-Warning "Error writing/opening HTML file: $_"
    }

    Start-Sleep -Seconds $intervallSek

}
