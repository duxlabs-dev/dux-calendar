{
  config,
  lib,
  dcalPkgs,
  ...
}:
let
  inherit (lib) types;
in
{
  imports = [
    (lib.mkRemovedOptionModule [
      "programs"
      "dank-calendar"
      "quickshell"
      "package"
    ] "The Quickshell runtime is embedded in dcal as dux-qt-base; set programs.dank-calendar.duxQtBase.package instead.")
  ];

  options.programs.dank-calendar = {
    enable = lib.mkEnableOption "Dux Calendar";

    package = lib.mkOption {
      type = types.package;
      default = dcalPkgs.dankcalendar.override { duxQtBase = config.programs.dank-calendar.duxQtBase.package; };
      defaultText = lib.literalExpression "dcalPkgs.dankcalendar.override { duxQtBase = config.programs.dank-calendar.duxQtBase.package; }";
      description = "The Dux Calendar package to use (defaults to be built from source against duxQtBase.package)";
    };

    duxQtBase = {
      package = lib.mkPackageOption dcalPkgs "dux-qt-base" {
        extraDescription = "The Quickshell runtime library embedded in the dcal package (pkgs.dux-qt-base when the overlay provides it, else the dux-qt-base flake input).";
      };
    };

    systemd = {
      enable = lib.mkEnableOption "Dux Calendar systemd startup";

      target = lib.mkOption {
        type = types.str;
        default = "graphical-session.target";
        description = "Systemd target that will automatically start dcal.";
      };

      restartIfChanged = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Auto-restart dcal.service when dank-calendar changes";
      };
    };
  };
}
