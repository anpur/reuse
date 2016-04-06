Function Get-Defaults {
    Param(
        [Parameter(ValueFromPipeline = $true)]
        $Defaults
    )

    If ($Defaults.GetType() -ne [HashTable]) {
        $customObject = Get-Content -Path $Defaults | ConvertFrom-Json
        $Defaults = @{}
        $customObject | Get-Member -MemberType NoteProperty | %{ $Defaults[$_.Name] = $customObject."$($_.Name)" }
    }

    $Defaults
}

Function Update-WithDefaults {
    <#
        .SYNOPSIS
        Replaces placeholders in string with values from Hashtable or JSON file        
        
        .DESCRIPTION
        Replaces placeholders in text with values from Defaults.        

        Placeholder styles:
         - AutoDetect[DEFAULT]
         - PercentWrapped  %placeholder_name%
         - FigureWrapped   {placeholder_name}
         - MSBuild         $(placeholder_name)

         Placeholder names:
          - Can't contain spaces
          - Can contain any other character except closing one         
        
        .OUTPUTS
        String or String[]
        Text with replaced placeholders or list of variables which will be replaced
        
        .PARAMETER Text
        String with placeholders to be replaced with values from Defaults

        .PARAMETER Defaults
        Hashtable with parameters or path to a file which contains JSON dictionary

        .PARAMETER PlaceholderStyle
        Style of placeholders. Check main description to see available styles

        .PARAMETER IgnoreMissing
        Use this switch, if you wan't to ignore missing 

        .PARAMETER ListOnly
        Returns only list of variables which will be replaced
        
        .EXAMPLE
        Update-WithDefaults 'Service IP address: %IP%' @{ 'IP'='127.0.0.1' }

        .EXAMPLE
        Update-WithDefaults -Text 'Building $(assembly)' -Defaults @{ 'assembly'='test.dll' } -PlaceholderStyle MSBuild

        .EXAMPLE
        Update-WithDefaults -Text 'Deploying %service% to slot %slot%' -Defaults my-config.json
        
        my-config.json contents:
        {
            'service': 'myservice',
            'slot': 'Production'
        }        
    #>  
    [CmdletBinding(SupportsShouldProcess=$true)]  
    Param(
        [Parameter(Mandatory = $true, HelpMessage = 'Text with placeholders')]
        [String]
        $Text,

        [Parameter(Mandatory = $true, HelpMessage = 'Hashtable of defaults or path to JSON file with them')]
        [ValidateScript({ ($_ -is [HashTable]) -or (Test-Path -Path $_ -PathType Leaf) })]
        $Defaults, 
              
        [ValidateSet('AutoDetect', 'PercentWrapped', 'FigureWrapped', 'MSBuild')]
        $PlaceholderStyle = 'AutoDetect',

        [switch]
        $IgnoreMissing,

        [switch]
        $ListOnly
    )

    $ErrorActionPreference = 'Stop'

    $Defaults = Get-Defaults -Defaults $Defaults
    
    $patterns = @{
        'PercentWrapped' = '%([^ %]+)%';
        'FigureWrapped'  = '\{([^ %]+)\}';
        'MSBuild'        = '\$\(([^ )]+)\)';
    }
    $pattern = $null

    If ($patterns.ContainsKey($PlaceholderStyle)) {
        $pattern = $patterns[$PlaceholderStyle]
    } Else {
        ForEach($key in $patterns.Keys) {
            $variables = [Regex]::Matches($Text, $patterns[$key]) | %{ $_.Groups[1].Value } | Select-Object -Unique
            If ($variables | ?{ $Defaults.ContainsKey($_) }) {
                $pattern = $patterns[$key]
                Write-Verbose "Auto detected $key pattern"
                Break
            }
        }
    }

    $replacements = @()
    If ($pattern) {
        $matches = [Regex]::Matches($Text, $pattern)
        If ($matches) {
            $matches | %{
                $name = $_.Groups[1].Value
                $capture = [Regex]::Escape($_.Groups[0].Value)
                If ($Defaults.Keys -icontains $name) {
                    $replacements += $name
                    $Text = $Text -replace $capture, $Defaults[$name]
                } ElseIf (-not $IgnoreMissing.IsPresent -and -not $ListOnly.IsPresent) {
                    throw "Value for '$name' placeholder is not available. "
                }
            }
        }
    }
    If (-not $ListOnly.IsPresent) {
        $Text
    } Else {
        $replacements
    }
}

