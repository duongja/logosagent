#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"

clone_repo() {
  local name="$1"
  local url="$2"
  local rev="$3"
  local submodules="${4:-false}"
  local dir="$WORKSPACE/$name"

  if [ ! -d "$dir/.git" ]; then
    git clone "$url" "$dir"
  fi

  git -C "$dir" fetch --tags --force origin "$rev"
  git -C "$dir" checkout --detach "$rev"

  if [ "$submodules" = "true" ]; then
    git -C "$dir" submodule update --init --recursive
  fi
}

configure_flake_paths() {
  local flake="$ROOT/flake.nix"
  local circuits_flake="$ROOT/nix/logos-blockchain-circuits-compat/flake.nix"
  local repos=(
    logos-module-builder logos-nix logos-cpp-sdk logos-module logos-plugin-qt
    nix-bundle-lgx logos-package nix-bundle-dir nix-bundle-appimage
    nix-bundle-logos-module-install logos-standalone-app logos-test-framework
    logos-liblogos process-stats logos-package-manager logos-design-system
    logos-capability-module logos-view-module-runtime logos-qt-mcp
    logos-execution-zone-module logos-storage-module logos-chat-module
    logos-delivery-module logos-execution-zone logos-storage-nim logos-chat
    logos-delivery rust-overlay crane flake-utils nix-systems-default
    logos-blockchain-circuits
  )

  for repo in "${repos[@]}"; do
    perl -0pi -e "s#path:(?:\\./)?\\.\\./$repo#path:$WORKSPACE/$repo#g" "$flake"
    perl -0pi -e "s#path:/[^\\\"]*/$repo#path:$WORKSPACE/$repo#g" "$flake" "$circuits_flake"
    perl -0pi -e "s#git\\+file:(?:\\./)?\\.\\./$repo#git+file://$WORKSPACE/$repo#g" "$flake"
    perl -0pi -e "s#git\\+file://[^\\\"?]*/$repo#git+file://$WORKSPACE/$repo#g" "$flake"
  done

  perl -0pi -e "s#path:(?:\\./)?\\.\\./\\.\\./\\.\\./logos-blockchain-circuits#path:$WORKSPACE/logos-blockchain-circuits#g" "$circuits_flake"
}

apply_if_missing() {
  local dir="$1"
  local marker="$2"
  local patch="$3"

  if grep -R -q "$marker" "$dir"; then
    return
  fi
  git -C "$dir" apply "$patch"
}

