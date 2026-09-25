#===========================================================
# IIS Log Analyzer
#===========================================================

$LogRoot = "D:\wwwroot\logs"

# Leave blank for all sites
$SiteFilter = "some.domain.com"

# Optional date filters - in machine local time; script will convert and query in UTC
#$From = $null
#$To   = $null

$From = [datetime]"2026-08-06 00:00:00"
$To   = [datetime]"2026-08-07 00:00:00"

#===========================================================

$sw = [System.Diagnostics.Stopwatch]::StartNew()

$Summary   = @()
$PerMinute = @()

$Sites = Get-ChildItem $LogRoot -Directory

if ($SiteFilter) {
    $Sites = $Sites | Where-Object Name -eq $SiteFilter
}

foreach ($Site in $Sites) {

    Write-Host "Processing $($Site.Name)..."

    $MinuteStats = @{}

    $TotalRequests = 0
    $TotalTime = 0

    $Times = New-Object System.Collections.Generic.List[int]

    $Errors500 = 0
    $Errors503 = 0

    $Logs = Get-ChildItem $Site.FullName -Filter *.log -Recurse

    if ($From) {
        $From = $From.ToUniversalTime()
    }

    if ($To) {
        $To = $To.ToUniversalTime()
    }

    if ($From -or $To) {

        $Logs = $Logs | Where-Object {

            if ($_.BaseName -match '(\d{6})(?:_x)?$') {

                $logDate = [datetime]::ParseExact(
                    $Matches[1],
                    "yyMMdd",
                    $null
                )

                if ($From -and $logDate.Date -lt $From.Date) {
                    return $false
                }

                if ($To -and $logDate.Date -gt $To.Date) {
                    return $false
                }

                return $true
            }

            # Couldn't parse the filename; process it anyway.
            return $true
        }
    }

    foreach ($Log in $Logs) {

        $Fields = $null

        Get-Content $Log.FullName | ForEach-Object {

            if ($_ -like "#Fields:*") {
                $Fields = ($_ -replace '^#Fields:\s*', '') -split '\s+'
                return
            }

            if ($_ -like "#*") { return }
            if (-not $Fields) { return }

            $Parts = $_.Split(" ")

            $iDate   = $Fields.IndexOf("date")
            $iTime   = $Fields.IndexOf("time")
            $iTaken  = $Fields.IndexOf("time-taken")
            $iStatus = $Fields.IndexOf("sc-status")


            $dt = [datetime]::ParseExact(
                "$($Parts[$iDate]) $($Parts[$iTime])",
                "yyyy-MM-dd HH:mm:ss",
                $null
            )

            if ($From -and $dt -lt $From) { return }
            if ($To   -and $dt -gt $To)   { return }

            $minute = $dt.ToString("yyyy-MM-dd HH:mm")

            if (!$MinuteStats.ContainsKey($minute)) {

                $MinuteStats[$minute] = [PSCustomObject]@{
                    Requests = 0
                    TotalTime = 0
                    MaxTime = 0
                    Errors500 = 0
                    Errors503 = 0
                }

            }

            $taken = 0

            if ($iTaken -ge 0) {
                $taken = [int]$Parts[$iTaken]
            }

            $MinuteStats[$minute].Requests++
            $MinuteStats[$minute].TotalTime += $taken

            if ($taken -gt $MinuteStats[$minute].MaxTime) {
                $MinuteStats[$minute].MaxTime = $taken
            }

            $TotalRequests++
            $TotalTime += $taken

            $Times.Add($taken)

            if ($iStatus -ge 0) {

                switch ($Parts[$iStatus]) {

                    "500" {
                        $Errors500++
                        $MinuteStats[$minute].Errors500++
                    }

                    "503" {
                        $Errors503++
                        $MinuteStats[$minute].Errors503++
                    }
                }

            }

        }

    }

    if ($TotalRequests -eq 0) { continue }

    $Sorted = $Times | Sort-Object
    $P95 = $Sorted[[math]::Floor($Sorted.Count * .95)]

    $PeakConcurrency = 0

    foreach ($Minute in $MinuteStats.Keys) {

        $m = $MinuteStats[$Minute]

        $AvgMs = if ($m.Requests) {
            $m.TotalTime / $m.Requests
        } else {
            0
        }

        $Concurrency =
            ($m.Requests / 60.0) *
            ($AvgMs / 1000.0)

        if ($Concurrency -gt $PeakConcurrency) {
            $PeakConcurrency = $Concurrency
        }

        $PerMinute += [PSCustomObject]@{

            Site = $Site.Name

            Minute = $Minute

            Requests = $m.Requests

            AvgTimeTaken =
                [math]::Round($AvgMs,0)

            MaxTimeTaken =
                $m.MaxTime

            EstimatedConcurrency =
                [math]::Round($Concurrency,2)

            Errors500 =
                $m.Errors500

            Errors503 =
                $m.Errors503
        }

    }

    $Summary += [PSCustomObject]@{

        Site = $Site.Name

        Requests = $TotalRequests

        Minutes = $MinuteStats.Count

        AvgRequestsPerMinute =
            [math]::Round($TotalRequests / $MinuteStats.Count,2)

        PeakRequestsPerMinute =
            ($MinuteStats.Values |
                Measure-Object Requests -Maximum).Maximum

        AvgTimeTaken =
            [math]::Round($TotalTime / $TotalRequests,0)

        P95TimeTaken =
            $P95

        MaxTimeTaken =
            ($Sorted | Measure-Object -Maximum).Maximum

        PeakEstimatedConcurrency =
            [math]::Round($PeakConcurrency,2)

        Errors500 = $Errors500

        Errors503 = $Errors503

    }

}

$Summary |
    Sort PeakEstimatedConcurrency -Descending |
    Export-Csv (Join-Path $PSScriptRoot "Summary.csv") -NoTypeInformation

$PerMinute |
    Sort Site,Minute |
    Export-Csv (Join-Path $PSScriptRoot "PerMinute.csv") -NoTypeInformation

$PerMinute |
    Sort EstimatedConcurrency -Descending |
    Select -First 100 |
    Export-Csv (Join-Path $PSScriptRoot "TopBusyMinutes.csv") -NoTypeInformation

$sw.Stop()

Write-Host
Write-Host "==============================================="
Write-Host "Analysis Complete"
Write-Host "Elapsed: $($sw.Elapsed)"
Write-Host
Write-Host "Summary.csv"
Write-Host "PerMinute.csv"
Write-Host "TopBusyMinutes.csv"
Write-Host "==============================================="
