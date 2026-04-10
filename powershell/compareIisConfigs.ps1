
Add-Type -AssemblyName System.Linq
Add-Type -AssemblyName System.Xml.Linq
Add-Type -AssemblyName System.Text.RegularExpressions

$appHostPath = "\C$\Windows\System32\inetsrv\Config\applicationHost.config"

$slackurl = "https://hooks.slack.com/services/<webhookurl>" #tasks-admin

function sendSlack($message) {    
    $post = @{
        # FOR DEBUGGING, SEND TO ME/AARON, UNTIL READY
        #channel = "UUURZQFR8"; 
    
        channel = "#web-admin"
        text = $message;
        username = "IIS Config Compare";
        icon_emoji = ":spider_web:"
    }
    $json = $post | ConvertTo-Json -Compress
    $json = ([System.Text.Encoding]::UTF8.GetBytes($json))
    
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -uri $slackurl -Method POST -Body $json -UseBasicParsing    
}

function isNullString($str) {
    if([String]::IsNullOrWhiteSpace($str)) {
        return $true
    } else {
        return $false
    }
}

function nullString($str, $def) {
    if(isNullString $str) {
        return $def
    } else {
        return $str
    }
}

function makeMessage([System.Boolean] $good, [string] $what, [Int16] $howMany) {
    return "$(($good ? "🟢" : "❌")) = $what ($howMany)"
}

function getAppPools($xd) {
    return $xd.Root.Element("system.applicationHost").Element("applicationPools").Elements("add") | ForEach-Object { $_.Attribute("name").Value }
}

function compareApplicationPools($xd1, $xd2) {
    $pools1 = getAppPools $xd1
    $pools2 = getAppPools $xd2
    $comp = (Compare-Object $pools1 $pools2 | Out-String)
    $num = ($pools1.Length + $pools2.Length)

    $rv = @()
    if(isNullString $comp) {
        $rv += (makeMessage $true "APPLICATION POOLS - MATCH" $num)
    } else {
        $rv += ""
        $rv += (makeMessage $false "APPLICATION POOLS" $num)
        $rv += $comp
    }
    return $rv
}

function getMimeTypes($xd) {
    return $xd.Root.Element("system.webServer").Element("staticContent").Elements("mimeMap") | ForEach-Object { $_.ToString() }
}

function compareMimeMaps($xd1, $xd2) {
    $mimes1 = getMimeTypes $xd1
    $mimes2 = getMimeTypes $xd2
    $comp = (Compare-Object $mimes1 $mimes2 | Out-String)
    $num = ($mimes1.Length + $mimes2.Length)

    $rv = @()
    if(isNullString $comp) {
        $rv += (makeMessage $true "MIME TYPES - MATCH" $num)
    } else {
        $rv += ""
        $rv += (makeMessage $false "MIME TYPES" $num)
        $rv += $comp
    }
    return $rv
}

function getDefaultDocs($xd) {
    return $xd.Root.Element("system.webServer").Element("defaultDocument").Element("files").Elements("add") | ForEach-Object { $_.Attribute("value").Value }
}

function compareDefaultDocuments($xd1, $xd2) {
    $docs1 = getDefaultDocs $xd1
    $docs2 = getDefaultDocs $xd2
    $comp = (Compare-Object $docs1 $docs2 -SyncWindow 0 | Out-String) # SyncWindow compares with order
    $num = ($docs1.Length + $docs2.Length)

    $rv = @()
    if(isNullString $comp) {
        $rv += (makeMessage $true "DEFAULT DOCUMENTS - MATCH" $num)
    } else {
        $rv += ""
        $rv += (makeMessage $false "DEFAULT DOCUMENTS" $num)
        $rv += $comp
    }
    return $rv
}

function getLocations($xd) {
    return $xd.Root.Elements("location") | Where-Object { -not (isNullString ($_.Attribute("path").Value)) }
}