clone_repo logos-module-builder https://github.com/logos-co/logos-module-builder.git 2afd64405439d3fdda1ffb53852a9bb0049f0f0e
clone_repo logos-nix https://github.com/logos-co/logos-nix.git e637a1f5e871244d1c2df1e3c52a067f2eb406f2
clone_repo logos-cpp-sdk https://github.com/logos-co/logos-cpp-sdk.git eb71a1aa90e05a98814138779680de2ea60a9ff2
clone_repo logos-module https://github.com/logos-co/logos-module.git 780894dd40ebc8eded0fa97b1729286f31571cfb
clone_repo logos-plugin-qt https://github.com/logos-co/logos-plugin-qt.git f58fbaa25acbc547ae2671e2cddcc1517d6643f0
clone_repo nix-bundle-lgx https://github.com/logos-co/nix-bundle-lgx.git 3c44d99b9d8dbd8a135b44b5b328e6175650305e
clone_repo logos-package https://github.com/logos-co/logos-package.git d2c98d34cc3412d08f2fab23644c620a79b78477
clone_repo nix-bundle-dir https://github.com/logos-co/nix-bundle-dir.git 4937262f55cf8be942263255dd0801e3e3878bc9
clone_repo nix-bundle-appimage https://github.com/logos-co/nix-bundle-appimage.git 8fcc56b5afcc313ca917cf3487be082ae2f0184c
clone_repo nix-bundle-logos-module-install https://github.com/logos-co/nix-bundle-logos-module-install.git 89cc9ea91275396d589c767d76926459ac77ef20
clone_repo logos-standalone-app https://github.com/logos-co/logos-standalone-app.git f812b43f73f3c264ee0f8a8354f40721431d6846
clone_repo logos-test-framework https://github.com/logos-co/logos-test-framework.git ee081954096f602b47308c6dc7d00fb71d5dcdc7
clone_repo logos-liblogos https://github.com/logos-co/logos-liblogos.git 51313eb58f2566efaa6ece82071a34e3bc4f7f61
clone_repo process-stats https://github.com/logos-co/process-stats.git 33ace1270f90c89b3565e803139c0970fcd1ce8f
clone_repo logos-package-manager https://github.com/logos-co/logos-package-manager.git 2b4b72087154dd4d6f691ac2527e06e0dadaef4d
clone_repo logos-design-system https://github.com/logos-co/logos-design-system.git 379ae956cbfdd189cfe3397fa372d14976aa85c9
clone_repo logos-capability-module https://github.com/logos-co/logos-capability-module.git e675e9e3a98ee69bb303365c2c626f9237bc1ab5
clone_repo logos-view-module-runtime https://github.com/logos-co/logos-view-module-runtime.git 21dddc380eca36e7e865cf5a437f63e0e16f30d3
clone_repo logos-qt-mcp https://github.com/logos-co/logos-qt-mcp.git c5223b4b640add09e461983b8fddbd12c8b31f4f
clone_repo logos-execution-zone-module https://github.com/logos-blockchain/logos-execution-zone-module.git 5d42559db8634ec40742941d8c22aeaedb2c1955
clone_repo logos-storage-module https://github.com/logos-co/logos-storage-module.git b1d82a32c1ba27e20d07b7ed8555fd45b02adb4e
clone_repo logos-chat-module https://github.com/logos-co/logos-chat-module.git 9b22b5223a3220645015592b3c17ebc541f2898d
clone_repo logos-delivery-module https://github.com/logos-co/logos-delivery-module.git 9043408857ad1858f5bbbf3f82a6b57951f49bb7
clone_repo logos-execution-zone https://github.com/logos-blockchain/logos-execution-zone.git feb6cb7f92d9926411b1aa00486fe198bd05bf13
clone_repo logos-blockchain-circuits https://github.com/logos-blockchain/logos-blockchain-circuits.git 059bc01e17b3d09cacfbbc9ab587dbb2c1447eec
clone_repo logos-storage-nim https://github.com/logos-storage/logos-storage-nim.git d61512a5b7349332bd9684bf163ed17eee1135af true
clone_repo logos-chat https://github.com/logos-messaging/logos-chat.git 15f68f2ec2c83befd7c346c7ce5b2d0b49f9c00d true
clone_repo logos-delivery https://github.com/logos-messaging/logos-delivery.git 38d951a2fdcc2498f7193c5c3f9401f95f458eae true
clone_repo scaffold https://github.com/logos-co/scaffold.git ae8c0b9ceaaa75462cb3bf14e8584f3f7d8df893
clone_repo rust-overlay https://github.com/oxalica/rust-overlay.git 27b7e78c6935293ee868469cc4172e9b8b17823b
clone_repo crane https://github.com/ipetkov/crane.git 59a82a1222dd3b2080b5cc52a1a2e8d5f1b77f37
clone_repo flake-utils https://github.com/numtide/flake-utils.git 11707dc2f618dd54ca8739b309ec4fc024de578b
clone_repo nix-systems-default https://github.com/nix-systems/default.git da67096a3b9bf56a91d16901293e51ba5b49a27e

apply_if_missing "$WORKSPACE/logos-execution-zone" "cp lez/wallet-ffi/wallet_ffi.h" "$ROOT/patches/logos-execution-zone-ffi-build.patch"
apply_if_missing "$WORKSPACE/logos-execution-zone-module" "jsonToFfiRecipientIdentifier" "$ROOT/patches/logos-execution-zone-module-wallet-ffi.patch"
configure_flake_paths

echo "Workspace ready at $WORKSPACE"
