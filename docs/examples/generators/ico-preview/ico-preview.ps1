param([string]$InPath, [string]$OutPath)

$exe = Join-Path $env:USERPROFILE '.netpng\bin\ico2png.exe'
$psi = New-Object System.Diagnostics.ProcessStartInfo $exe
$psi.Arguments = '-q "' + $InPath + '"'
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.CreateNoWindow = $true

$p = [System.Diagnostics.Process]::Start($psi)
$fs = [System.IO.File]::Create($OutPath)
try {
  $p.StandardOutput.BaseStream.CopyTo($fs)
} finally {
  $fs.Close()
}
$p.WaitForExit()
exit $p.ExitCode
