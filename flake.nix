{
  description = "Ninjabrain Bot - stronghold calculator for Minecraft speedrunning";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});

      version =
        let
          lines = lib.splitString "\n" (builtins.readFile ./pom.xml);
          match = lib.findFirst (m: m != null) null (
            map (l: builtins.match "[[:space:]]*<version>([^<]+)</version>[[:space:]]*" l) lines
          );
        in
        if match == null then throw "flake.nix: no <version> found in pom.xml" else builtins.head match;

      source = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.unions [
          ./pom.xml
          ./src
        ];
      };

      mkNinjabrainBot =
        {
          lib,
          stdenv,
          maven,
          makeWrapper,
          copyDesktopItems,
          makeDesktopItem,
          jre,
          libxkbcommon,
          libx11,
          libxcb,
          libxinerama,
          libxt,
          libxtst,
        }:
        let
          linuxNativeLibraries = [
            libxkbcommon
            libx11
            libxcb
            libxinerama
            libxt
            libxtst
          ];
        in
        maven.buildMavenPackage {
          pname = "ninjabrain-bot";
          inherit version;
          src = source;

          strictDeps = true;
          __structuredAttrs = true;

          # CI=true makes the suite skip the tests that need a display; the rest still run.
          env.CI = "true";
          mvnFetchExtraArgs.env.CI = "true";

          mvnParameters = "assembly:single";
          mvnHash = "sha256-k/bhq3TyiG+PvUogBeFGpgx+vBFdkEge6UnmnVPUjjg=";

          nativeBuildInputs = [
            makeWrapper
            copyDesktopItems
          ];

          installPhase = ''
            runHook preInstall

            install -Dm444 target/ninjabrainbot-${version}-jar-with-dependencies.jar \
              $out/share/java/ninjabrain-bot.jar

            install -Dm644 src/main/resources/icon.png \
              $out/share/icons/hicolor/512x512/apps/ninjabrain-bot.png
            install -Dm644 src/main/resources/icon.png \
              $out/share/icons/hicolor/640x640/apps/ninjabrain-bot.png

            # Swing text rendering varies outside a full desktop environment.
            makeWrapperArgs=(
              --add-flags "-Dawt.useSystemAAFontSettings=on"
              --add-flags "-Dswing.aatext=true"
              --add-flags "-jar $out/share/java/ninjabrain-bot.jar"
            )

            ${lib.optionalString stdenv.hostPlatform.isLinux ''
              makeWrapperArgs+=(
                --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath linuxNativeLibraries}
              )
            ''}

            makeWrapper ${lib.getExe jre} $out/bin/ninjabrain-bot "''${makeWrapperArgs[@]}"

            runHook postInstall
          '';

          desktopItems = [
            (makeDesktopItem {
              name = "ninjabrain-bot";
              desktopName = "Ninjabrain Bot";
              comment = "Stronghold calculator for Minecraft speedrunning";
              type = "Application";
              exec = "ninjabrain-bot";
              icon = "ninjabrain-bot";
              categories = [
                "Game"
                "Utility"
              ];
              keywords = [
                "minecraft"
                "speedrun"
                "stronghold"
                "mcsr"
              ];
            })
          ];

          meta = {
            description = "Stronghold calculator for Minecraft speedrunning";
            homepage = "https://github.com/Ninjabrain1/Ninjabrain-Bot";
            license = lib.licenses.gpl3Only;
            mainProgram = "ninjabrain-bot";
            platforms = systems;
          };
        };
    in
    {
      packages = forAllSystems (
        system: pkgs: rec {
          ninjabrain-bot = pkgs.callPackage mkNinjabrainBot { };
          default = ninjabrain-bot;
        }
      );

      devShells = forAllSystems (
        system: pkgs: {
          default = pkgs.mkShell {
            packages = [
              pkgs.maven
              pkgs.jdk
            ];
            CI = "true";
          };
        }
      );

      apps = forAllSystems (
        system: pkgs: rec {
          ninjabrain-bot = {
            type = "app";
            program = lib.getExe self.packages.${system}.ninjabrain-bot;
            meta.description = "Run Ninjabrain Bot";
          };
          default = ninjabrain-bot;
        }
      );

      checks = forAllSystems (
        system: pkgs: {
          inherit (self.packages.${system}) ninjabrain-bot;
        }
      );

      formatter = forAllSystems (system: pkgs: pkgs.nixfmt-tree);
    };
}
