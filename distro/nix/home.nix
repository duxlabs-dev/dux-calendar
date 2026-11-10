{
  config,
  pkgs,
  lib,
  ...
}@args:
let
  cfg = config.programs.dank-calendar;
  jsonFormat = pkgs.formats.json { };
in
{
  imports = [ (import ./options.nix args) ];

  options.programs.dank-calendar.settings = lib.mkOption {
    type = jsonFormat.type;
    default = { };
    description = "Dux Calendar UI settings written to ~/.config/dankcal/ui-settings.json.";
    example = lib.literalExpression ''
      {
        remindersEnabled = true;
        use24HourClock = true;
        defaultReminderMinutes = 10;
        snoozeMinutes = 5;
      }
    '';
  };

  config = lib.mkIf cfg.enable {
    programs.dank-calendar.systemd.target = lib.mkDefault config.wayland.systemd.target;

    home.packages = [ cfg.package ];

    systemd.user.services.dcal = lib.mkIf cfg.systemd.enable {
      Unit = {
        Description = "Dux Calendar";
        PartOf = [ cfg.systemd.target ];
        After = [ cfg.systemd.target ];
        # With RestartSec=2 the default limit (5 starts per 10s) is never reached, so a persistent failure would restart forever.
        StartLimitIntervalSec = "60";
        StartLimitBurst = "5";
      };

      Service = {
        ExecStart = lib.getExe cfg.package + " run --session --hidden";
        Restart = "on-failure";
        RestartSec = "2";
        Slice = "app.slice";
      };

      Install.WantedBy = [ cfg.systemd.target ];
    };

    xdg.configFile."dankcal/ui-settings.json" = lib.mkIf (cfg.settings != { }) {
      source = jsonFormat.generate "ui-settings.json" cfg.settings;
    };
  };
}
