$ErrorActionPreference = 'Stop'
Add-Type -Path "$PSScriptRoot/Mono.Cecil.dll"
Add-Type -Path "$PSScriptRoot/RestoreDownload.cs" -ReferencedAssemblies "$PSScriptRoot/Mono.Cecil.dll"
try {
    [RestoreDownload]::Run("$PSScriptRoot/previous/Plain Craft Launcher 2.exe", "$PSScriptRoot/release/Plain Craft Launcher 2.exe", "$PSScriptRoot/../PCL-Download-Restored.exe")
} catch {
    Write-Output $_.Exception.ToString()
    exit 1
}
