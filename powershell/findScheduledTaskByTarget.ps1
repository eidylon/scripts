$target = "File.exe"

Get-ScheduledTask | ForEach-Object {
    $task = $_
    foreach ($action in $task.Actions) {
        if ($action.Execute -like "*$target*") {
            [PSCustomObject]@{
                TaskName  = $task.TaskName
                TaskPath  = $task.TaskPath
                Execute   = $action.Execute
                Arguments = $action.Arguments
            }
        }
    }
}
