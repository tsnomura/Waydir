param([string]$FontPath, [string]$Position, [string]$OutPath)
. "$PSScriptRoot\font-preview-lib.ps1"

$blocks = Get-FontBlocks $FontPath
$idx = [Math]::Max(0, [Math]::Min([int]$Position, $blocks.Count - 1))
$block = $blocks[$idx]

$pfc = New-Object System.Drawing.Text.PrivateFontCollection
$pfc.AddFontFile($FontPath)
$family = $pfc.Families[0]

$bmp = New-Object System.Drawing.Bitmap(900, 360)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::White)
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
$sampleFont = New-Object System.Drawing.Font($family, $block.Size, [System.Drawing.FontStyle]::Regular)
$g.DrawString($block.Text, $sampleFont, [System.Drawing.Brushes]::Black, 20, 20)
$labelFont = New-Object System.Drawing.Font('Segoe UI', 14)
$g.DrawString($family.Name, $labelFont, [System.Drawing.Brushes]::Gray, 20, 320)
$bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
