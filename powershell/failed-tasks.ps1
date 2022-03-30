$slackurl = "<slack webhook url>"
$comp = $env:computername
$envkey = "FailTasksLastRun"
[bool]$loggish = $False
[bool]$sendOnZero = $True

$env = [System.Environment]::GetEnvironmentVariable($envkey)
[DateTime]$lastRun = if($env -eq $null) { '01/01/1900' } else { $env }
[DateTime]$thisRun = Get-Date

$tasks = Get-ScheduledTask | 
    Where-Object State -eq 'Ready' | 
    Where-Object TaskPath -like '*Folder*' | 
    Get-ScheduledTaskInfo |
    Where-Object LastTaskResult -ne 0 |
    Where-Object LastRunTime -gt $lastRun
    Select-Object -Property TaskPath, TaskName, LastTaskResult 

if($loggish) { $tasks }

$msg = "";
[int]$count = $tasks.Count 
if($sendOnZero -or $count -gt 0) {
    if($count -eq 0) {
        $msg = "All tasks last completed successfully.";
    } else {
        $msg = "The following $count tasks did not last complete successfully`n" + ($tasks | Format-Table | Out-String)
    }

    $post = @{
        text = $msg;
        username = "$comp Unsuccessful Tasks";
        icon_emoji = ":mag:"
    }
    $json = $post | ConvertTo-Json -Compress
    if($loggish) { $json }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $resp = Invoke-WebRequest -uri $slackurl -Method POST -Body $json
    if($loggish) { $resp }
}

[System.Environment]::SetEnvironmentVariable($envkey, $thisRun, [System.EnvironmentVariableTarget]::Machine)
