#!/bin/bash

export VERSION_NUMBER=0.5.0

# edit main.zig version number commit and push
git add src/main.zig
git commit -m "release: v${VERSION_NUMBER}"
git push

# tag and push (triggers ci build of the cli for mac and linux in releases)
git tag v${VERSION_NUMBER}
git push --tags


# wait for CI, then update homebrew with the new shas from the releases
# get the shas with these commands or off the releases/latest page in github
curl -sL https://github.com/nathanjmorton/zigtsc/releases/download/v${VERSION_NUMBER}/zigtsc-aarch64-macos.tar.gz | shasum -a 256
curl -sL https://github.com/nathanjmorton/zigtsc/releases/download/v${VERSION_NUMBER}/zigtsc-x86_64-macos.tar.gz | shasum -a 256
curl -sL https://github.com/nathanjmorton/zigtsc/releases/download/v${VERSION_NUMBER}/zigtsc-aarch64-linux-gnu.tar.gz | shasum -a 256
curl -sL https://github.com/nathanjmorton/zigtsc/releases/download/v${VERSION_NUMBER}/zigtsc-x86_64-linux-gnu.tar.gz | shasum -a 256

# update the homebrew formula with the new shas commit and push
cd /opt/homebrew/Library/Taps/nathanjmorton/homebrew-zigtsc
# Edit Formula/zigtsc.rb: change version to "${VERSION_NUMBER}" and update each sha256
git add Formula/zigtsc.rb
git commit -m "zigtsc ${VERSION_NUMBER}"
git push

# verify
zigtsc upgrade
# Upgrading zigtsc v0.4.0 → v0.5.0
# zigtsc is installed via Homebrew (/opt/homebrew/bin/zigtsc).
# Use 'brew upgrade zigtsc' instead of 'zigtsc upgrade'.