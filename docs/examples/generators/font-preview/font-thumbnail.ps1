param([string]$FontPath, [string]$OutPath)
. "$PSScriptRoot\font-preview-lib.ps1"

$sample = Get-ThumbnailSample $FontPath

$pfc = New-Object System.Drawing.Text.PrivateFontCollection
$pfc.AddFontFile($FontPath)
$family = $pfc.Families[0]

$bmp = New-Object System.Drawing.Bitmap(400, 400)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::White)
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
$font = New-Object System.Drawing.Font($family, 160, [System.Drawing.FontStyle]::Regular)
$size = $g.MeasureString($sample, $font)
$x = (400 - $size.Width) / 2
$y = (400 - $size.Height) / 2
$g.DrawString($sample, $font, [System.Drawing.Brushes]::Black, $x, $y)
$bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
