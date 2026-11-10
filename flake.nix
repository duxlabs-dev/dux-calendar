{
  description = "Dux Calendar";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    dank-qml-common = {
      url = "github:duxlabs-dev/dux-qml-common";
      flake = false;
    };
    dux-qt-base = {
      url = "github:duxlabs-dev/dux-qt-base";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      dank-qml-common,
      dux-qt-base,
      ...
    }:
    let
      goModVersion =
        let
          content = builtins.readFile ./core/go.mod;
          lines = builtins.filter builtins.isString (builtins.split "\n" content);
          goLines = builtins.filter (l: builtins.match "go [0-9]+\\..*" l != null) lines;
          matched =
            if goLines != [ ] then builtins.match "go ([0-9]+)\\.([0-9]+).*" (builtins.head goLines) else null;
        in
        if matched != null then
          {
            major = builtins.elemAt matched 0;
            minor = builtins.elemAt matched 1;
          }
        else
          {
            major = "1";
            minor = "25";
          };
      goForPkgs = pkgs: pkgs.${"go_${goModVersion.major}_${goModVersion.minor}"};

      forEachSystem =
        fn:
        nixpkgs.lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
          system: fn system nixpkgs.legacyPackages.${system}
        );

      duxQtBaseFor = pkgs: (dux-qt-base.overlays.default pkgs pkgs).dux-qt-base;

      mkQmlImportPath =
        pkgs: qmlPkgs:
        pkgs.lib.concatStringsSep ":" (map (o: "${o}/${pkgs.qt6.qtbase.qtQmlPrefix}") qmlPkgs);

      mkQtPluginPath =
        pkgs: qtPkgs:
        pkgs.lib.concatStringsSep ":" (map (o: "${o}/${pkgs.qt6.qtbase.qtPluginPrefix}") qtPkgs);

      mkModuleWithDcalPkgs =
        modulePath:
        args@{ pkgs, ... }:
        {
          imports = [
            (import modulePath (args // { dcalPkgs = buildDcalPkgs pkgs; }))
          ];
        };

      mkDcal =
        pkgs:
        pkgs.lib.makeOverridable (
          {
            duxQtBase ? duxQtBaseFor pkgs,
          }:
          let
            version = "2.1.0";
            qtPackages = with pkgs.kdePackages; [
              qtdeclarative
              qtsvg
            ];
          in
          (pkgs.buildGoModule.override { go = goForPkgs pkgs; }) {
            inherit version;
            pname = "dankcalendar";
            src = ./.;
            modRoot = "core";
            vendorHash = "sha256-0dhVy8BNTRrNo1cFAVlR80yaUMqa2PCNbx4cYl04g9g=";

            subPackages = [ "cmd/dcal" ];

            tags = [
              "withshell"
              "withqtbase"
            ];

            # embed the runtime library the same way make qtbase does; buildGoModule copies preBuild
            # into the vendor derivation, which would make the vendorHash build depend on dux-qt-base
            preConfigure = ''
              install -Dm644 ${duxQtBase}/lib/libdux-qt-base.so.0 core/internal/qtbaseembed/lib/libdux-qt-base.so.0
              sha256sum core/internal/qtbaseembed/lib/libdux-qt-base.so.0 | cut -c1-16 > core/internal/qtbaseembed/lib/.dankrev
            '';

            # Mirror `make -C core sync-shell`: bake the quickshell UI into
            # the binary, minus dev-only files. The flake src excludes
            # submodule content, so the DCommon symlink is replaced with
            # the pinned dank-qml-common input.
            postPatch = ''
              rm -rf core/internal/shellembed/dist
              cp -r quickshell core/internal/shellembed/dist
              rm -f core/internal/shellembed/dist/DCommon
              cp -r ${dank-qml-common}/DCommon core/internal/shellembed/dist/DCommon
              chmod -R u+w core/internal/shellembed/dist/DCommon
              rm -rf core/internal/shellembed/dist/scripts \
                core/internal/shellembed/dist/.claude
              rm -f core/internal/shellembed/dist/.qmlls.ini \
                core/internal/shellembed/dist/translations/extract_translations.py
            '';

            ldflags = [
              "-s"
              "-w"
              "-X main.Version=${version}"
              "-X main.Commit=${self.shortRev or self.dirtyShortRev or "dirty"}"
            ];

            nativeBuildInputs = with pkgs; [
              installShellFiles
              makeWrapper
            ];

            postInstall = ''
              install -Dm644 ${./assets/dev.duxlabs.calendar.desktop} \
                $out/share/applications/dev.duxlabs.calendar.desktop
              substituteInPlace $out/share/applications/dev.duxlabs.calendar.desktop \
                --replace-fail 'Exec=dcal ' 'Exec='$out'/bin/dcal '
              install -Dm644 ${./assets/dev.duxlabs.calendar.svg} \
                $out/share/icons/hicolor/scalable/apps/dev.duxlabs.calendar.svg

              install -Dm644 ${./assets/systemd/dcal.service} \
                $out/lib/systemd/user/dcal.service
              substituteInPlace $out/lib/systemd/user/dcal.service \
                --replace-fail /usr/bin/dcal $out/bin/dcal

              installShellCompletion --cmd dcal \
                --bash <($out/bin/dcal completion bash) \
                --fish <($out/bin/dcal completion fish) \
                --zsh <($out/bin/dcal completion zsh)

              wrapProgram $out/bin/dcal \
                --prefix NIXPKGS_QT6_QML_IMPORT_PATH : "${mkQmlImportPath pkgs qtPackages}" \
                --prefix QT_PLUGIN_PATH : "${mkQtPluginPath pkgs qtPackages}"
            '';

            meta = {
              description = "Local, Google, Microsoft, and CalDAV calendars for the Dux desktop";
              homepage = "https://github.com/duxlabs-dev/dux-calendar";
              license = pkgs.lib.licenses.mit;
              mainProgram = "dcal";
              platforms = pkgs.lib.platforms.linux;
            };
          }
        ) { };

      buildDcalPkgs = pkgs: {
        dankcalendar = mkDcal pkgs;
        dux-qt-base = duxQtBaseFor pkgs;
      };
    in
    {
      packages = forEachSystem (
        system: pkgs: {
          dankcalendar = mkDcal pkgs;
          default = self.packages.${system}.dankcalendar;
        }
      );

      lib = { inherit mkDcal buildDcalPkgs; };

      homeModules.dank-calendar = mkModuleWithDcalPkgs ./distro/nix/home.nix;

      homeModules.default = self.homeModules.dank-calendar;

      nixosModules.dank-calendar = mkModuleWithDcalPkgs ./distro/nix/nixos.nix;

      nixosModules.default = self.nixosModules.dank-calendar;

      devShells = forEachSystem (
        system: pkgs: {
          default = pkgs.mkShell {
            # Let the golangci-lint pre-commit hook fetch the Go version core/go.mod
            # requires rather than pinning it (prek forces GOTOOLCHAIN=local otherwise).
            GOTOOLCHAIN = "auto";

            buildInputs = with pkgs; [
              (goForPkgs pkgs)
              go-mockery
              gopls
              delve
              go-tools
              gnumake

              quickshell

              prek
              uv
              python3

              nixd
              nil
            ];

            shellHook = ''
              touch quickshell/.qmlls.ini 2>/dev/null
              if [ ! -f .git/hooks/pre-commit ]; then prek install; fi
            '';
          };
        }
      );

      nixosTests = nixpkgs.lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
        system:
        import ./distro/nix/tests {
          inherit self;
          pkgs = nixpkgs.legacyPackages.${system};
        }
      );
    };
}
