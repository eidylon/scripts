
Import-Module FailoverClusters

$slackurl = "https://hooks.slack.com/services/<webhookurl>"
$domain = (Get-ADDomain).Name
$file = "$($PSScriptRoot)\last-owners.txt"
$logfile = "$($PSScriptRoot)\check-active-nodes.log"
$lasts = @{}
if(Test-Path $file) {
    # Read the list of last owners
    $txt = Get-Content -Path $file
    $txt | ForEach-Object {
        # Split the line into key and value using the colon separator
        $key, $val = $_ -split ':', 2

        # Add the key-value pair to the collection
        $lasts[$key.Trim()] = $val.Trim()
    }
}

# Get the list of current owners
$currents = @{}
$changes = @()
$clusters = (Get-Cluster -Domain (Get-ADDomain).DNSRoot)
#$clusters  | Out-File -FilePath $logfile -Append
foreach ($cluster in $clusters) {
    try {
        $groups = (Get-ClusterGroup -Cluster $cluster -ErrorAction Stop)
        #$groups | Out-File -FilePath $logfile -Append
        foreach ($role in $groups) {
            $key = "$($cluster.Name)-$($role.Name)"
            $val = $role.OwnerNode.Name;
            $currents[$key.Trim()] = $val.Trim()
        }
    } catch {
        $changes += New-Object -TypeName PSObject -Property @{
            ClusterRole = "OFFLINE - $($_.Exception.Message)"   
            OldOwner = $cluster.Name
            NewOwner = ''
        }
    }
}

foreach ($key in $currents.Keys) {
    $changes += New-Object -TypeName PSObject -Property @{
        ClusterRole = $key    
        OldOwner = $lasts[$key]
        NewOwner = $currents[$key]
    }
}
$changes = @( $changes | Where-Object { $_.NewOwner -ne $_.OldOwner } )

if(Test-Path $file) { Remove-Item $file }
foreach ($pair in $currents.GetEnumerator() | Sort Name) {
    $line = "{0}:{1}" -f $pair.Key, $pair.Value
    $line | Out-File -FilePath $file -Append
}

if ($changes.Count -gt 0) {
    # SEND OVERVIEW TO HW-ADMIN CHANNEL
    $msg = "The following cluster roles have recently switched active nodes:`n``````" + ($changes | Format-Table | Out-String).Trim() + "``````"

    $post = @{
        channel = "#hw-admin";
        text = $msg;
        username = "$domain Cluster Node Changes";
        icon_emoji = ":loud_sound:"
    }
    $json = $post | ConvertTo-Json -Compress

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -uri $slackurl -Method POST -Body $json
} 
