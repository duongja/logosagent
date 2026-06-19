{
  description = "Compatibility wrapper for Logos Blockchain Circuits";

  inputs = {
    upstream.url = "path:/home/agate/Projects/logos/logos-blockchain-circuits";
    nixpkgs.follows = "upstream/nixpkgs";
  };

  outputs =
    { upstream, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      systems = builtins.attrNames upstream.packages;
      forAll = lib.genAttrs systems;

      wrapCircuits =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          base = upstream.packages.${system}.default;
        in
        pkgs.runCommand "logos-blockchain-circuits-compat-${base.version or "unknown"}" { } ''
          mkdir -p "$out"
          cp -a ${base}/. "$out/"
          chmod -R u+w "$out"

          # LEZ currently consumes a crate named logos-blockchain-zksign whose
          # build script expects the signature circuit artifacts under zksign/.
          # The published circuit bundle exposes the same artifacts under
          # signature/, so provide the expected compatibility path.
          if [ -d "$out/signature" ] && [ ! -e "$out/zksign" ]; then
            cp -a "$out/signature" "$out/zksign"
          fi

          if [ -f "$out/zksign/witness_generator.dat" ] && [ ! -e "$out/zksign/witness_generator" ]; then
            ln -s witness_generator.dat "$out/zksign/witness_generator"
          fi
        '';
    in
    {
      packages = forAll (
        system:
        let
          circuits = wrapCircuits system;
        in
        {
          inherit circuits;
          default = circuits;
          upstream = upstream.packages.${system}.default;
        }
      );
    };
}
