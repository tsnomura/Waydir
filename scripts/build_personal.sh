#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

case "$(uname -s)" in
  Darwin) platform=macos ;;
  *) platform=linux ;;
esac

version="$(git describe --tags --always --dirty)"
branch="$(git rev-parse --abbrev-ref HEAD)"
date="$(date +%Y-%m-%d)"
export WAYDIR_PERSONAL_LABEL="$version, $branch, $date"

flutter build "$platform" --release \
  "--dart-define=WAYDIR_PERSONAL_VERSION=$version" \
  "--dart-define=WAYDIR_PERSONAL_BRANCH=$branch" \
  "--dart-define=WAYDIR_PERSONAL_COMMIT=$(git rev-parse HEAD)" \
  "--dart-define=WAYDIR_PERSONAL_BUILD_DATE=$date" \
  "$@"
