# Grant Manage Documents on All Shared Printers
# Run in an elevated PowerShell session on the print server.

$Account = "mydomain\someuser"   # Change this
$WhatIf  = $true                # Preview first; set to $false to apply

$SID = ([System.Security.Principal.NTAccount]$Account).Translate(
    [System.Security.Principal.SecurityIdentifier]
)

$Printers = Get-Printer | Where-Object { $_.Shared }

$Mask = 983052
$Inherit = [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
$Propagation = [System.Security.AccessControl.PropagationFlags]::InheritOnly

foreach ($Printer in $Printers) {
    try {
        $Printer = Get-Printer -Name $Printer.Name -Full -ErrorAction Stop

        $SD = [System.Security.AccessControl.CommonSecurityDescriptor]::new(
            $true,
            $false,
            $Printer.PermissionSDDL
        )

        $Exists = $false

        $ACL = [System.Security.AccessControl.RawSecurityDescriptor]::new(
            $Printer.PermissionSDDL
        ).DiscretionaryAcl

        foreach ($ACE in $ACL) {
            if ($ACE.SecurityIdentifier.Value -eq $SID.Value -and
                $ACE.AccessMask -eq $Mask) {
                $Exists = $true
                break
            }
        }

        if ($Exists) {
            Write-Host "SKIP:    $($Printer.Name) (permission exists)"
            continue
        }

        $SD.DiscretionaryAcl.AddAccess(
            [System.Security.AccessControl.AccessControlType]::Allow,
            $SID,
            $Mask,
            $Inherit,
            $Propagation
        )

        $NewSDDL = $SD.GetSddlForm(
            [System.Security.AccessControl.AccessControlSections]::All
        )

        if ($WhatIf) {
            Write-Host "PREVIEW: $($Printer.Name)"
        }
        else {
            Set-Printer -Name $Printer.Name `
                -PermissionSDDL $NewSDDL -ErrorAction Stop

            Write-Host "UPDATED: $($Printer.Name)"
        }
    }
    catch {
        Write-Warning "FAILED: $($Printer.Name) — $($_.Exception.Message)"
    }
}
