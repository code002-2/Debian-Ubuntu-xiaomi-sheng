# ---
# Module: Niri Desktop Profile
# Description: Niri scrollable-tiling Wayland compositor for sheng tablet
# Scope: System
# ---

{ config, lib, pkgs, vars, ... }:

{
  programs.niri.enable = true;
  hardware.graphics.enable = true;

  # kmscon conflicts with the compositor owning the display
  services.kmscon.enable = lib.mkForce false;

  # seatd manages DRM/input device access without a display manager
  services.seatd.enable = true;
  security.polkit.enable = true;

  # Auto-login on tty1 so bash loginShellInit can exec niri
  services.getty.autologinUser = lib.mkForce vars.username;

  environment.systemPackages = with pkgs; [
    niri
    foot
    fuzzel
    wvkbd
    waybar
  ];

  # Auto-start niri on the autologin tty (getty tty1)
  programs.bash.loginShellInit = ''
    if [ "$(tty)" = "/dev/tty1" ]; then
      echo "Starting niri compositor..." >&2

      # Dump input device info for diagnostics
      mkdir -p /tmp/niri-diag
      echo "=== $(date) ===" > /tmp/niri-diag/devices.log
      echo "--- input events ---" >> /tmp/niri-diag/devices.log
      ls -la /dev/input/event* >> /tmp/niri-diag/devices.log 2>&1
      echo "--- by-path ---" >> /tmp/niri-diag/devices.log
      ls -la /dev/input/by-path/ >> /tmp/niri-diag/devices.log 2>&1
      echo "--- by-id ---" >> /tmp/niri-diag/devices.log
      ls -la /dev/input/by-id/ >> /tmp/niri-diag/devices.log 2>&1
      echo "--- libinput ---" >> /tmp/niri-diag/devices.log
      libinput list-devices >> /tmp/niri-diag/devices.log 2>&1
      echo "--- usb devices ---" >> /tmp/niri-diag/devices.log
      lsusb >> /tmp/niri-diag/devices.log 2>&1
      echo "--- kernel modules (hid/usb) ---" >> /tmp/niri-diag/devices.log
      lsmod | grep -iE "hid|usb" >> /tmp/niri-diag/devices.log 2>&1

      if ! ls /dev/dri/card* >/dev/null 2>&1; then
        echo "ERROR: No DRM device found at /dev/dri/" >&2
      elif ! systemctl is-active --quiet seatd 2>/dev/null; then
        echo "ERROR: seatd is not running" >&2
        echo "  status: $(systemctl is-active seatd 2>&1)" >&2
      else
        exec niri --session
      fi
    fi
  '';

  environment.etc."xdg/niri/config.kdl".text = ''
    spawn-at-startup "foot"
    spawn-at-startup "wvkbd-mobintl"

    input {
        touch {
            tap
        }
        touchpad {
            tap
        }
        keyboard {
            xkb-layout "us"
        }
    }

    layout {
        gaps 12
        center-focused-column "never"
        default-column-width { proportion 0.5; }
        background-color "#202020"

        shadow {
            on
            softness 40
            spread 8
            offset x=0 y=4
            draw-behind-window true
            color "#00000060"
        }

        focus-ring {
            on
            width 2
            active-color "#60cdff"
            inactive-color "#3b3b3b"
        }

        border {
            on
            width 1
            active-color "#0078d4"
            inactive-color "#383838"
        }

        insert-hint {
            on
            color "#0078d480"
        }
    }

    window-rule {
        geometry-corner-radius 12
        clip-to-geometry true
    }

    layer-rule {
        match namespace="^launcher$"

        shadow {
            on
        }

        geometry-corner-radius 12

        background-effect {
            blur true
        }
    }

    animations {
        workspace-switch {
            spring damping-ratio=0.8 stiffness=800 epsilon=0.0001
        }

        window-open {
            duration-ms 200
            curve "ease-out-expo"
        }

        window-close {
            duration-ms 200
            curve "ease-out-quad"
        }

        window-movement {
            spring damping-ratio=0.7 stiffness=600 epsilon=0.0001
        }

        window-resize {
            spring damping-ratio=0.7 stiffness=600 epsilon=0.0001
        }
    }

    binds {
        Mod+Return { spawn "foot"; }
        Mod+T { spawn "foot"; }
        Mod+D { spawn "fuzzel"; }
        Mod+Q { close-window; }
        Mod+H { focus-column-left; }
        Mod+L { focus-column-right; }
        Mod+J { focus-window-down; }
        Mod+K { focus-window-up; }
        Mod+Shift+H { move-column-left; }
        Mod+Shift+L { move-column-right; }
        Mod+Shift+J { move-window-down; }
        Mod+Shift+K { move-window-up; }
        Mod+1 { switch-to-workspace 1; }
        Mod+2 { switch-to-workspace 2; }
        Mod+3 { switch-to-workspace 3; }
        Mod+Ctrl+C { quit; }
        Mod+Minus { set-column-width "-10%"; }
        Mod+Equal { set-column-width "+10%"; }
        Mod+S { screenshot; }
    }
  '';
}
