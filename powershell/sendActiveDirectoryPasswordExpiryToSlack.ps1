# EXPECTS USER SLACK MEMBER IDS TO BE STORED IN AD FIELD "IP phone"

$slackurl = "<slack webhook url here>"
$domain = (Get-ADDomain).Name
[int]$warningdays = 15
[bool]$loggish = $False

function Send-Slack-Alert {
    param ($User)

    $days = $User.ExpiringIn
    $msg = "";
    if($null -eq $days) {
        $msg = "Hi "+$User.GivenName+". This is to let you know that your password for account ``"+$User.SamAccountName+"@$domain`` does not expire."
    } elseif($days -gt 0) {
        $msg = "Hi "+$User.GivenName+". This is to let you know that your password for account ``"+$User.SamAccountName+"@$domain`` is expiring in ``"+$User.ExpiringIn+"`` days on ``"+$User.ExpiryDate+"``."
    } else {
        $msg = "Hi "+$User.GivenName+". This is to let you know that your password for account ``"+$User.SamAccountName+"@$domain`` expired on ``"+$User.ExpiryDate+"``. Please contact an administrator to have it reset."
    }

    $post = @{
        channel = $User.SlackID; 
        text = $msg;
        username = "$domain Password Expiry";
        icon_emoji = ":key:"
    }
    $json = $post | ConvertTo-Json -Compress
    if($loggish) { $json }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $resp = Invoke-WebRequest -uri $slackurl -Method POST -Body $json
    if($loggish) { $resp }
}

$excludes = @("samName1", "samName2", "samName3")
$filter = { Enabled -eq $True -and PasswordNeverExpires -eq $False }

# FOLLOWING LINE CAN BE USED TO PULL SPECIFIC USER FOR TESTING
#$filter = { SamAccountName -eq "someUserToTest" }

$users = Get-ADUser -Filter $filter -Properties "SamAccountName", "GivenName", "msDS-UserPasswordExpiryTimeComputed", "IPPhone" |
         Select-Object -Property "SamAccountName", "GivenName", 
            @{ Name="SlackID"; Expression={ $_.IPPhone } }, 
            @{ Name="ExpiryDate"; Expression={ [datetime]::FromFileTime($_."msDS-UserPasswordExpiryTimeComputed") } }, 
            @{ Name="ExpiringIn"; Expression={ [datetime]::FromFileTime($_."msDS-UserPasswordExpiryTimeComputed").Subtract((Get-Date)).Days }} |
         Where-Object ExpiringIn -le $warningdays | 
         Where-Object { $excludes -notcontains $_.SamAccountName } 
if($loggish) { $users }

$users | ForEach-Object {
    if(![string]::IsNullOrWhiteSpace($_.SlackID)) {
        Send-Slack-Alert $_
    }
}

# SEND OVERVIEW TO AD-ADMIN CHANNEL
$msg = "";
if($users.Count -eq 0) {
    $msg = "No users' passwords are expiring within the next "+$warningdays+" days.";
} else {
    $msg = "The following users' passwords are expiring soon (or expired):`n" + ($users | Format-Table | Out-String)
}

$post = @{
    text = $msg;
    username = "$domain Password Expiries";
    icon_emoji = ":key:"
}
$json = $post | ConvertTo-Json -Compress
if($loggish) { $json }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$resp = Invoke-WebRequest -uri $slackurl -Method POST -Body $json
if($loggish) { $resp }
