#!/usr/bin/env bash
# Add hugo-eureka theme as a Git submodule so Hugo loads it from disk (no Go module fetch).
# Run from repo root: ./scripts/setup-theme.sh

set -e
cd "$(dirname "$0")/.."

if [ -d "themes/hugo-eureka" ]; then
  echo "Theme already at themes/hugo-eureka"
  exit 0
fi

git submodule add https://github.com/ZhangYet/hugo-eureka.git themes/hugo-eureka
cd themes/hugo-eureka && git checkout v0.9.3 && cd ../..
echo "Theme installed at themes/hugo-eureka. Run: hugo server"
