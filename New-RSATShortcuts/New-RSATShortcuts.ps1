<#
  .SYNOPSIS
    Creates desktop shortcuts to run RSAT tools as a higher-privileged user
  .NOTES
    Author      : Sean McGrath
    Last update : Januay 16, 2019
#>

Function Set-Shortcut() {
    param ( [string]$SourceExe, [string]$ArgumentsToSourceExe, [string]$DestinationPath, [string]$IconLocation, [int]$IconArrayIndex )
    $WshShell = New-Object -comObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($DestinationPath)
    $Shortcut.TargetPath = $SourceExe
    $Shortcut.Arguments = $ArgumentsToSourceExe
    $Shortcut.IconLocation = "$IconLocation, $IconArrayIndex"
    $Shortcut.Save()
}

# Change to reflect your administrative user naming scheme
$adminusername = "$env:USERDOMAIN\$env:USERNAME-admin"
$desktop = [Environment]::getfolderpath("desktop")
$rsatfolder = "$desktop\RSAT"

# Add any extra tools that you use here
$documents = @()
$documents += New-Object PSObject -Property @{name = "Users & Computers"; path = "mmc %SystemRoot%\System32\dsa.msc"; iconlocation = "%SystemRoot%\system32\dsadmin.dll"; iconarrayindex = "0"}
$documents += New-Object PSObject -Property @{name = "DNS"; path = "mmc %SystemRoot%\System32\dnsmgmt.msc"; iconlocation = "%SystemRoot%\system32\dnsmgr.dll"; iconarrayindex = "0"}
$documents += New-Object PSObject -Property @{name = "DFS"; path = "mmc %SystemRoot%\System32\dfsmgmt.msc"; iconlocation = "%SystemRoot%\system32\dfsres.dll"; iconarrayindex = "0"}
$documents += New-Object PSObject -Property @{name = "DHCP"; path = "mmc %SystemRoot%\System32\dhcpmgmt.msc"; iconlocation = "%SystemRoot%\system32\dhcpsnap.dll"; iconarrayindex = "0"}
$documents += New-Object PSObject -Property @{name = "AD Domains & Trusts"; path = "mmc %SystemRoot%\System32\domain.msc"; iconlocation = "%SystemRoot%\system32\domadmin.dll"; iconarrayindex = "0"}
$documents += New-Object PSObject -Property @{name = "AD Sites & Services"; path = "mmc %SystemRoot%\System32\dssite.msc"; iconlocation = "%SystemRoot%\system32\dsadmin.dll"; iconarrayindex = "2"}
$documents += New-Object PSObject -Property @{name = "Group Policy Management"; path = "mmc %SystemRoot%\System32\gpmc.msc"; iconlocation = "%SystemRoot%\system32\gpoadmin.dll"; iconarrayindex = "0"}
$documents += New-Object PSObject -Property @{name = "Server Manager"; path = "%SystemRoot%\System32\ServerManager.exe"; iconlocation = "%SystemRoot%\system32\svrmgrnc.dll"; iconarrayindex = "0"}


$problem = $false
foreach ($doc in $documents) {
    if (Test-Path $([Environment]::ExpandEnvironmentVariables(($doc.path).TrimStart("mmc ")))) {
        New-Item -ItemType directory -Path $rsatfolder -ErrorAction SilentlyContinue
        Set-Shortcut "%SystemRoot%\System32\runas.exe" "/savecred /user:$($adminusername) `"%SystemRoot%\System32\cmd.exe /C start /B $($doc.path)`"" "$($rsatfolder)\$($doc.name).lnk" -IconLocation "$($doc.iconlocation)" -IconArrayIndex $($doc.iconarrayindex)
    }
    else {
        $problem = $true
        Write-Output "Path '$($doc.path)' for $($doc.name) doesn't exist. Is RSAT installed?"
    }
}

if ($problem -and !$psISE) {
    Write-Host -NoNewline "Press any key to end..."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
