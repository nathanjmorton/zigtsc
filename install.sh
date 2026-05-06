#!/usr/bin/env bash
set -euo pipefail

# zigtsc installer
# Usage:
# curl -fsSL https://raw.githubusercontent.com/nathanjmorton/zigtsc/main/install.sh | bash
# curl -fsSL https://raw.githubusercontent.com/nathanjmorton/zigtsc/main/install.sh | bash -s v0.1.0

platform=$(uname -ms)

# ── Colors ────────────────────────────────────────────────────────────────────

Color_Off=''
Red=''
Green=''
Dim=''
Bold_White=''
Bold_Green=''

if [[ -t 1 ]]; then
  Color_Off='\033[0m'
  Red='\033[0;31m'
  Green='\033[0;32m'
  Dim='\033[0;2m'
  Bold_Green='\033[1;32m'
  Bold_White='\033[1m'
fi

error() {
  echo -e "${Red}error${Color_Off}:" "$@" >&2
  exit 1
}

info() {
  echo -e "${Dim}$@ ${Color_Off}"
}

info_bold() {
  echo -e "${Bold_White}$@ ${Color_Off}"
}

success() {
  echo -e "${Green}$@ ${Color_Off}"
}

# ── Platform detection ────────────────────────────────────────────────────────

case $platform in
'Darwin x86_64')
  target=x86_64-macos
  ;;
'Darwin arm64')
  target=aarch64-macos
  ;;
'Linux aarch64' | 'Linux arm64')
  target=aarch64-linux-gnu
  ;;
'Linux x86_64')
  target=x86_64-linux-gnu
  ;;
*)
  error "Unsupported platform: $platform. zigtsc supports macOS (x86_64, arm64) and Linux (x86_64, aarch64)."
  ;;
esac

# Rosetta detection on macOS
if [[ $target = x86_64-macos ]]; then
  if [[ $(sysctl -n sysctl.proc_translated 2>/dev/null) = 1 ]]; then
    target=aarch64-macos
    info "Your shell is running in Rosetta 2. Downloading zigtsc for aarch64-macos instead."
  fi
fi

# ── Download ──────────────────────────────────────────────────────────────────

GITHUB=${GITHUB-"https://github.com"}
github_repo="$GITHUB/nathanjmorton/zigtsc"

if [[ $# = 0 ]]; then
  zigtsc_uri=$github_repo/releases/latest/download/zigtsc-$target.tar.gz
else
  zigtsc_uri=$github_repo/releases/download/$1/zigtsc-$target.tar.gz
fi

install_env=ZIGTSC_INSTALL
bin_env=\$$install_env/bin

install_dir=${!install_env:-$HOME/.zigtsc}
bin_dir=$install_dir/bin
exe=$bin_dir/zigtsc

if [[ ! -d $bin_dir ]]; then
  mkdir -p "$bin_dir" ||
    error "Failed to create install directory \"$bin_dir\""
fi

curl --fail --location --progress-bar --output "$exe.tar.gz" "$zigtsc_uri" ||
  error "Failed to download zigtsc from \"$zigtsc_uri\""

tar -xzf "$exe.tar.gz" -C "$bin_dir" ||
  error 'Failed to extract zigtsc'

chmod +x "$exe" ||
  error 'Failed to set permissions on zigtsc executable'

rm "$exe.tar.gz"

# ── Success ───────────────────────────────────────────────────────────────────

tildify() {
  if [[ $1 = $HOME/* ]]; then
    local replacement=\~/
    echo "${1/$HOME\//$replacement}"
  else
    echo "$1"
  fi
}

success "zigtsc was installed successfully to $Bold_Green$(tildify "$exe")"

if command -v zigtsc >/dev/null; then
  echo "Run 'zigtsc --help' to get started"
  exit
fi

refresh_command=''

tilde_bin_dir=$(tildify "$bin_dir")
quoted_install_dir=\"${install_dir//\"/\\\"}\"

if [[ $quoted_install_dir = \"$HOME/* ]]; then
  quoted_install_dir=${quoted_install_dir/$HOME\//\$HOME/}
fi

echo

case $(basename "$SHELL") in
fish)
  commands=(
    "set --export $install_env $quoted_install_dir"
    "set --export PATH $bin_env \$PATH"
  )

  fish_config=$HOME/.config/fish/config.fish
  tilde_fish_config=$(tildify "$fish_config")

  if [[ -w $fish_config ]]; then
    {
      echo -e '\n# zigtsc'
      for command in "${commands[@]}"; do
        echo "$command"
      done
    } >>"$fish_config"

    info "Added \"$tilde_bin_dir\" to \$PATH in \"$tilde_fish_config\""
    refresh_command="source $tilde_fish_config"
  else
    echo "Manually add the directory to $tilde_fish_config (or similar):"
    for command in "${commands[@]}"; do
      info_bold "  $command"
    done
  fi
  ;;
zsh)
  commands=(
    "export $install_env=$quoted_install_dir"
    "export PATH=\"$bin_env:\$PATH\""
  )

  zsh_config=$HOME/.zshrc
  tilde_zsh_config=$(tildify "$zsh_config")

  if [[ -w $zsh_config ]]; then
    {
      echo -e '\n# zigtsc'
      for command in "${commands[@]}"; do
        echo "$command"
      done
    } >>"$zsh_config"

    info "Added \"$tilde_bin_dir\" to \$PATH in \"$tilde_zsh_config\""
    refresh_command="exec $SHELL"
  else
    echo "Manually add the directory to $tilde_zsh_config (or similar):"
    for command in "${commands[@]}"; do
      info_bold "  $command"
    done
  fi
  ;;
bash)
  commands=(
    "export $install_env=$quoted_install_dir"
    "export PATH=\"$bin_env:\$PATH\""
  )

  bash_configs=(
    "$HOME/.bash_profile"
    "$HOME/.bashrc"
  )

  if [[ ${XDG_CONFIG_HOME:-} ]]; then
    bash_configs+=(
      "$XDG_CONFIG_HOME/.bash_profile"
      "$XDG_CONFIG_HOME/.bashrc"
      "$XDG_CONFIG_HOME/bash_profile"
      "$XDG_CONFIG_HOME/bashrc"
    )
  fi

  set_manually=true
  for bash_config in "${bash_configs[@]}"; do
    tilde_bash_config=$(tildify "$bash_config")

    if [[ -w $bash_config ]]; then
      {
        echo -e '\n# zigtsc'
        for command in "${commands[@]}"; do
          echo "$command"
        done
      } >>"$bash_config"

      info "Added \"$tilde_bin_dir\" to \$PATH in \"$tilde_bash_config\""
      refresh_command="source $bash_config"
      set_manually=false
      break
    fi
  done

  if [[ $set_manually = true ]]; then
    echo "Manually add the directory to ~/.bashrc (or similar):"
    for command in "${commands[@]}"; do
      info_bold "  $command"
    done
  fi
  ;;
*)
  echo 'Manually add the directory to ~/.bashrc (or similar):'
  info_bold "  export $install_env=$quoted_install_dir"
  info_bold "  export PATH=\"$bin_env:\$PATH\""
  ;;
esac

echo
info "To get started, run:"
echo

if [[ $refresh_command ]]; then
  info_bold "  $refresh_command"
fi

info_bold "  zigtsc --help"
