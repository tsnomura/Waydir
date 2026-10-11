#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

case "$(uname -s)" in
  Darwin) platform=macos ;;
  *) platform=linux ;;
esac

flutter build "$platform" --release \
  "--dart-define=WAYDIR_PERSONAL_VERSION=$(git describe --tags --always --dirty)" \
  "--dart-define=WAYDIR_PERSONAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)" \
  "--dart-define=WAYDIR_PERSONAL_COMMIT=$(git rev-parse HEAD)" \
  "--dart-define=WAYDIR_PERSONAL_BUILD_DATE=$(date +%Y-%m-%d)" \
  "$@"
