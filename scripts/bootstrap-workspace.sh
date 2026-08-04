#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="${LOGOS_AGENT_WORKSPACE:-$(cd "$ROOT/.." && pwd)}"
FALLBACK_WORKSPACE="${LOGOS_AGENT_FALLBACK_WORKSPACE:-$ROOT/.local/v02-workspace}"
declare -A REPO_DIRS=()

clone_repo() {
  local name="$1"
  local url="$2"
  local rev="$3"
  local submodules="${4:-false}"
  local dir="$WORKSPACE/$name"

  if [ -d "$dir/.git" ]; then
    local sibling_current
    sibling_current="$(git -C "$dir" rev-parse HEAD)"
    if [ -n "$(git -C "$dir" status --porcelain)" ] && [ "$sibling_current" != "$rev" ]; then
      dir="$FALLBACK_WORKSPACE/$name"
      echo "preserving incompatible dirty checkout; using isolated dependency: $dir" >&2
    fi
  fi

  if [ ! -d "$dir/.git" ]; then
    mkdir -p "$(dirname "$dir")"
    git clone "$url" "$dir"
  fi

  local current
  current="$(git -C "$dir" rev-parse HEAD)"
  if [ -n "$(git -C "$dir" status --porcelain)" ]; then
    if [ "$current" != "$rev" ]; then
      echo "refusing to replace dirty checkout $dir ($current); required revision is $rev" >&2
      exit 1
    fi
    echo "using dirty checkout at required revision without modifying it: $dir" >&2
    REPO_DIRS["$name"]="$dir"
    return
  fi

  git -C "$dir" fetch --tags --force origin "$rev"
  git -C "$dir" checkout --detach "$rev"

  if [ "$submodules" = "true" ]; then
    git -C "$dir" submodule update --init --recursive
  fi
  REPO_DIRS["$name"]="$dir"
}

