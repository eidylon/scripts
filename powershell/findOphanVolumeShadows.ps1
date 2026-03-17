Import-Module ActiveDirectory

$searcher = New-Object DirectoryServices.DirectorySearcher
$searcher.Filter = "(&(objectCategory=computer)(operatingSystem=*Server*)(!(name=*NTClus*))(!(name=*CLUSTER*)))"
$searcher.PageSize = 1000

$servers = $searcher.FindAll() | ForEach-Object {
    $_.Properties["name"][0]
} | Sort-Object -Unique

Invoke-Command -ComputerName $servers -ScriptBlock {

    $output = vssadmin list shadows 2>$null

    if ($output -match "Persistent" -and $output -match "No auto release") {
        [PSCustomObject]@{
            Server = $env:COMPUTERNAME
            Details = ($output -join "`n")
        }
    }

} -ErrorAction SilentlyContinue

#AFTER RUNNING, ON APPROPRIATE MACHINE OPEN ADMIN CMD
#RUN "DISKSHADOW", THEN USING THE COPY ID, NOT THE SET ID, RUN
#DELETE SHADOWS ID {volume-copy-id}
