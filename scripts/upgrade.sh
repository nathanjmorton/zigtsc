#!/usr/bin/env bash
set -euo pipefail

# zigtsc upgrade — self-update to the latest release
# Called by `zigtsc upgrade`

Color_Off='' Red='' Green='' Dim='' Bold_White=''
if [[ -t 1 ]]; then
  Color_Off='\033[0m'; Red='\033[0;31m'; Green='\033[0;32m'
  Dim='\033[0;2m'; Bold_White='\033[1m'
fi

error() { echo -e "${Red}error${Color_Off}: $*" >&2; exit 1; }
info() { echo -e "${Dim}$*${Color_Off}"; }
success() { echo -e "${Green}$*${Color_Off}"; }

# Detect Homebrew install
exe=$(command -v zigtsc 2>/dev/null || true)
if [[ -z "$exe" ]]; then
  error "zigtsc not found on PATH"
fi

if [[ "$exe" == /opt/homebrew/* ]] || [[ "$exe" == /usr/local/* ]]; then
  echo "zigtsc was installed via Homebrew."
  echo ""
  echo -e "${Bold_White}  brew upgrade zigtsc${Color_Off}"
  echo ""
  exit 0
fi

# Platform detection
platform=$(uname -ms)
case $platform in
  'Darwin x86_64')  target=x86_64-macos ;;
  'Darwin arm64')   target=aarch64-macos ;;
  'Linux aarch64' | 'Linux arm64') target=aarch64-linux-gnu ;;
  'Linux x86_64')   target=x86_64-linux-gnu ;;
  *) error "Unsupported platform: $platform" ;;
esac

# Rosetta
if [[ $target = x86_64-macos ]]; then
  if [[ $(sysctl -n sysctl.proc_translated 2>/dev/null) = 1 ]]; then
    target=aarch64-macos
  fi
fi

GITHUB=${GITHUB-"https://github.com"}
uri="$GITHUB/nathanjmorton/zigtsc/releases/latest/download/zigtsc-$target.tar.gz"
bin_dir=$(dirname "$exe")

info "Downloading zigtsc-$target..."
curl --fail --location --progress-bar --output "$exe.tar.gz" "$uri" ||
  error "Failed to download from $uri"

tar -xzf "$exe.tar.gz" -C "$bin_dir" ||
  error "Failed to extract"

chmod +x "$exe"
rm "$exe.tar.gz"

success "zigtsc upgraded successfully"
