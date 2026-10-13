param([string]$FontPath)
. "$PSScriptRoot\font-preview-lib.ps1"

$blocks = Get-FontBlocks $FontPath
Write-Output $blocks.Count
