# Reuse
PowerShell module to reuse JSON dictionary to invoke cmdlets or applications and create configurations from templates

## Install
Run in PowerShell console started as Administrator:

    Install-Module -Name Reuse

## Cmdlets
Here are cmdlets from `Reuse` module:

 - Invoke-ApplicationWithDefaults:  Invokes application replacing arguments with values from Hashtable or JSON file
 - Invoke-CmdletWithDefaults:  Invokes any cmdlet with arguments from Hashtable or JSON file
 - Set-DefaultsToTemplate:  Creates file replacing placeholders with values from Hashtable or JSON file
 - Update-WithDefaults:  Replaces placeholders in string with values from Hashtable or JSON file
 
 Execute "Get-Help CMDLET-NAME -Full" to get detailed help about any particular cmdlet from this list.