Function FromFileOrMask {
    Param(
        $FileOrMaskOrObject,
        $DefaultMask = '*',
        $Folder
    )
    If (-not $Folder) { $Folder = Get-Location }

    Push-Location -Path $Folder

    If ($FileOrMaskOrObject -eq $null) {
        $result = Get-ChildItem -Name $DefaultMask | Resolve-Path 
    } ElseIf ($FileOrMaskOrObject -is [string]) {
        If (Test-Path -Path $FileOrMaskOrObject -PathType Leaf -IsValid) {
            $result = $FileOrMaskOrObject | Resolve-Path 
        } Else {
            $result = Get-ChildItem -Name $FileOrMaskOrObject | Resolve-Path 
        }
    } Else {
        $result = $FileOrMaskOrObject
    }

    Pop-Location

    If (-not $result) {
        $search = $FileOrMaskOrObject
        If (-not $search) { $search = $DefaultMask }

        throw "File/s '$search' not found in '$Folder'" 
    }

    $result
}

Function Invoke-CmdletWithDefaults {
    <#
        .SYNOPSIS
        Invokes any cmdlet with arguments from Hashtable or JSON file

        .DESCRIPTION
        You can invoke any cmdlet via this one using some default values.
        Those default values can be provided in the form of Hashtable or as path to a file containing JSON dictionary.

        You can provide as many arguments as you want:
            Invoke-CmdletWithDefaults -CmdletName Do-Something -Defaults @{ 'Arg1': 'value1'; 'Arg2': 'value2'; 'Switch1': 'True' }
            will invoke
            Do-Something -Arg1 value1 -Arg2 value2 -Switch1

        You can have switches in defaults too:
            Invoke-CmdletWithDefaults -CmdletName Do-Something -Defaults @{ 'Switch1': '' }
            will invoke
            Do-Something -Switch1

        You can provide more arguments to invoked cmdlet simply adding them as you would do with invoked cmdlet
            Invoke-CmdletWithDefaults -CmdletName Do-Something -Defaults @{ 'Arg1': 'value' } -Arg2 value -Switch1
            will invoke
            Do-Something -Defaults -Arg1 value -Arg2 value -Switch1

        You can override some of defaults:
            Invoke-CmdletWithDefaults -CmdletName Do-Something -Defaults @{ 'Arg1': 'value1'; 'Arg2': 'value2' } -Arg2 'value1 B'
            will invoke
            Do-Something -Arg1 value1 -Arg2 'value1 B'

        Even switches:
            Invoke-CmdletWithDefaults -CmdletName Do-Something -Defaults @{ 'Switch1': 'True' } -Switch1:$false
            will invoke
            Do-Something

        .OUTPUTS
        Value from invoked cmdlet

        .PARAMETER CmdletName
        Name of cmdlet to invoke

        .PARAMETER Defaults
        Hashtable with parameters or path to a file which contains JSON dictionary

        .EXAMPLE
        Invoke-CmdletWithDefaults -Cmdlet Test-Path -Defaults .\defaults.json

        defaults.json contents:
        {
            'Path': 'c:\Windows'
        }

        .EXAMPLE
        Invoke-CmdletWithDefaults -Cmdlet Test-Path -Defaults @{ Path='c:\asdsad' } '-Verbose'
        Passing default argument to invoked function
    #>

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, HelpMessage = 'Name of Cmdlet to execute')]
        [ValidateScript({ Get-Command -Name $_ -ErrorAction Stop })]
        $CmdletName,

        [Parameter(Mandatory = $true, HelpMessage = 'Hashtable of defaults or path to JSON file with them')]
        [ValidateScript({ ($_ -is [HashTable]) -or (Test-Path -Path $_ -PathType Leaf) })]
        $Defaults,

        [Parameter(ValueFromRemainingArguments = $true)]
        $ArgumentList = @()
    )

    $Defaults = Get-Defaults $Defaults

    $cmdlet = Get-Command -Name $CmdletName
    $parameters = $cmdlet | Select-Object -ExpandProperty Parameters
    $flagNames = $parameters.Keys | ?{  $parameters[$_].SwitchParameter }

    # Override values from defaults by OverridedArguments

    $argumentName = $null
    $ArgumentList | %{
        $isName = $_ -is [String] -and $_[0] -eq '-'

        If ($isName) {
            $argumentName = $_.Split(':')[0].TrimStart('-')
            $flagValue = $_.Split(':')[1]

            If ($flagValue) {                
                $Defaults[$argumentName] = $flagValue
                $argumentName = $null
            } Else {
                $Defaults[$argumentName] = $null
            }            
        } Else {
            If (-not $argumentName) { throw "Value '$_' belongs to no argument" }

            $Defaults[$argumentName] = $_
            $argumentName = $null
        }
    }

    # Check what arguments cmdlet has
    $expression = "$CmdletName "
    $Defaults.Keys | ?{ $parameters.Keys -icontains $_ } | %{
        $value = $Defaults[$_]

        If ($flagNames -icontains $_) {
            If ($value -eq $null -or $value -eq $true -or $value -eq $true.ToString() -or $value -eq '$true') {
                $expression += "-$_ "
            }
        } Else {
            $expression += "-$_ `$Defaults['$_']"
        }
    }
    $Defaults.Keys | ?{ $parameters.Keys -inotcontains $_ } | %{ Write-Verbose "Parameter '-$_' skipped as it does't belong to $Cmdlet cmdlet" }

    Write-Verbose "Executing following expression: $expression"

    &( [scriptblock]::Create($expression) )
}

