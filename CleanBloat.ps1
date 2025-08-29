#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
    $id  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pri = New-Object Security.Principal.WindowsPrincipal $id
    return $pri.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Warning "This script should be run as Administrator for reliable uninstalls."
}

function Get-UninstallEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayNamePattern  # accepts wildcards; use exact string if you want
    )

    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    $entries = foreach ($root in $roots) {
        if (Test-Path $root) {
            Get-ChildItem -Path $root -ErrorAction SilentlyContinue |
            Get-ItemProperty -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and $_.UninstallString -and $_.DisplayName -like $DisplayNamePattern }
        }
    }

    # De-dup on key path if the same thing is seen twice
    $entries | Sort-Object PSPath -Unique
}

function Invoke-Uninstall {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$AppName,             # accepts wildcards
        [ValidateSet('Auto','MSI','EXE')][string]$Type='Auto',
        [string[]]$ExeSilentArgs = @('/S','/silent','-silent','/verysilent','/quiet'),
        [switch]$NoRestart
    )

    $matches = Get-UninstallEntries -DisplayNamePattern $AppName
    if (-not $matches) {
        Write-Host "$AppName is not installed on this computer"
        return
    }

    foreach ($m in $matches) {
        $un = $m.UninstallString
        $isMsi = ($m.WindowsInstaller -eq 1) -or ($un -match '(?i)^\s*msiexec(\.exe)?\b')

        if ($Type -eq 'MSI' -or ($Type -eq 'Auto' -and $isMsi)) {
            # Normalize to msiexec /X {GUID} /qn
            $guid = if ($m.PSChildName -match '^\{[0-9A-F-]{36}\}$') { $m.PSChildName } else { $null }
            if ($un -match '(?i)\s/I') { $un = ($un -replace '(?i)\s/I',' /X') }
            elseif ($guid) { $un = "msiexec.exe /x $guid" }

            $un += $NoRestart ? ' /qn /norestart' : ' /qn'
            if ($PSCmdlet.ShouldProcess($m.DisplayName, "Uninstall (MSI)")) {
                Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $un" -Wait -NoNewWindow
            }
        }
        else {
            # EXE: split path and args, preserve existing args, add a silent flag if not present
            $exe, $args = if ($un -match '^\s*"([^"]+)"\s*(.*)$') {
                $matches[1], $matches[2]
            } else {
                ($un -split '\s+', 2) + @('') | Select-Object -First 2
            }

            # Append the first silent arg not already present
            $silentToAdd = ($ExeSilentArgs | Where-Object { $args -notmatch [regex]::Escape($_) } | Select-Object -First 1)
            $finalArgs = ($args, $silentToAdd) -join ' '

            if ($PSCmdlet.ShouldProcess($m.DisplayName, "Uninstall (EXE): $exe $finalArgs")) {
                Start-Process -FilePath $exe -ArgumentList $finalArgs -Wait -NoNewWindow
            }
        }
    }
}

function Remove-AppxPackageEverywhere {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$AppName)

    $apps = Get-AppxPackage -AllUsers | Where-Object { $_.Name -eq $AppName -or $_.PackageFamilyName -eq $AppName }
    if (-not $apps) { Write-Host "$AppName is not installed on this computer" } 
    foreach ($p in $apps) {
        if ($PSCmdlet.ShouldProcess($p.Name, "Remove Appx for all users")) {
            Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        }
    }

    $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $AppName -or $_.PackageName -like "*$AppName*" }
    foreach ($pp in $prov) {
        if ($PSCmdlet.ShouldProcess($pp.DisplayName, "Deprovision")) {
            Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName | Out-Null
        }
    }
}

function Show-UninstallString {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$AppName)
    $matches = Get-UninstallEntries -DisplayNamePattern $AppName
    if ($matches) { $matches | Select-Object DisplayName, UninstallString | Format-Table -AutoSize }
    else { Write-Host "$AppName is not installed on this computer" }
}

# ---------------------------
# Your calls (same intent)
# Tip: dry-run first by adding -WhatIf to see exactly what would run.
# ---------------------------

Invoke-Uninstall -AppName 'Dell SupportAssist' -NoRestart
Invoke-Uninstall -AppName 'Dell Digital Delivery Services' -NoRestart
Invoke-Uninstall -AppName 'Dell Optimizer Core'
Invoke-Uninstall -AppName 'Dell SupportAssist OS Recovery Plugin for Dell Update'
Invoke-Uninstall -AppName 'Dell SupportAssist Remediation'
Invoke-Uninstall -AppName 'Dell Display Manager 2.1'
Invoke-Uninstall -AppName 'Dell Peripheral Manager'
Invoke-Uninstall -AppName 'Dell Core Services' -NoRestart
Invoke-Uninstall -AppName 'Dell Trusted Device Agent' -NoRestart
Invoke-Uninstall -AppName 'Dell Optimizer' -NoRestart

Remove-AppxPackageEverywhere 'Microsoft.GamingApp'
Remove-AppxPackageEverywhere 'Microsoft.MicrosoftOfficeHub'
Remove-AppxPackageEverywhere 'DellInc.DellDigitalDelivery'
Remove-AppxPackageEverywhere 'Microsoft.GetHelp'
Remove-AppxPackageEverywhere 'Microsoft.Getstarted'
Remove-AppxPackageEverywhere 'Microsoft.Messaging'
Remove-AppxPackageEverywhere 'Microsoft.MicrosoftSolitaireCollection'
Remove-AppxPackageEverywhere 'Microsoft.OneConnect'
Remove-AppxPackageEverywhere 'Microsoft.SkypeApp'
Remove-AppxPackageEverywhere 'Microsoft.Wallet'
Remove-AppxPackageEverywhere 'microsoft.windowscommunicationsapps'
Remove-AppxPackageEverywhere 'Microsoft.WindowsFeedbackHub'
Remove-AppxPackageEverywhere 'Microsoft.YourPhone'
Remove-AppxPackageEverywhere 'ZuneMusic'

# M365: strongly recommend ODT-based uninstall for reliability.
# Your existing approach can be brittle across channels/locales.
# Example (ODT):
# setup.exe /configure .\config-uninstall.xml  (DisplayLevel=False, Remove=ALL)

Show-UninstallString 'DELLOSD'
