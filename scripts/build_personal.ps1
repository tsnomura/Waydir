$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  $version = (git describe --tags --always --dirty).Trim()
  $branch = (git rev-parse --abbrev-ref HEAD).Trim()
  $commit = (git rev-parse HEAD).Trim()
  $date = Get-Date -Format 'yyyy-MM-dd'
  flutter build windows --release `
    "--dart-define=WAYDIR_PERSONAL_VERSION=$version" `
    "--dart-define=WAYDIR_PERSONAL_BRANCH=$branch" `
    "--dart-define=WAYDIR_PERSONAL_COMMIT=$commit" `
    "--dart-define=WAYDIR_PERSONAL_BUILD_DATE=$date" `
    @args
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
