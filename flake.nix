{
  description = "Greener Reporter Lib";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay.url = "github:mitchellh/zig-overlay";
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ zig-overlay.overlays.default ];
        };

        zig = pkgs.zigpkgs."0.15.2";

        buildForTargets = targets: pkgs.stdenv.mkDerivation {
          pname = "greener-reporter";
          version = "0.1.0";

          src = ./.;

          nativeBuildInputs = [ zig ];

          dontConfigure = true;

          buildPhase = ''
            runHook preBuild
            export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
            export HOME=$TMPDIR

            ${pkgs.lib.concatMapStringsSep "\n" (target: ''
              echo "Building for target: ${target}"
              zig build -Doptimize=ReleaseSafe --prefix $TMPDIR/install-${target} --seed 0x00000000 -Dtarget=${target}
            '') targets}

            runHook postBuild
          '';

          checkPhase = ''
            runHook preCheck
            export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
            export HOME=$TMPDIR

            echo "Running tests"
            zig build test --seed 0x00000000

            runHook postCheck
          '';

          doCheck = true;

          installPhase = ''
            runHook preInstall
            ${pkgs.lib.concatMapStringsSep "\n" (target: ''
              mkdir -p $out/${target}
              cp -r $TMPDIR/install-${target}/lib/* $out/${target}/
            '') targets}
            runHook postInstall
          '';

          meta = {
            description = "Greener Reporter Lib";
            license = pkgs.lib.licenses.asl20;
            platforms = pkgs.lib.platforms.unix;
          };
        };

      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            zig
          ];
        };

        packages = {
          default = buildForTargets [ "aarch64-macos" ];
          minimal = buildForTargets [ "x86_64-linux-gnu" ];
          all = buildForTargets [ "x86_64-linux-gnu" "aarch64-linux-gnu" ];
        };
      }
    );
}
