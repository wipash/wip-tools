<# 
  .SYNOPSIS
    Clean up stale AD Computer Accounts
  .DESCRIPTION
    Clean up stale computer accounts with the following method:
    - Move all accounts not seen in over $minLastSeen days to $disabledOU, and disable where necessary
    - Delete all accounts in Disabled OU that haven't been modified in over $minLastChanged days
  .NOTES
    Author      : Sean McGrath
    Last update : Januay 16, 2019
#>

# Use S.DS.P module from https://gallery.technet.microsoft.com/scriptcenter/Using-SystemDirectoryServic-0adf7ef5
# This performs a much faster LDAP search, and can return an unlimited set of results
#Requires -Modules S.DS.P
Import-Module S.DS.P

# LDAP Settings
$server = "dc.your.domain.com"
$searchBase = "DC=your,DC=domain,DC=com"

# OU to move stale acocunts to
$disabledOU = "OU=Disabled,DC=your,DC=domain,DC=com"

# OU to exclude, to enable retention of old computer accounts that are still used occasionally
$excludeOU = "OU=Retain,DC=your,DC=domain,DC=com"

# Minimum days since account was last seen by AD
$minLastSeen = -180

# Minimum days since account was changed (e.g. disabled)
$minLastChanged = -30

$WhatIfPreferenceDefault = $WhatIfPreference
# Set to $true for dry run, $false for production
$WhatIfPreference = $true

# Search filter for computer accounts
$baseSearchFilter = "(objectClass=computer)(!objectClass=msDS-ManagedServiceAccount)(!objectClass=msDS-GroupManagedServiceAccount)"

# Generalized-Time parsing format
$gtfmt = "yyyyMMddHHmmss.f'Z'"
$culture = [Globalization.CultureInfo]::InvariantCulture

# Calculate dates
$minLastSeenDate = ([DateTime]::Now.AddDays($minLastSeen)).toFileTime()
$minLastChangedDate = [DateTime]::Now.AddDays($minLastChanged)

# Find all stale computer accounts not in disabled or freezer OUs that have not been seen in specified amount of days
$allStaleComputers = @(Find-LdapObject `
        -LdapConnection $server `
        -searchFilter "(&$baseSearchFilter(lastlogontimestamp<=$minLastSeenDate))" `
        -searchBase $searchBase) |
    Where-Object {($_.distinguishedName -notmatch $disabledOU) -and ($_.distinguishedName -notmatch $excludeOU)}

# Move and all stale computer accounts to the Disabled OU
$allStaleComputers | ForEach-Object {
    Write-Output "Moving $($_.distinguishedName)"
    Move-ADObject -Identity $_.distinguishedName -TargetPath $disabledOU
}

# Run a new LDAP query to find all computers in the Disabled OU, including the ones we just moved there
$disabledOuComputers = @(Find-LdapObject `
        -LdapConnection $server `
        -searchFilter "(&$baseSearchFilter)" `
        -searchBase $disabledOU `
        -PropertiesToLoad @('whenChanged', 'userAccountControl', 'lastlogontimestamp'))

# Make sure computer accounts already in the Disabled OU are actually disabled
# Check if second bit in userAccountControl is set, to see if account is disabled: [convert]::ToString($_.userAccountControl,2) -band 2
$activeComputersInDisabledOU = $disabledOUComputers | Where-Object {([convert]::ToString($_.userAccountControl, 2) -band 2) -eq 0}
$activeComputersInDisabledOU | 
    ForEach-Object {
    Write-Output "Disabling $($_.distinguishedName)"
    Set-ADComputer -Identity $_.distinguishedName -Enabled $false
}

# Delete disabled accounts if they have been unchanged in longer than 1 month, and not logged in over 6 months
# Don't delete computers that we just disabled (which will have an out-of-date whenChanged value)
# whenChanged comes out of LDAP as a "Generalized-Time" string, so needs to be parsed into DateTime using format defined above
$disabledOUComputers | Where-Object {
    (([convert]::ToString($_.userAccountControl, 2) -band 2) -eq 2) `
        -and ($_.distinguishedName -notin $activeComputersInDisabledOU.distinguishedName) `
        -and ($_.lastlogontimestamp -le $minLastSeenDate) `
        -and ([DateTime]::ParseExact($_.whenChanged, $gtfmt, $culture) -le $minLastChangedDate)
} | ForEach-Object {
    Write-Output "Deleting $($_.distinguishedName)"
    Remove-ADObject -Identity $_.distinguishedName -Recursive -Confirm:$False
}

# Reset $WhatIfPreference
$WhatIfPreference = $WhatIfPreferenceDefault