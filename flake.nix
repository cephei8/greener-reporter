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

        hostToZigTarget = {
          "aarch64-darwin" = "aarch64-macos";
          "x86_64-darwin" = "x86_64-macos";
          "x86_64-linux" = "x86_64-linux-gnu";
          "aarch64-linux" = "aarch64-linux-gnu";
        };

        defaultTarget = hostToZigTarget.${pkgs.stdenv.hostPlatform.system};

        buildForTarget = zigTarget: pkgs.stdenv.mkDerivation {
          pname = "greener-reporter";
          version = "0.1.0";

          src = ./.;

          nativeBuildInputs = [ zig ];

          dontConfigure = true;

          buildPhase = ''
            runHook preBuild
            export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
            export HOME=$TMPDIR

            zig build -Doptimize=ReleaseSafe --prefix $TMPDIR/install --seed 0x00000000 -Dtarget=${zigTarget}

            runHook postBuild
          '';

          doCheck = false;

          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp -r $TMPDIR/install/lib/* $out/
            if [[ "${zigTarget}" == *"windows"* ]]; then
              cp -r $TMPDIR/install/bin/*.dll $out/
            fi
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
          default = buildForTarget defaultTarget;
          x86_64-linux-gnu = buildForTarget "x86_64-linux-gnu";
          aarch64-linux-gnu = buildForTarget "aarch64-linux-gnu";
          x86_64-linux-musl = buildForTarget "x86_64-linux-musl";
          aarch64-linux-musl = buildForTarget "aarch64-linux-musl";
          x86_64-windows = buildForTarget "x86_64-windows";
          x86_64-macos = buildForTarget "x86_64-macos";
          aarch64-macos = buildForTarget "aarch64-macos";
        };

        checks = {
          tests = pkgs.stdenv.mkDerivation {
            pname = "greener-reporter-tests";
            version = "0.1.0";

            src = ./.;

            nativeBuildInputs = [ zig ];

            dontConfigure = true;
            dontBuild = true;

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
              mkdir -p $out
              echo "Tests passed" > $out/result
              runHook postInstall
            '';
          };
        };
      }
    );
}
