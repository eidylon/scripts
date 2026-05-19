Import-Module WebAdministration

Get-Website | ForEach-Object {

    $enabled = (Get-WebConfigurationProperty `
        -PSPath "IIS:\" `
        -Location $_.Name `
        -Filter "/system.webServer/directoryBrowse" `
        -Name "enabled").Value

    if ($enabled) {

        [PSCustomObject]@{
            SiteName    = $_.Name
            PhysicalPath = $_.PhysicalPath
        }
    }

} | Format-Table -AutoSize