Function Invoke-ApplicationWithDefaults {
    <#
        .SYNOPSIS
        Invokes application replacing arguments with values from Hashtable or JSON file

        .DESCRIPTION
        You can start any application providing values from Hashtable or JSON file in arguments.

        Here is basic example how invocation can look like:
        Invoke-ApplicationWithDefaults -Defaults @{ "IP"='127.0.0.1' } ping %IP% -n 1

        It can also be used to invoke cmdlets.
        
        .OUTPUTS
        String
        STDOUT of started application or command line if -WhatIf is present

        .PARAMETER Application
        Name, absolute or relative path of application to start

        .PARAMETER Defaults
        Hashtable with parameters or path to a file which contains JSON dictionary

        .PARAMETER Defaults
        Ignores placeholders with no values in Defaults

        .EXAMPLE
        Invoke-ApplicationWithDefaults -Defaults defaults.json ping %IP%
        
        Will invoke: 
        ping 127.0.0.1

        defaults.json contents:
        {
            'IP': '127.0.0.1'
        }

        .EXAMPLE
        Invoke-ApplicationWithDefaults -Defaults @{ 'domain'='bing.com'; 'port'=80 } Invoke-WebRequest 'http://%domain%:%port%'
        
        Will invoke: 
        Invoke-WebRequest http://bing.com:80
        
        .EXAMPLE
        Invoke-ApplicationWithDefaults -Defaults defaults.json ping %IP% -n '%number of attempts%'

        Will invoke:
        ping 127.0.0.1 -n 5

        defaults.json contents:
        {
            'IP': '127.0.0.1'
            'number of attempts': 5
        }        
    #>
    [CmdletBinding(SupportsShouldProcess=$true, PositionalBinding=$False)]
    Param(
        [Parameter(Mandatory = $true, HelpMessage = 'Hashtable of defaults or path to JSON file with them')]
        [ValidateScript({ ($_ -is [HashTable]) -or (Test-Path -Path $_ -PathType Leaf) })]
        $Defaults,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $Application,  
        
        [ValidateSet('AutoDetect', 'PercentWrapped', 'FigureWrapped', 'MSBuild')]
        $PlaceholderStyle = 'AutoDetect',      

        [switch]
        $IgnoreMissing,

        [Parameter(ValueFromRemainingArguments = $true)]
        $ArgumentList = @()
    )

    $Defaults = Get-Defaults $Defaults   
    
    $ArgumentList = $ArgumentList | %{
        $argument = $_
        
        $argument = Update-WithDefaults -Text $argument -Defaults $Defaults -PlaceholderStyle $PlaceholderStyle -IgnoreMissing:$IgnoreMissing        
        
        # escaping internal quotes
        $argument = $argument -replace '"', '""'

        # adding wrapping quotes if needed
        If ($argument -match ' ') {
            $argument = """$argument"""
        }

        $argument
    }

    $commandLine = ". $Application " + [string]::Join(' ', $ArgumentList)
    If ($WhatIfPreference) {
        $commandLine
    } Else {
        Write-Verbose $commandLine
        Invoke-Expression -Command $commandLine
    }
}

