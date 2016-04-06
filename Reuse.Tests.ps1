Import-Module -Name ( Join-Path -Path $PSScriptRoot -ChildPath 'Reuse\Reuse.psm1' ) -Force

InModuleScope Reuse {

    Describe "Set-DefaultsToTemplate" {
        $defaults = @{ 
            'arg'='1';
            'arg2'='2';
        }
        $defaults2 = @{ 
            'arg'='1b';
            'arg2'='2b';
        }

        $templateText = 'test %arg%'
        $templateText2 = 'test %arg% %arg2%'

        $testFolder =                  Join-Path -Path $env:TEMP   -ChildPath Set-DefaultsToTemplate
        $defaultsFile =                Join-Path -Path $testFolder -ChildPath 'defaults.json'
        $defaultsFile2 =               Join-Path -Path $testFolder -ChildPath 'defaults2.json'
        $templateFile =                Join-Path -Path $testFolder -ChildPath 'result.xml.template'
        $templateFile2 =               Join-Path -Path $testFolder -ChildPath 'result2.xml.template'
        $templateFileWithPlaceholder = Join-Path -Path $testFolder -ChildPath '%defaults%-result.xml.template'

        Remove-Item -Path $testFolder -Force -Recurse -ErrorAction SilentlyContinue
        New-Item -Path $testFolder -ItemType Directory
        [System.IO.File]::WriteAllText($defaultsFile, ($defaults | ConvertTo-Json))
        [System.IO.File]::WriteAllText($defaultsFile2, ($defaults2 | ConvertTo-Json))
        [System.IO.File]::WriteAllText($templateFile, $templateText)
        [System.IO.File]::WriteAllText($templateFile2, $templateText2)     
        [System.IO.File]::WriteAllText($templateFileWithPlaceholder, $templateText)

        # Structure of test files:
        #
        # \ Set-DefaultsToTemplate
        #      \ defaults.json                      : @{ 'arg'='1'; 'arg2'='2'; }
        #      \ defaults2.json                     : @{ 'arg'='1b'; 'arg2'='2b'; }
        #      \ result.xml.template                : test %arg%
        #      \ result2.xml.template               : test %arg% %arg2%
        #      \ %defaults%-result.xml.template : test %arg%

        Context 'Simple' {
            It "Default style" {
                $result = Set-DefaultsToTemplate -TemplatePath $templateFile -Defaults $defaultsFile -WhatIf
            }        
        }
        Context 'Multiple' {
            It "Default style" {
                Push-Location -Path $testFolder
                Try {
                    $result = Set-DefaultsToTemplate -Defaults $defaultsFile -WhatIf
                    $resultWithPlaceholder = $templateFileWithPlaceholder.Replace('.template', '').Replace('%defaults%', 'defaults')
                    $result | ?{ $_.ResultPath -eq $resultWithPlaceholder } | %{ $_.Content } | Should Be 'test 1'
                    $result | ?{ $_.ResultPath -eq $templateFile.Replace('.template', '') } | %{ $_.Content } | Should Be 'test 1'
                    $result | ?{ $_.ResultPath -eq $templateFile2.Replace('.template', '') } | %{ $_.Content } | Should Be 'test 1 2'
                } Finally {
                    Pop-Location
                }
            }        
        }

        Context 'FromFileOrMask' {
            It "File" {
                FromFileOrMask -FileOrMaskOrObject $defaultsFile | Should Be @( $defaultsFile )
            }
            It "File and default mask" {
                FromFileOrMask -FileOrMaskOrObject $defaultsFile -DefaultMask *.txt | Should Be @( $defaultsFile )
            }
            It "Mask" {
                $result = FromFileOrMask -Folder $testFolder -FileOrMaskOrObject *.json
                $result[0] | Should Be $defaultsFile
                $result[1] | Should Be $defaultsFile2
            }
            It "Null and default mask" {
                $result = FromFileOrMask -Folder $testFolder -DefaultMask *.json
                $result[0] | Should Be $defaultsFile
                $result[1] | Should Be $defaultsFile2
            }
            It "Object" {
                $result = FromFileOrMask -Folder $testFolder -FileOrMaskOrObject 1 | Should Be 1
            }
            It "Not found" {
                { FromFileOrMask -Folder $testFolder -FileOrMaskOrObject *.not-exist-for-sure } | Should Throw "File/s '*.not-exist-for-sure' not found in '$($testFolder)'"
                { FromFileOrMask -Folder $testFolder -DefaultMask *.not-exist-for-sure } | Should Throw "File/s '*.not-exist-for-sure' not found in '$($testFolder)'"
            }
        }    
    }

    Describe "FromFileOrMask" {
        Context 'FromFileOrMask' {
            
        }
    }

    Describe "Update-WithDefaults" {
        $defaults = @{ 
            'arg'='1';
            'arg2'='2';
        }
        Context 'Different placeholder styles' {
            It "Default style" {
                Update-WithDefaults -Text 'test %arg%' -Defaults $defaults | Should Be 'test 1'
            }
            It "Procents" {
                Update-WithDefaults -Text 'test %arg% %arg2%' -Defaults $defaults -PlaceholderStyle PercentWrapped | Should Be 'test 1 2'
            }
            It "Figure" {
                Update-WithDefaults -Text 'test {arg} {arg2}' -Defaults $defaults -PlaceholderStyle FigureWrapped | Should Be 'test 1 2'
            }
            It "MSBuild" {
                Update-WithDefaults -Text 'test $(arg) $(arg2)' -Defaults $defaults -PlaceholderStyle MSBuild | Should Be 'test 1 2'
            }
        }
        Context 'Missing' {
            It "Default missing" {
                { Update-WithDefaults -Text 'test %arg-missing%' -Defaults $defaults -PlaceholderStyle PercentWrapped } | Should Throw
            }
            It "Default missing but ignored" {
                Update-WithDefaults -Text 'test %arg% %arg-missing%' -Defaults $defaults -IgnoreMissing | Should Be 'test 1 %arg-missing%'
            }
        }
        Context 'List only' {
            It "One" {
                Update-WithDefaults -Text 'test %arg%' -Defaults $defaults -ListOnly | Should Be @("arg")
            }
            It "Zero" {
                Update-WithDefaults -Text 'test' -Defaults $defaults -ListOnly | Should Be $null
            }
            It "One and ignore" {
                Update-WithDefaults -Text 'test %arg% %arg-missing%' -Defaults $defaults -IgnoreMissing -ListOnly | Should Be @("arg")
            }
        }
    }

    Describe "Invoke-CmdletWithDefaults" {
        Function global:MyFunc ($Arg1, $Arg2, [switch]$Switch) {
            $Arg1, $Arg2, $Switch.IsPresent
        }

        Context 'Testing defaults with hashtable' {
            It "One default argument" {
                $result = Invoke-CmdletWithDefaults -CmdletName MyFunc -Defaults @{ 'Arg1'=1 }
                $result[0] | Should Be 1
                $result[1] | Should Be $null
                $result[2] | Should Be $false
            }
            It "Two default arguments" {
                $result = Invoke-CmdletWithDefaults -CmdletName MyFunc -Defaults @{ 'Arg1'=1; 'Arg2'=2 }
                $result[0] | Should Be 1
                $result[1] | Should Be 2
                $result[2] | Should Be $false
            }
            It "One default argument and switch as bool" {
                $result = Invoke-CmdletWithDefaults -CmdletName MyFunc -Defaults @{ 'Arg1'=1; 'Switch'=$true }
                $result[0] | Should Be 1
                $result[1] | Should Be $null
                $result[2] | Should Be $true
            }
            It "One default argument and switch as string" {
                $result = Invoke-CmdletWithDefaults -CmdletName MyFunc -Defaults @{ 'Arg1'=1; 'Switch'='True' }
                $result[0] | Should Be 1
                $result[1] | Should Be $null
                $result[2] | Should Be $true
            }

            It "One default argument and switch as string" {
                $result = Invoke-CmdletWithDefaults -CmdletName MyFunc -Defaults @{ 'Arg1'=1; 'Switch'='False' }
                $result[0] | Should Be 1
                $result[1] | Should Be $null
                $result[2] | Should Be $false
            }
        }

        Context 'Testing defaults and override' {
            It "One default argument" {
                $result = Invoke-CmdletWithDefaults -CmdletName MyFunc -Defaults @{ 'Arg1'=1 } -Arg1 2
                $result[0] | Should Be 2
                $result[1] | Should Be $null
                $result[2] | Should Be $false
            }
            It "Two default arguments" {
                $result = Invoke-CmdletWithDefaults -CmdletName MyFunc -Defaults @{ 'Arg1'=1; 'Arg2'=2 } -Arg2 3
                $result[0] | Should Be 1
                $result[1] | Should Be 3
                $result[2] | Should Be $false
            }
            It "One default argument and switch in override" {
                $result = Invoke-CmdletWithDefaults -CmdletName MyFunc -Defaults @{ 'Arg1'=1; } -Switch
                $result[0] | Should Be 1
                $result[1] | Should Be $null
                $result[2] | Should Be $true
            }        
        }

        Context 'Testing defaults with file' {
            $file = [System.IO.Path]::GetTempFileName()        

            It "One default argument" {
                Set-Content -Path $file -Value ( @{ 'Arg1'=1 } | ConvertTo-Json )
                $result = Invoke-CmdletWithDefaults -CmdletName MyFunc -Defaults $file -Arg1 2
                $result[0] | Should Be 2
                $result[1] | Should Be $null
                $result[2] | Should Be $false
            }
            It "Two default arguments" {
                Set-Content -Path $file -Value ( @{ 'Arg1'=1; 'Arg2'=2 } | ConvertTo-Json )
                $result = Invoke-CmdletWithDefaults -CmdletName MyFunc -Defaults $file -Arg2 3
                $result[0] | Should Be 1
                $result[1] | Should Be 3
                $result[2] | Should Be $false
            }
            It "One default argument and switch in override" {
                Set-Content -Path $file -Value ( @{ 'Arg1'=1; } | ConvertTo-Json )
                $result = Invoke-CmdletWithDefaults -CmdletName MyFunc -Defaults $file -Switch
                $result[0] | Should Be 1
                $result[1] | Should Be $null
                $result[2] | Should Be $true
            }
            It "One default argument and switch overriden" {
                Set-Content -Path $file -Value ( @{ 'Arg1'=1; 'Switch'='True' } | ConvertTo-Json )
                $result = Invoke-CmdletWithDefaults -CmdletName MyFunc -Defaults $file -Switch:$false
                $result[0] | Should Be 1
                $result[1] | Should Be $null
                $result[2] | Should Be $false
            }

            It "One default argument and switch overriden" {
                Set-Content -Path $file -Value ( @{ 'Arg1'=1; 'Switch'='False' } | ConvertTo-Json )
                $result = Invoke-CmdletWithDefaults -CmdletName MyFunc -Defaults $file -Switch:$false
                $result[0] | Should Be 1
                $result[1] | Should Be $null
                $result[2] | Should Be $false
            }
        }

        Context 'Extended flag checks' {
            It "One default argument and switch overriden" {
                $result = Invoke-CmdletWithDefaults -CmdletName MyFunc -Defaults @{ 'Arg1'=1; 'Switch'='True' } -Switch:$false
                $result[0] | Should Be 1
                $result[1] | Should Be $null
                $result[2] | Should Be $false
            }

            It "One default argument and switch overriden" {
                $result = Invoke-CmdletWithDefaults -CmdletName MyFunc -Defaults @{ 'Arg1'=1; 'Switch'='False' } -Switch:$false
                $result[0] | Should Be 1
                $result[1] | Should Be $null
                $result[2] | Should Be $false
            }
        }
    }

}
