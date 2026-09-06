@{
    RootModule        = 'Nautilus.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '7f3c2a18-9b2e-4a71-8c55-3d2f1e0a9b8c'
    Author            = 'Alex Shen'
    CompanyName       = '_alex.shen'
    Copyright         = '(c) Alex Shen. All rights reserved.'
    Description       = 'Nautilus - a pure-PowerShell futuristic TUI AI assistant (JARVIS-style, Gemini-powered).'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('nautilus')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('naut')
    PrivateData       = @{
        PSData = @{
            Tags       = @('AI','TUI','Gemini','JARVIS','Assistant','SciFi')
            ProjectUri = 'https://github.com/alex-ckshen/nautilus'
            LicenseUri = 'https://github.com/alex-ckshen/nautilus'
        }
    }
}
