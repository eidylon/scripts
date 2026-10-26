
# Redis Memory Load Check
# No external modules or redis-cli.exe required.

# ---------------- Configuration ----------------
$RedisHost = "your.redis.server.com"
$RedisPort = 6380
$AccessKey = "YourRedisPasswordHere"

# Leave empty for password-only AUTH.
# Set this if your Redis instance uses ACL authentication.
$RedisUser = ""

# Alert when usage exceeds this percentage of maxmemory.
$ThresholdPercentWarning = 80
$ThresholdPercentCritical = 90

# Optional fallback maxmemory in bytes.
# Leave 0 to retrieve it using CONFIG GET maxmemory.
# Set this manually if your Redis service restricts CONFIG.
$MaxMemoryBytes = 0

$TimeoutMilliseconds = 8000
# ------------------------------------------------

function iif($bool, $ifTrue, $ifFalse) {
    if($bool) {
        return $ifTrue
    } else {
        return $ifFalse
    }
}

function Send-Slack-Alert {
    param([string]$Message, [bool] $isCritical)

    $slackurl = "https://hooks.slack.com/services/.........."


    $post = @{
        channel = "#hw-admin";
        text = $Message;
        username = "Redis Memory Load";
        icon_emoji = (iif ($isCritical) ":sos:" ":warning:")
    }
    $json = $post | ConvertTo-Json -Compress
    if($loggish) { $json }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $resp = Invoke-WebRequest -uri $slackurl -Method POST -Body $json -UseBasicParsing
    if($loggish) { $resp }
}

function Read-RedisLine {
    param([System.IO.Stream]$Stream)

    $bytes = [System.Collections.Generic.List[byte]]::new()

    while ($true) {
        $b = $Stream.ReadByte()

        if ($b -lt 0) {
            throw "Redis closed the connection while reading a response line."
        }

        if ($b -eq 13) {
            $next = $Stream.ReadByte()

            if ($next -lt 0) {
                throw "Redis closed the connection after CR."
            }

            if ($next -eq 10) {
                break
            }

            $bytes.Add([byte]$b)
            $bytes.Add([byte]$next)
            continue
        }

        $bytes.Add([byte]$b)
    }

    return [System.Text.Encoding]::UTF8.GetString($bytes.ToArray())
}

function Read-RedisExactBytes {
    param(
        [System.IO.Stream]$Stream,
        [int]$Count
    )

    if ($Count -lt 0) {
        throw "Invalid negative RESP bulk length: $Count"
    }

    $buffer = [byte[]]::new($Count)
    $offset = 0

    while ($offset -lt $Count) {
        $read = $Stream.Read($buffer, $offset, $Count - $offset)

        if ($read -le 0) {
            throw "Redis closed the connection while reading a bulk response."
        }

        $offset += $read
    }

    $cr = $Stream.ReadByte()
    $lf = $Stream.ReadByte()

    if ($cr -ne 13 -or $lf -ne 10) {
        throw "Malformed Redis RESP bulk response terminator."
    }

    return ,$buffer
}

function Read-RedisResponse {
    param([System.IO.Stream]$Stream)

    $prefixByte = $Stream.ReadByte()

    if ($prefixByte -lt 0) {
        throw "Redis closed the connection before sending a response."
    }

    $prefix = [char]$prefixByte

    switch ($prefix) {
        '+' {
            return (Read-RedisLine -Stream $Stream)
        }

        '-' {
            throw ("Redis error: " + (Read-RedisLine -Stream $Stream))
        }

        ':' {
            $line = Read-RedisLine -Stream $Stream
            [long]$number = 0

            if (-not [long]::TryParse($line, [ref]$number)) {
                throw "Malformed Redis integer response: $line"
            }

            return $number
        }

        '$' {
            $line = Read-RedisLine -Stream $Stream
            [int]$length = 0

            if (-not [int]::TryParse($line, [ref]$length)) {
                throw "Malformed Redis bulk length: $line"
            }

            if ($length -eq -1) {
                return $null
            }

            $data = Read-RedisExactBytes -Stream $Stream -Count $length
            return [System.Text.Encoding]::UTF8.GetString($data)
        }

        '*' {
            $line = Read-RedisLine -Stream $Stream
            [int]$count = 0

            if (-not [int]::TryParse($line, [ref]$count)) {
                throw "Malformed Redis array length: $line"
            }

            if ($count -eq -1) {
                return $null
            }

            $items = [System.Collections.Generic.List[object]]::new()

            for ($i = 0; $i -lt $count; $i++) {
                $items.Add((Read-RedisResponse -Stream $Stream))
            }

            return ,($items.ToArray())
        }

        default {
            throw "Unsupported Redis RESP response prefix: '$prefix'"
        }
    }
}

function Send-RedisCommand {
    param(
        [System.IO.Stream]$Stream,
        [string[]]$Arguments
    )

    $memory = [System.IO.MemoryStream]::new()

    try {
        $header = [System.Text.Encoding]::ASCII.GetBytes(
            "*$($Arguments.Count)`r`n"
        )

        $memory.Write($header, 0, $header.Length)

        foreach ($argument in $Arguments) {
            $argBytes = [System.Text.Encoding]::UTF8.GetBytes(
                [string]$argument
            )

            # RESP bulk length is the UTF-8 byte count, not string length.
            $argHeader = [System.Text.Encoding]::ASCII.GetBytes(
                "`$$($argBytes.Length)`r`n"
            )

            $memory.Write($argHeader, 0, $argHeader.Length)

            if ($argBytes.Length -gt 0) {
                $memory.Write($argBytes, 0, $argBytes.Length)
            }

            $crlf = [byte[]](13, 10)
            $memory.Write($crlf, 0, $crlf.Length)
        }

        $payload = $memory.ToArray()
        $Stream.Write($payload, 0, $payload.Length)
        $Stream.Flush()
    }
    finally {
        $memory.Dispose()
    }

    return (Read-RedisResponse -Stream $Stream)
}