function compareAuthentications($xd1, $xd2) {
    $locs1 = getLocations $xd1
    $locs2 = getLocations $xd2

    $paths = $locs1 | ForEach-Object { $_.Attribute("path").Value }
    $paths += $locs2 | ForEach-Object { $_.Attribute("path").Value }
    $paths = $paths | Where-Object { -not ($_ -like "*/.well-known") } | Select-Object -Unique | Sort-Object
    $num = $paths.Length

    $results = @()

    # CHECK AUTH CONFIGS ONLY ON ONE SERVER
    $results += $paths | Where-Object {
        $p = $_;
        (($locs1 | Where-Object { $_.Attribute("path").Value -eq $p}).Count -eq 0) -or 
        (($locs2 | Where-Object { $_.Attribute("path").Value -eq $p}).Count -eq 0) 
    } | ForEach-Object {
        $p = $_;
        "$_ (exists) > "+
        ((($locs1 | Where-Object { $_.Attribute("path").Value -eq $p}).Count -eq 0) ? "missing" : "exists ")+" : "+
        ((($locs2 | Where-Object { $_.Attribute("path").Value -eq $p}).Count -eq 0) ? "missing" : " exists ")
    } 

    # CHECK SITE BINDINGS
    $results += $paths | Where-Object {
        $p = $_;
        ((($locs1 | Where-Object { $_.Attribute("path").Value -eq $p}).Element("system.webServer").Element("security").Element("authentication").Elements() | ForEach-Object { $_.ToString() } | Sort-Object | Out-String)) -ne
        ((($locs2 | Where-Object { $_.Attribute("path").Value -eq $p}).Element("system.webServer").Element("security").Element("authentication").Elements() | ForEach-Object { $_.ToString() } | Sort-Object | Out-String))
    } | ForEach-Object {
        "$_ (authentication) `t> DIFFERENCES IN AUTHENTICATION FOUND"
    } 
    
    $rv = @()
    if($results.Count -eq 0) {
        $rv += (makeMessage $true "AUTHENTICATION - MATCH" $num)
    } else {
        $rv += (makeMessage $false "AUTHENTICATION - DIFFERENCES" $num)
        $rv += $results
    }
    return $rv
}

function getSites($xd) {
    return $xd.Root.Element("system.applicationHost").Element("sites").Elements("site") | Where-Object { $_.Attribute("id").Value -gt 1 }
}

function compareSites($sites1, $sites2) {
    $names = $sites1 | ForEach-Object { $_.Attribute("name").Value }
    $names += $sites2 | ForEach-Object { $_.Attribute("name").Value }
    $names = $names | Select-Object -Unique | Sort-Object
    $num = $names.Length

    $results = @()

    # CHECK SITES ONLY ON ONE SERVER
    $results += $names | Where-Object {
        $n = $_;
        (($sites1 | Where-Object { $_.Attribute("name").Value -eq $n}).Count -eq 0) -or 
        (($sites2 | Where-Object { $_.Attribute("name").Value -eq $n}).Count -eq 0) 
    } | ForEach-Object {
        $n = $_;
        "$_ (exists) > "+
        ((($sites1 | Where-Object { $_.Attribute("name").Value -eq $n}).Count -eq 0) ? "missing" : "exists ")+" : "+
        ((($sites2 | Where-Object { $_.Attribute("name").Value -eq $n}).Count -eq 0) ? "missing" : " exists ")
    } 

    # CHECK SITES APP POOLS
    $results += $names | Where-Object {
        $n = $_;
        ((($sites1 | Where-Object { $_.Attribute("name").Value -eq $n}).Element("application").Attribute("applicationPool").Value) -ne 
        (($sites2 | Where-Object { $_.Attribute("name").Value -eq $n}).Element("application").Attribute("applicationPool").Value))
    } | ForEach-Object {
        $n = $_;
        "$_ (app pool) `t> "+
        (($sites1 | Where-Object { $_.Attribute("name").Value -eq $n}).Element("application").Attribute("applicationPool").Value)+" : "+
        (($sites2 | Where-Object { $_.Attribute("name").Value -eq $n}).Element("application").Attribute("applicationPool").Value)
    } 

    # CHECK SITES APP POOL NAMES
    $results += $names | Where-Object {
        $n = $_;
        ((($sites1 | Where-Object { $_.Attribute("name").Value -eq $n}).Element("application").Attribute("applicationPool").Value) -ne $n) -or
        ((($sites2 | Where-Object { $_.Attribute("name").Value -eq $n}).Element("application").Attribute("applicationPool").Value) -ne $n)
    } | ForEach-Object {
        $n = $_;
        "$_ (app pool name) `t> "+
        (($sites1 | Where-Object { $_.Attribute("name").Value -eq $n}).Element("application").Attribute("applicationPool").Value)+" : "+
        (($sites2 | Where-Object { $_.Attribute("name").Value -eq $n}).Element("application").Attribute("applicationPool").Value)
    } 

    # CHECK SITE BINDINGS
    $results += $names | Where-Object {
        $n = $_;
        ((($sites1 | Where-Object { $_.Attribute("name").Value -eq $n}).Element("bindings").Elements("binding") | ForEach-Object { $_.Attribute("bindingInformation").Value } | Sort-Object | Out-String)) -ne
        ((($sites2 | Where-Object { $_.Attribute("name").Value -eq $n}).Element("bindings").Elements("binding") | ForEach-Object { $_.Attribute("bindingInformation").Value } | Sort-Object | Out-String))
    } | ForEach-Object {
        "$_ (bindings) `t> DIFFERENCES IN BINDINGS FOUND"
    } 

    $rv = @()
    if($results.Count -eq 0) {
        $rv += (makeMessage $true "SITES - MATCH" $num)
    } else {
        $rv += (makeMessage $false "SITES - DIFFERENCES" $num)
        $rv += $results
    }
    return $rv
}