configure_flake_paths() {
  local flake="$ROOT/flake.nix"
  local circuits_flake="$ROOT/nix/logos-blockchain-circuits-compat/flake.nix"
  local repos=(
    logos-module-builder logos-nix logos-cpp-sdk logos-module logos-plugin-qt logos-logoscore-cli
    nix-bundle-lgx logos-package nix-bundle-dir nix-bundle-appimage
    nix-bundle-logos-module-install logos-standalone-app logos-test-framework
    logos-liblogos process-stats logos-package-manager logos-package-downloader logos-design-system
    logos-capability-module logos-view-module-runtime logos-qt-mcp
    logos-execution-zone-module logos-storage-module logos-chat-module
    logos-delivery-module logos-execution-zone logos-storage-nim logos-chat
    logos-delivery rust-overlay crane flake-utils nix-systems-default
    logos-blockchain-circuits
  )

  for repo in "${repos[@]}"; do
    local repo_dir="${REPO_DIRS[$repo]:-$WORKSPACE/$repo}"
    perl -0pi -e "s#path:(?:\\./)?\\.\\./$repo#path:$repo_dir#g" "$flake"
    perl -0pi -e "s#path:/[^\\\"]*/$repo#path:$repo_dir#g" "$flake" "$circuits_flake"
    perl -0pi -e "s#git\\+file:(?:\\./)?\\.\\./$repo#git+file://$repo_dir#g" "$flake"
    perl -0pi -e "s#git\\+file://[^\\\"?]*/$repo#git+file://$repo_dir#g" "$flake"
  done

  local circuits_dir="${REPO_DIRS[logos-blockchain-circuits]:-$WORKSPACE/logos-blockchain-circuits}"
  perl -0pi -e "s#path:(?:\\./)?\\.\\./\\.\\./\\.\\./logos-blockchain-circuits#path:$circuits_dir#g" "$circuits_flake"
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

clone_repo logos-module-builder https://github.com/logos-co/logos-module-builder.git 2b59cb8e855894f7e7a064b15bfae409f288080b
clone_repo logos-nix https://github.com/logos-co/logos-nix.git e637a1f5e871244d1c2df1e3c52a067f2eb406f2
clone_repo logos-cpp-sdk https://github.com/logos-co/logos-cpp-sdk.git 350a2891e60a40aba93f273d85e8accb4803ac29
clone_repo logos-logoscore-cli https://github.com/logos-co/logos-logoscore-cli.git 797b98a02bb009c477cfe82a7bb75f5fc6cb75d7
clone_repo logos-module https://github.com/logos-co/logos-module.git 2ec64c4a65f8966b5137cdba3a19a6498ce17b6d
clone_repo logos-plugin-qt https://github.com/logos-co/logos-plugin-qt.git f33f264abb6d628cc78cf926f9f33c7cc8252151
clone_repo nix-bundle-lgx https://github.com/logos-co/nix-bundle-lgx.git 3c44d99b9d8dbd8a135b44b5b328e6175650305e
clone_repo logos-package https://github.com/logos-co/logos-package.git d2c98d34cc3412d08f2fab23644c620a79b78477
clone_repo nix-bundle-dir https://github.com/logos-co/nix-bundle-dir.git 4937262f55cf8be942263255dd0801e3e3878bc9
clone_repo nix-bundle-appimage https://github.com/logos-co/nix-bundle-appimage.git 8fcc56b5afcc313ca917cf3487be082ae2f0184c
clone_repo nix-bundle-logos-module-install https://github.com/logos-co/nix-bundle-logos-module-install.git 89cc9ea91275396d589c767d76926459ac77ef20
clone_repo logos-standalone-app https://github.com/logos-co/logos-standalone-app.git f812b43f73f3c264ee0f8a8354f40721431d6846
clone_repo logos-test-framework https://github.com/logos-co/logos-test-framework.git eb1600cc6f61b66f6d75edd4773a58f0d1fa1ca4
clone_repo logos-liblogos https://github.com/logos-co/logos-liblogos.git 51313eb58f2566efaa6ece82071a34e3bc4f7f61
clone_repo process-stats https://github.com/logos-co/process-stats.git 33ace1270f90c89b3565e803139c0970fcd1ce8f
clone_repo logos-package-manager https://github.com/logos-co/logos-package-manager.git 7a1f1cf35b22dc1a3407d6b5cafce333321be584
clone_repo logos-package-downloader https://github.com/logos-co/logos-package-downloader.git cf814220bfd78a0e07e042a8d29fae026bf652fd
clone_repo logos-design-system https://github.com/logos-co/logos-design-system.git 379ae956cbfdd189cfe3397fa372d14976aa85c9
clone_repo logos-capability-module https://github.com/logos-co/logos-capability-module.git e675e9e3a98ee69bb303365c2c626f9237bc1ab5
clone_repo logos-view-module-runtime https://github.com/logos-co/logos-view-module-runtime.git 21dddc380eca36e7e865cf5a437f63e0e16f30d3
clone_repo logos-qt-mcp https://github.com/logos-co/logos-qt-mcp.git c5223b4b640add09e461983b8fddbd12c8b31f4f
clone_repo logos-execution-zone-module https://github.com/logos-blockchain/logos-execution-zone-module.git 92dd9e25bcc6be04f841671e8da7b94bd2449f39
clone_repo logos-storage-module https://github.com/logos-co/logos-storage-module.git 8feb7cc0f7806bc2b25faa884e1bb9076b993969
clone_repo logos-chat-module https://github.com/logos-co/logos-chat-module.git 894526024dadd641a88a7b3b23de6a1edb8a8dff
clone_repo logos-delivery-module https://github.com/logos-co/logos-delivery-module.git 794c21cbe177bdea16d4907468eaf52d4282dda7
clone_repo logos-execution-zone https://github.com/logos-blockchain/logos-execution-zone.git a58fbce2ff48c58b7bb5001b1a27e64b9596ee3a
clone_repo logos-blockchain-circuits https://github.com/logos-blockchain/logos-blockchain-circuits.git 059bc01e17b3d09cacfbbc9ab587dbb2c1447eec
clone_repo logos-storage-nim https://github.com/logos-storage/logos-storage-nim.git d94417a221ea12153c70744cb22942a561ab2a34 true
clone_repo logos-chat https://github.com/logos-messaging/logos-chat.git 15f68f2ec2c83befd7c346c7ce5b2d0b49f9c00d true
clone_repo logos-delivery https://github.com/logos-messaging/logos-delivery.git f8b036594ea2a36b529e10b584b7d2851a3ac5c8 true
clone_repo scaffold https://github.com/logos-co/scaffold.git ae8c0b9ceaaa75462cb3bf14e8584f3f7d8df893
clone_repo rust-overlay https://github.com/oxalica/rust-overlay.git 27b7e78c6935293ee868469cc4172e9b8b17823b
clone_repo crane https://github.com/ipetkov/crane.git 59a82a1222dd3b2080b5cc52a1a2e8d5f1b77f37
clone_repo flake-utils https://github.com/numtide/flake-utils.git 11707dc2f618dd54ca8739b309ec4fc024de578b
clone_repo nix-systems-default https://github.com/nix-systems/default.git da67096a3b9bf56a91d16901293e51ba5b49a27e

configure_flake_paths

echo "Workspace ready at $WORKSPACE"
