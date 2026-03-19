Import-Module WebAdministration

$results = @()

Get-Website | ForEach-Object {
    foreach ($binding in $_.Bindings.Collection) {

        $parts = $binding.bindingInformation.Split(':')
        $hostname = $parts[2]

        if ([string]::IsNullOrWhiteSpace($hostname)) {
            return
        }

        $ip = $null

        try {
            # Preferred: DNS resolution
            $dns = Resolve-DnsName -Name $hostname -ErrorAction Stop |
                   Where-Object { $_.Type -eq "A" }

            if ($dns) {
                $ip = ($dns | Select-Object -ExpandProperty IPAddress) -join ", "
            }
        }
        catch {
            # Fallback: ping (Test-Connection)
            try {
                $ping = Test-Connection -ComputerName $hostname -Count 1 -ErrorAction Stop
                $ip = $ping.IPV4Address.IPAddressToString
            }
            catch {
                $ip = "UNRESOLVED"
            }
        }

        $results += [PSCustomObject]@{
            Domain = $hostname
            IP     = $ip
        }
    }
}

# Remove duplicates (same domain appearing in multiple sites)
$results |
    Sort-Object Domain -Unique |
    Format-Table -AutoSize

# Optional export
# $results | Sort-Object Domain -Unique | Export-Csv "Domain_IPs.csv" -NoTypeInformation
