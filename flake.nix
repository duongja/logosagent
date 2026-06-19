{
  description = "LP-0008 Logos Agent module";

  inputs = {
    logos-module-builder.url = "path:/home/agate/Projects/logos/logos-module-builder";
    logos-module-builder.inputs.logos-nix.follows = "logos-nix";
    logos-module-builder.inputs.logos-cpp-sdk.follows = "logos-cpp-sdk";
    logos-module-builder.inputs.logos-module.follows = "logos-module";
    logos-module-builder.inputs.logos-plugin-qt.follows = "logos-plugin-qt";
    logos-module-builder.inputs.logos-plugin-core.follows = "logos-plugin-qt";
    logos-module-builder.inputs.nix-bundle-lgx.follows = "nix-bundle-lgx";
    logos-module-builder.inputs.nix-bundle-logos-module-install.follows = "nix-bundle-logos-module-install";
    logos-module-builder.inputs.logos-standalone-app.follows = "logos-standalone-app";
    logos-module-builder.inputs.logos-test-framework.follows = "logos-test-framework";
    logos-nix.url = "path:/home/agate/Projects/logos/logos-nix";
    nixpkgs.follows = "logos-nix/nixpkgs";
    logos-cpp-sdk.url = "path:/home/agate/Projects/logos/logos-cpp-sdk";
    logos-cpp-sdk.inputs.logos-nix.follows = "logos-nix";
    logos-module.url = "path:/home/agate/Projects/logos/logos-module";
    logos-module.inputs.logos-nix.follows = "logos-nix";
    logos-plugin-qt.url = "path:/home/agate/Projects/logos/logos-plugin-qt";
    logos-plugin-qt.inputs.logos-nix.follows = "logos-nix";
    logos-plugin-qt.inputs.logos-module.follows = "logos-module";
    nix-bundle-lgx.url = "path:/home/agate/Projects/logos/nix-bundle-lgx";
    nix-bundle-lgx.inputs.logos-nix.follows = "logos-nix";
    nix-bundle-lgx.inputs.logos-package.follows = "logos-package";
    nix-bundle-lgx.inputs.nix-bundle-dir.follows = "nix-bundle-dir";
    logos-package.url = "path:/home/agate/Projects/logos/logos-package";
    logos-package.inputs.logos-nix.follows = "logos-nix";
    nix-bundle-dir.url = "path:/home/agate/Projects/logos/nix-bundle-dir";
    nix-bundle-dir.inputs.logos-nix.follows = "logos-nix";
    nix-bundle-appimage.url = "path:/home/agate/Projects/logos/nix-bundle-appimage";
    nix-bundle-appimage.inputs.logos-nix.follows = "logos-nix";
    nix-bundle-appimage.inputs.nix-bundle-dir.follows = "nix-bundle-dir";
    nix-bundle-logos-module-install.url = "path:/home/agate/Projects/logos/nix-bundle-logos-module-install";
    nix-bundle-logos-module-install.inputs.logos-nix.follows = "logos-nix";
    nix-bundle-logos-module-install.inputs.nix-bundle-lgx.follows = "nix-bundle-lgx";
    nix-bundle-logos-module-install.inputs.logos-package-manager.follows = "logos-package-manager";
    logos-standalone-app.url = "path:/home/agate/Projects/logos/logos-standalone-app";
    logos-standalone-app.inputs.logos-nix.follows = "logos-nix";
    logos-standalone-app.inputs.logos-cpp-sdk.follows = "logos-cpp-sdk";
    logos-standalone-app.inputs.logos-liblogos.follows = "logos-liblogos";
    logos-standalone-app.inputs.logos-design-system.follows = "logos-design-system";
    logos-standalone-app.inputs.logos-capability-module.follows = "logos-capability-module";
    logos-standalone-app.inputs.logos-view-module-runtime.follows = "logos-view-module-runtime";
    logos-standalone-app.inputs.nix-bundle-lgx.follows = "nix-bundle-lgx";
    logos-standalone-app.inputs.logos-qt-mcp.follows = "logos-qt-mcp";
    logos-test-framework.url = "path:/home/agate/Projects/logos/logos-test-framework";
    logos-test-framework.inputs.logos-nix.follows = "logos-nix";
    logos-test-framework.inputs.logos-cpp-sdk.follows = "logos-cpp-sdk";
    logos-liblogos.url = "path:/home/agate/Projects/logos/logos-liblogos";
    logos-liblogos.inputs.logos-nix.follows = "logos-nix";
    logos-liblogos.inputs.logos-cpp-sdk.follows = "logos-cpp-sdk";
    logos-liblogos.inputs.logos-capability-module.follows = "logos-capability-module";
    logos-liblogos.inputs.logos-module.follows = "logos-module";
    logos-liblogos.inputs.process-stats.follows = "process-stats";
    logos-liblogos.inputs.logos-package-manager.follows = "logos-package-manager";
    process-stats.url = "path:/home/agate/Projects/logos/process-stats";
    process-stats.inputs.logos-nix.follows = "logos-nix";
    logos-package-manager.url = "path:/home/agate/Projects/logos/logos-package-manager";
    logos-package-manager.inputs.logos-nix.follows = "logos-nix";
    logos-package-manager.inputs.logos-package.follows = "logos-package";
    logos-package-manager.inputs.nix-bundle-dir.follows = "nix-bundle-dir";
    logos-package-manager.inputs.nix-bundle-appimage.follows = "nix-bundle-appimage";
    logos-design-system.url = "path:/home/agate/Projects/logos/logos-design-system";
    logos-design-system.inputs.logos-nix.follows = "logos-nix";
    logos-capability-module.url = "path:/home/agate/Projects/logos/logos-capability-module";
    logos-capability-module.inputs.logos-module-builder.follows = "logos-module-builder";
    logos-view-module-runtime.url = "path:/home/agate/Projects/logos/logos-view-module-runtime";
    logos-view-module-runtime.inputs.logos-nix.follows = "logos-nix";
    logos-view-module-runtime.inputs.logos-cpp-sdk.follows = "logos-cpp-sdk";
    logos-qt-mcp.url = "path:/home/agate/Projects/logos/logos-qt-mcp";
    logos-qt-mcp.inputs.logos-nix.follows = "logos-nix";
    logos_execution_zone.url = "path:/home/agate/Projects/logos/logos-execution-zone-module";
    storage_module.url = "path:/home/agate/Projects/logos/logos-storage-module";
    chat_module.url = "path:/home/agate/Projects/logos/logos-chat-module";
    delivery_module.url = "path:/home/agate/Projects/logos/logos-delivery-module";
    logos_execution_zone.inputs.logos-module-builder.follows = "logos-module-builder";
    logos_execution_zone.inputs.nix-bundle-lgx.follows = "nix-bundle-lgx";
    logos_execution_zone.inputs.logos-execution-zone.follows = "logos-execution-zone-src";
    storage_module.inputs.logos-module-builder.follows = "logos-module-builder";
    storage_module.inputs.logos-storage.follows = "logos-storage-src";
    chat_module.inputs.logos-module-builder.follows = "logos-module-builder";
    chat_module.inputs.nix-bundle-lgx.follows = "nix-bundle-lgx";
    chat_module.inputs.logos-chat.follows = "logos-chat-src";
    delivery_module.inputs.logos-module-builder.follows = "logos-module-builder";
    delivery_module.inputs.nix-bundle-lgx.follows = "nix-bundle-lgx";
    delivery_module.inputs.logos-delivery.follows = "logos-delivery-src";
    logos-execution-zone-src.url = "path:/home/agate/Projects/logos/logos-execution-zone";
    logos-execution-zone-src.inputs.logos-liblogos.follows = "logos-liblogos";
    logos-execution-zone-src.inputs.rust-overlay.follows = "rust-overlay";
    logos-execution-zone-src.inputs.crane.follows = "crane";
    logos-execution-zone-src.inputs.logos-blockchain-circuits.follows = "logos-blockchain-circuits";
    logos-blockchain-circuits.url = "path:./nix/logos-blockchain-circuits-compat";
    logos-storage-src.url = "path:/home/agate/Projects/logos/logos-storage-nim";
    logos-storage-src.inputs.nixpkgs.follows = "nixpkgs";
    logos-chat-src.url = "git+file:///home/agate/Projects/logos/logos-chat?submodules=1";
    logos-chat-src.inputs.nixpkgs.follows = "nixpkgs";
    logos-chat-src.inputs.rust-overlay.follows = "rust-overlay";
    logos-chat-src.inputs.flake-utils.follows = "flake-utils";
    logos-delivery-src.url = "git+file:///home/agate/Projects/logos/logos-delivery?submodules=1";
    logos-delivery-src.inputs.nixpkgs.follows = "nixpkgs";
    logos-delivery-src.inputs.rust-overlay.follows = "rust-overlay";
    rust-overlay.url = "path:/home/agate/Projects/logos/rust-overlay";
    crane.url = "path:/home/agate/Projects/logos/crane";
    flake-utils.url = "path:/home/agate/Projects/logos/flake-utils";
    flake-utils.inputs.systems.follows = "systems";
    systems.url = "path:/home/agate/Projects/logos/nix-systems-default";
  };

  outputs = inputs@{ logos-module-builder, nixpkgs, logos-cpp-sdk, logos-test-framework, ... }:
    let
      lib = nixpkgs.lib;
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      source = lib.cleanSourceWith {
        src = ./.;
        filter = path: type:
          let
            rel = lib.removePrefix (toString ./. + "/") (toString path);
            baseName = baseNameOf path;
          in
          ! (
            rel == ".local"
            || lib.hasPrefix ".local/" rel
            || rel == ".git"
            || lib.hasPrefix ".git/" rel
            || rel == "agent_lez/target"
            || lib.hasPrefix "agent_lez/target/" rel
            || rel == "cli/__pycache__"
            || lib.hasPrefix "cli/__pycache__/" rel
            || lib.hasPrefix "result" baseName
          );
      };

      base = logos-module-builder.lib.mkLogosModule {
        src = source;
        configFile = ./metadata.json;
        flakeInputs = inputs;
      };

      fastTests = lib.genAttrs systems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          logosSdk = logos-cpp-sdk.packages.${system}.default;
          testFramework = logos-test-framework.packages.${system}.default;
        in
        pkgs.stdenv.mkDerivation {
          pname = "logos-agent-fast-tests";
          version = "0.1.0";
          src = source;

          nativeBuildInputs = with pkgs; [
            cmake
            ninja
            pkg-config
            qt6.wrapQtAppsNoGuiHook
            logosSdk
          ];

          buildInputs = with pkgs; [
            qt6.qtbase
            qt6.qtremoteobjects
            logosSdk
            testFramework
          ];

          dontUseCmakeConfigure = true;

          buildPhase = ''
            runHook preBuild
            cmake -S tests -B build -GNinja \
              -DLOGOS_CPP_SDK_ROOT=${logosSdk} \
              -DLOGOS_TEST_FRAMEWORK_ROOT=${testFramework} \
              -DCMAKE_MODULE_PATH=${testFramework}/cmake
            cmake --build build --parallel "$NIX_BUILD_CORES"
            ./build/logos_agent_tests
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p "$out/bin"
            cp build/logos_agent_tests "$out/bin/"
            runHook postInstall
          '';
        });

      fastTestOutputs = lib.mapAttrs (_: drv: { "unit-tests-fast" = drv; }) fastTests;
    in
    base // {
      packages = lib.recursiveUpdate (base.packages or {}) fastTestOutputs;
      checks = lib.recursiveUpdate (base.checks or {}) fastTestOutputs;
    };
}
