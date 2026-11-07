{
  self,
  pkgs,
  ...
}:
pkgs.testers.runNixOSTest {
  name = "dankcalendar-nixos-module";

  nodes.machine = {
    imports = [
      self.nixosModules.dank-calendar
    ];

    users.users.danklinux = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };

    programs.dank-calendar = {
      enable = true;
      systemd.enable = true;
    };

    system.stateVersion = "25.11";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    machine.succeed("command -v dcal")
    machine.succeed("su -- danklinux -c 'dcal --help >/dev/null'")
    machine.succeed("test -f /run/current-system/sw/share/systemd/user/dcal.service")
    machine.succeed("test -f /run/current-system/sw/share/applications/dev.duxlabs.calendar.desktop")
    machine.succeed("grep -q 'text/calendar;text/x-vcalendar;application/ics;' /run/current-system/sw/share/applications/dev.duxlabs.calendar.desktop")
  '';
}
