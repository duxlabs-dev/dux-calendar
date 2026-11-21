{
  config,
  pkgs,
  lib,
  ...
}@args:
let
  cfg = config.programs.dank-calendar;
in
{
  imports = [ (import ./options.nix args) ];

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.packages = lib.mkIf cfg.systemd.enable [ cfg.package ];

    systemd.user.services.dcal = lib.mkIf cfg.systemd.enable {
      wantedBy = [ cfg.systemd.target ];
      restartIfChanged = cfg.systemd.restartIfChanged;
    };
  };
}