function Get-RedisInfoValue {
    param(
        [string]$InfoText,
        [string]$Name
    )

    $pattern = '(?m)^' + [regex]::Escape($Name) + ':([^\r\n]+)\s*$'
    $match = [regex]::Match($InfoText, $pattern)

    if (-not $match.Success) {
        throw "Redis INFO memory did not contain '$Name'."
    }

    [long]$value = 0

    if (-not [long]::TryParse($match.Groups[1].Value, [ref]$value)) {
        throw "Redis returned a non-numeric value for '$Name'."
    }

    return $value
}

$tcp = $null
$ssl = $null

try {
    if ([string]::IsNullOrWhiteSpace($RedisHost) -or
        $RedisHost -eq "YOUR_REDIS_HOST") {
        throw "Set `$RedisHost in the configuration section."
    }

    if ([string]::IsNullOrWhiteSpace($AccessKey) -or
        $AccessKey -eq "YOUR_REDIS_ACCESS_KEY") {
        throw "Set `$AccessKey in the configuration section."
    }

    # Connect with a timeout.
    $tcp = [System.Net.Sockets.TcpClient]::new()
    $connectTask = $tcp.ConnectAsync($RedisHost, $RedisPort)

    if (-not $connectTask.Wait($TimeoutMilliseconds)) {
        throw "Timed out connecting to Redis at ${RedisHost}:$RedisPort."
    }

    $tcp.ReceiveTimeout = $TimeoutMilliseconds
    $tcp.SendTimeout = $TimeoutMilliseconds

    # Intentionally accepts any server certificate, including self-signed.
    # This bypasses certificate validation; use only if that is intentional.
    $certificateCallback = [System.Net.Security.RemoteCertificateValidationCallback]{
        param($sender, $certificate, $chain, $sslPolicyErrors)
        return $true
    }

    $ssl = [System.Net.Security.SslStream]::new(
        $tcp.GetStream(),
        $false,
        $certificateCallback
    )

    $ssl.ReadTimeout = $TimeoutMilliseconds
    $ssl.WriteTimeout = $TimeoutMilliseconds

    $ssl.AuthenticateAsClient(
        $RedisHost,
        $null,
        [System.Security.Authentication.SslProtocols]::Tls12,
        $true
    )

    # Authenticate before issuing Redis commands.
    if (-not [string]::IsNullOrWhiteSpace($RedisUser)) {
        $authResponse = Send-RedisCommand -Stream $ssl -Arguments @(
            "AUTH", $RedisUser, $AccessKey
        )
    }
    else {
        $authResponse = Send-RedisCommand -Stream $ssl -Arguments @(
            "AUTH", $AccessKey
        )
    }

    if ($authResponse -ne "OK") {
        throw "Redis authentication did not return OK."
    }

    # Read used memory.
    $info = Send-RedisCommand -Stream $ssl -Arguments @("INFO", "memory")

    if ($null -eq $info -or $info -isnot [string]) {
        throw "Redis INFO memory returned an unexpected response."
    }

    $usedMemory = Get-RedisInfoValue -InfoText $info -Name "used_memory"

    # Get maxmemory from Redis, unless a manual fallback was configured.
    if ($MaxMemoryBytes -gt 0) {
        $maxMemory = [long]$MaxMemoryBytes
    }
    else {
        $config = Send-RedisCommand -Stream $ssl -Arguments @(
            "CONFIG", "GET", "maxmemory"
        )

        if ($null -eq $config -or $config.Count -lt 2) {
            throw "Unexpected CONFIG GET maxmemory response. If CONFIG is restricted, set `$MaxMemoryBytes manually."
        }

        [long]$maxMemory = 0

        if (-not [long]::TryParse([string]$config[1], [ref]$maxMemory)) {
            throw "Redis returned an invalid maxmemory value: $($config[1])"
        }
    }

    if ($maxMemory -le 0) {
        throw "Redis maxmemory is unlimited or invalid. Set `$MaxMemoryBytes to a positive byte value to use a fixed limit."
    }

    $usedPercent = ($usedMemory / [double]$maxMemory) * 100
    $usedMiB = [math]::Round($usedMemory / 1MB, 2)
    $maxMiB = [math]::Round($maxMemory / 1MB, 2)

    Write-Host (
        "Redis memory: {0:N2} MB / {1:N2} MB ({2:N1}%)" -f
        $usedMiB, $maxMiB, $usedPercent
    )

    $isOverThreshold = $false;
    $isCritical = $false;
    $thresholdPercent = 0;
    if ($usedPercent -gt $ThresholdPercentCritical) {
        $isOverThreshold = $true;
        $isCritical = $true;
        $thresholdPercent = $ThresholdPercentCritical;
    } else {
        if ($usedPercent -gt $ThresholdPercentWarning) {
            $isOverThreshold = $true;
            $isCritical = $false;
            $thresholdPercent = $ThresholdPercentWarning;
        }
    }

    if ($isOverThreshold) {
        $message = (
            "Redis memory usage is {0:N1}% ({1:N2} MB of {2:N2} MB), " +
            "above the configured threshold of {3}%."
        ) -f $usedPercent, $usedMiB, $maxMiB, $thresholdPercent

        Send-Slack-Alert -Message $message -isCritical $isCritical
    }
}
catch {
    Write-Error "Redis memory check failed: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($null -ne $ssl) {
        $ssl.Dispose()
    }

    if ($null -ne $tcp) {
        $tcp.Dispose()
    }
}