function checkLogLocations($server, $sites) {
    $bads = $sites | Where-Object {
        $null -eq $_.Element("logFile") -or -not ($_.Element("logFile").Attribute("directory").Value -match ("\\"+[Regex]::Escape($_.Attribute("name").Value)+"\\?$"))
    }
    $num = $sites.Length

    $rv = @()
    if($bads.Count -eq 0) {
        $rv += (makeMessage $true "LOG LOCATIONS - $server GOOD" $num)
    } else {
        $rv += ""
        $rv += (makeMessage $false "LOG LOCATIONS - $server" $num)
        $rv += $bads | ForEach-Object { "Site "+$_.Attribute("name")+" should log to its own named directory" }
    }
    return $rv
}

function checkBindingPorts($server, $sites) {
    $bads = $sites | Where-Object {
        ($_.Element("bindings").Elements("binding") | Where-Object { 
            -not ($_.Attribute("bindingInformation").Value -match ("^[^:]+\:40443\:"))
        }).Count -gt 0
    }
    $num = $sites.Length

    $rv = @()
    if($bads.Count -eq 0) {
        $rv += (makeMessage $true "BINDING PORTS - $server GOOD" $num)
    } else {
        $rv += ""
        $rv += (makeMessage $false "BINDING PORTS - $server" $num)
        $rv += $bads | ForEach-Object { "Site "+$_.Attribute("name")+" has bindings not on port 40443" }
    }
    return $rv
}

function compareServers($name, $server1, $server2) { 
    "Comparing [$name]: $server1 <--> $server2"
    $results = @();
    $results += "🟡 = COMPARE IIS CONFIG - $NAME`n`t$server1`n`t$server2"

    $xp1 = "\\$server1$appHostPath"
    $xp2 = "\\$server2$appHostPath"
    $failLoad = $false

    "`tLoading $xp1 ..."
    try {
        $xd1 = [System.Xml.Linq.XDocument]::Load($xp1)
    } catch {
        $results += "ERROR LOADING $xp1; $($_.Exception.Message); terminating."
        $failLoad = $true
    }
    "`tLoading $xp2 ..."
    try {
        $xd2 = [System.Xml.Linq.XDocument]::Load($xp2)
    } catch {
        $results += "ERROR LOADING $xp2; $($_.Exception.Message); terminating."
        $failLoad = $true
    }
    ""
    if(-not $failLoad) {
        $results += (compareApplicationPools $xd1 $xd2)
        $results += (compareMimeMaps $xd1 $xd2)
        $results += (compareDefaultDocuments $xd1 $xd2)
        $results += (compareAuthentications $xd1 $xd2)

        $sites1 = getSites $xd1
        $sites2 = getSites $xd2

        $results += (compareSites $sites1 $sites2)
        $results += (checkLogLocations $server1 $sites1)
        $results += (checkLogLocations $server2 $sites2)
        $results += (checkBindingPorts $server1 $sites1)
        $results += (checkBindingPorts $server2 $sites2)
    }
    
    $results

    $r = sendSlack "$([string]::join("`n", $results))"
}

compareServers "Production" "web1.servers.igniteintegrationsolutions.com" "web2.servers.igniteintegrationsolutions.com"

"Done."