Function Set-DefaultsToTemplateInternal {
    [CmdletBinding(SupportsShouldProcess=$true)]
    Param (
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        $TemplatePath,

        [ValidateScript({ ($_ -is [HashTable]) -or (Test-Path -Path $_ -PathType Leaf) })]
        $Defaults,

        [Switch]
        $IgnoreMissing,

        [Switch]
        $Force,

        [ValidateSet('AutoDetect', 'PercentWrapped', 'FigureWrapped', 'MSBuild')]
        $PlaceholderStyle = 'AutoDetect'
    ) 

    $DefaultsFile = $Defaults

    $Defaults = Get-Defaults $Defaults

    If ($DefaultsFile -isnot [HashTable] -and $Defaults -notcontains 'defaults') {            
        $Defaults['defaults'] = [System.IO.Path]::GetFileNameWithoutExtension($DefaultsFile)
        Write-Verbose "Adding 'defaults'='$($Defaults['defaults'])' to `$Defaults"
    }
    $ResultPath = $TemplatePath -ireplace '\.template$', ''   

    $ResultPath = Update-WithDefaults -Text $ResultPath -Defaults $Defaults -PlaceholderStyle $PlaceholderStyle -IgnoreMissing:$IgnoreMissing.IsPresent
    Write-Verbose "ResultPath will be '$ResultPath'"    
    
    $text = [System.IO.File]::ReadAllText($TemplatePath)

    $replaced = Update-WithDefaults -Text $text -Defaults $Defaults -PlaceholderStyle $PlaceholderStyle -IgnoreMissing:$IgnoreMissing.IsPresent
    
    If ($ResultPath -ieq $TemplatePath) {
        throw "ResultPath can't be same as TemplatePath, even with -Force flag '$ResultPath'"
    }
    If (-not $Force.IsPresent -and ( Test-Path -Path $ResultPath )) {
        throw "`$ResultPath already exists, use -Force flag to overwrite it: '$ResultPath'"        
    }

    If (-not $WhatIfPreference) {
        Write-Verbose "`$ResultPath already exists, overwriting: '$ResultPath'"
        Set-Content -Path $ResultPath -Value $replaced -Force
    } Else {
        New-Object PSCustomObject -Property @{ 'ResultPath' = $ResultPath; 'Content' = $replaced }
    }
}

Function Set-DefaultsToTemplate {
    <#
        .SYNOPSIS
        Creates file replacing placeholders with values from Hashtable or JSON file
        
        .DESCRIPTION
        Creates file from template file and defaults.

        Placeholders in resulting file content and name will by values in Defaults.

        If $ResultPath is absent, then template file name will be used without '.template' extension.

        If $ResultPath contains placeholders they will be also replced.

        If Defaults is a path to a JSON file, then it's name without extension will be also available by name 'defaultsName'.        
        For example:
            Set-DefaultsToTemplate -TemplatePath %defaultsName%-service.xml.template -Defaults myservice-prod.json
        Will save result to: 'myservice-prod-service.xml'.        

        To get help about placeholders and their styles run:
        Get-Help Update-WithDefaults        
        
        .OUTPUTS
        String
        $ResultPath eventually used
        
        If -WhatIf switch is presents returns hashtable with target path and content

        .PARAMETER TemplatePath
        Relative or absolute path to template file
        
        .PARAMETER Defaults
        Hashtable with parameters or path to a file which contains JSON dictionary

        .PARAMETER PlaceholderStyle
        Style of placeholders

        .PARAMETER IgnoreMissing
        Use this switch, if you wan't to ignore missing
    #>

    [CmdletBinding(SupportsShouldProcess=$true)]
    Param (
        $TemplatePath,

        $Defaults,

        [Switch]
        $IgnoreMissing,

        [Switch]
        $Force,

        [ValidateSet('AutoDetect', 'PercentWrapped', 'FigureWrapped', 'MSBuild')]
        $PlaceholderStyle = 'AutoDetect'
    )

    #return Set-DefaultsToTemplateInternal -TemplatePath $TemplatePath -Defaults $Defaults -ResultPath $ResultPath -IgnoreMissing:$IgnoreMissing -Force:$Force -PlaceholderStyle $PlaceholderStyle

    $templates = FromFileOrMask -FileOrMaskOrObject $TemplatePath -DefaultMask *.template
    
    $defaultCollections = FromFileOrMask -FileOrMaskOrObject $Defaults -DefaultMask *.json
    
    $templates | %{
        $template = $_

        $defaultCollections | %{
            $anotherDefaults = $_

            Set-DefaultsToTemplateInternal -TemplatePath $template -Defaults $anotherDefaults -IgnoreMissing:$IgnoreMissing -Force:$Force -PlaceholderStyle $PlaceholderStyle
        }
    }
}

Export-ModuleMember -Function Update-WithDefaults, Invoke-CmdletWithDefaults, Invoke-ApplicationWithDefaults, Set-DefaultsToTemplate