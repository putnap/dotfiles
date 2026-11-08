{
  description = "Zenful Darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    # The release binary: a source build recompiles on every nixpkgs bump.
    # `nix flake update` refetches latest, so nixr still upgrades it.
    clauth.url = "file+https://github.com/uwuclxdy/clauth/releases/latest/download/clauth-macos-aarch64";
    clauth.flake = false;
    # The last nixpkgs Hydra built atuin (18.24.2) from: 18.24.4's e2e tests fail on Hydra and here.
    nixpkgs-atuin.url = "github:NixOS/nixpkgs/f4b794aaffc0e3d45da81088d492b118224bb476";
    # home-manager.url = "github:nix-community/home-manager";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, nix-homebrew, home-manager, nixpkgs-atuin, clauth }:
    let
      system = "aarch64-darwin";
      user = "papu";
      clauthPackage = nixpkgs.legacyPackages.${system}.runCommand "clauth" {} ''
        install -Dm755 ${clauth} $out/bin/clauth
      '';
      # Rebuilds fail once nixpkgs' atuin moves past this; if Hydra built the new one
      # (hydra.nixos.org/job/nixpkgs/unstable/atuin.aarch64-darwin) unpin, else bump this.
      atuinBroken = "18.24.4";
      atuinPinned = nixpkgs.lib.throwIf (nixpkgs.legacyPackages.${system}.atuin.version != atuinBroken)
        "nixpkgs has atuin ${nixpkgs.legacyPackages.${system}.atuin.version}: unpin it in flake.nix, or set atuinBroken to that to keep the pin"
        nixpkgs-atuin.legacyPackages.${system}.atuin;
      configuration = { pkgs, config, ... }: {

        system.primaryUser = user;
        nixpkgs.config.allowUnfree = true;

        # Enable zsh (or any other shell)
        programs.zsh.enable = true;

        # List packages installed in system profile. To search by name, run:
        # $ nix-env -qaP | grep wget
        environment =
          {
            systemPackages = with pkgs;
              [
                #apps
                spotify

                # Productivity terminal stuff
                git
                stow
                jq
                dasel # TOML/JSON conversion for declarative agent settings
                lazygit
                lazydocker
                delta
                yazi
                glow
                fd
                ripgrep
                imagemagick
                neovim
                tmux
                tmux-sessionizer
                oh-my-posh
                fzf
                zoxide
                ffmpegthumbnailer
                ffmpeg
                p7zip
                poppler
                btop
                carapace
                posting
                gh
                gh-dash
                atuinPinned
                herdr
                cloudflared
                codex
                clauthPackage

                # dev SDKs
                python3
                uv
                go
                chafa
                rustc
                cargo
                rustfmt
                clippy
                rust-analyzer
                jdk25
                zig
                dotnet-sdk_10

                # mobile dev
                android-tools # adb, fastboot

                # cloud tools
                (google-cloud-sdk.withExtraComponents [
                  google-cloud-sdk.components.gke-gcloud-auth-plugin
                ])
                minikube
                kubectl
                kubernetes-helm
                kustomize

                # mac setup
                pam-reattach
              ];
            etc."pam.d/sudo_local".text = ''
              # Managed by Nix Darwin
              auth       optional       ${pkgs.pam-reattach}/lib/pam/pam_reattach.so ignore_ssh
              auth       sufficient     pam_tid.so
            '';
            etc."zshenv.local".text = ''
              if [[ -f "/opt/homebrew/bin/brew" ]] then
                eval "$(/opt/homebrew/bin/brew shellenv)"
              fi
              
              function nixr() {
                nix flake update --flake "$(readlink -f ~/.config/nix)" || return
                brew update || return
                sudo darwin-rebuild switch --flake "$(readlink -f ~/.config/nix)#mac"
              }
            '';
          };

        # Atuin's thread capture runs in its daemon. The profile path, not a store path,
        # keeps the plist unchanged across rebuilds, so nix-darwin doesn't restart it each time.
        launchd.user.agents.atuin-daemon = {
          command = "/run/current-system/sw/bin/atuin daemon start";
          environment = {
            HOME = "/Users/${user}";
            PATH = "/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
          };
          serviceConfig = {
            RunAtLoad = true;
            KeepAlive = true;
            StandardOutPath = "/Users/${user}/Library/Logs/atuin-daemon.log";
            StandardErrorPath = "/Users/${user}/Library/Logs/atuin-daemon.error.log";
          };
        };

        # --standby yields to a daemon started by hand instead of exiting into a
        # KeepAlive restart loop. Store paths stay out of the plist, as above.
        launchd.user.agents.clauth = {
          command = "/run/current-system/sw/bin/clauth daemon --standby";
          environment = {
            HOME = "/Users/${user}";
            PATH = "/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
          };
          serviceConfig = {
            RunAtLoad = true;
            KeepAlive = true;
            StandardOutPath = "/Users/${user}/Library/Logs/clauth-daemon.log";
            StandardErrorPath = "/Users/${user}/Library/Logs/clauth-daemon.error.log";
          };
        };

        fonts.packages = with pkgs;
          [
            nerd-fonts.jetbrains-mono
            sketchybar-app-font
          ];

        homebrew = {
          enable = true;
          brews = [
            "mas"
            "sketchybar"
            "borders"
            "lua"
            "switchaudio-osx"
            "media-control"
            "PeonPing/tap/peon-ping"
            "tnk-studio/tools/lazykube"
            "modem-dev/tap/hunk"
            "vite-plus"
            "bjarneo/cliamp/cliamp"
            # Prebuilt release binaries; Nix compiled these on every nixpkgs bump.
            "raine/workmux/workmux"
            "hashicorp/tap/terraform"
          ];
          taps = [
            "FelixKratz/formulae"
            "nikitabobko/tap"
          ];
          casks = [
            "android-studio"
            "stretchly"
            "ghostty"
            "claude-code@latest"
            "zen"
            "aerospace"
            "sf-symbols"
            "karabiner-elements"
            # The cask self-updates, so a plain upgrade skips it and v1 never moved to
            # v2 (the Tahoe build). Greedy makes the rebuild upgrade it anyway.
            { name = "raycast"; greedy = true; }
            "sublime-text"
            "postman"
            "visual-studio-code"
            "docker-desktop"
            "transmission"
          ];
          masApps = {
            "WhatsApp" = 310633997;
            "Windows App" = 1295203466;
          };
          onActivation.cleanup = "zap";
          onActivation.autoUpdate = false;
          onActivation.upgrade = true;
          # Homebrew 6.0 (June 2026) requires explicit trust for non-official taps.
          # nix-darwin's module can't yet emit per-tap `trusted: true`, so restore the
          # pre-6.0 behavior during activation. NOTE: transition flag, slated for removal
          # upstream — revisit once nix-darwin supports declaring tap trust.
          onActivation.extraEnv.HOMEBREW_NO_REQUIRE_TAP_TRUST = "1";
        };

        system.activationScripts.applications.text =
          let
            env = pkgs.buildEnv {
              name = "system-applications";
              paths = config.environment.systemPackages;
              pathsToLink = [ "/Applications" ];
            };
          in
          pkgs.lib.mkForce ''
            # Set up applications.
            echo "setting up /Applications..." >&2
            rm -rf /Applications/Nix\ Apps
            mkdir -p /Applications/Nix\ Apps
            find ${env}/Applications -maxdepth 1 -type l -exec readlink '{}' + |
            while read -r src; do
              app_name=$(basename "$src")
              echo "copying $src" >&2
              ${pkgs.mkalias}/bin/mkalias "$src" "/Applications/Nix Apps/$app_name"
            done

            # Dequarantine 
            xattr -r -d com.apple.quarantine /Applications/Stretchly.app
            xattr -r -d com.apple.quarantine /Applications/AeroSpace.app
          '';

        system.defaults = {
          dock = {
            autohide = true;
            show-recents = false;
            mru-spaces = false;
          };
          finder = {
            AppleShowAllExtensions = true;
            ShowPathbar = true;
            ShowStatusBar = true;
          };
          loginwindow.GuestEnabled = false;
          NSGlobalDomain = {
            AppleICUForce24HourTime = true;
            AppleInterfaceStyle = "Dark";
            AppleShowAllExtensions = true;
            KeyRepeat = 2;
            InitialKeyRepeat = 15;
            NSWindowShouldDragOnGesture = true;
            "com.apple.swipescrolldirection" = false;
            "com.apple.keyboard.fnState" = true;
            _HIHideMenuBar = true;
          };
          # macOS 26 reads these keys, not the ByHost ones system.defaults.controlcenter
          # writes. All three stay one click away in Control Centre itself.
          CustomUserPreferences."com.apple.controlcenter" = {
            "NSStatusItem VisibleCC WiFi" = false;
            "NSStatusItem VisibleCC Sound" = false;
            "NSStatusItem VisibleCC NowPlaying" = false;
          };
        };

        # Keyboard
        system.keyboard.enableKeyMapping = true;
        system.keyboard.remapCapsLockToEscape = true;

        # Custom keyboard layouts: copy real files into /Library/Keyboard Layouts.
        # macOS doesn't reliably load symlinked layouts, so we copy (not link).
        # The bundle is vendored under ./keyboard-layouts and MUST stay git-tracked
        # or the flake won't see it. After a rebuild you still have to log out/in
        # and enable "Lithuanian - Numeric" in System Settings > Keyboard >
        # Text Input > Input Sources (the enabled-sources list isn't declarative).
        system.activationScripts.postActivation.text = ''
          echo "installing custom keyboard layouts..." >&2
          install -d "/Library/Keyboard Layouts"
          rm -rf "/Library/Keyboard Layouts/lithuanian-numeric.bundle"
          cp -R "${./keyboard-layouts/lithuanian-numeric.bundle}" "/Library/Keyboard Layouts/lithuanian-numeric.bundle"

          # Run after package activation, as the owner of the dotfiles (never root).
          # Resolve the checkout through its Stowed flake, independent of shell cwd.
          echo "refreshing declarative agent setup..." >&2
          /usr/bin/sudo -H -u ${user} /usr/bin/env -i \
            HOME="/Users/${user}" USER="${user}" LOGNAME="${user}" \
            PATH="${config.system.path}/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
            ${pkgs.bash}/bin/bash -c '
              set -euo pipefail
              flake_dir=$(readlink -f "$HOME/.config/nix")
              repo=$(cd "$flake_dir/../../.." && pwd -P)
              exec bash "$repo/agents/.config/agent-setup/apply.sh" --repo "$repo" --apply --integrations
            ' || exit 1

          # The nix.gc launchd timer below never fires: every rebuild rewrites and
          # reloads its plist, which re-registers the calendar trigger from scratch
          # and drops any pending event. Collect here instead, where it always runs.
          # Count-based, not time-based, so rollback depth doesn't drift with how
          # often we rebuild. nix-collect-garbage has no +N flag, hence two steps.
          echo "collecting nix garbage..." >&2
          ${config.nix.package}/bin/nix-env -p /nix/var/nix/profiles/system --delete-generations +3
          ${config.nix.package}/bin/nix-store --gc
        '';

        # Add ability to used TouchID for sudo authentication
        security.pam.services.sudo_local.touchIdAuth = true;

        # Necessary for using flakes on this system.
        nix.settings.experimental-features = "nix-command flakes";
          # Free ⌘Space for Raycast. -dict-add edits only Spotlight's entry (64);
          # CustomUserPreferences would overwrite every other system shortcut.
          echo "disabling Spotlight's ⌘Space..." >&2
          launchctl asuser "$(id -u -- ${user})" sudo --user=${user} -- \
            defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 \
            '<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>1048576</integer></array><key>type</key><string>standard</string></dict></dict>'
          launchctl asuser "$(id -u -- ${user})" sudo --user=${user} -- \
            /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u


        # Automatic store optimization - runs weekly on Sunday at 3am
        nix.optimise = {
          automatic = true;
          interval = { Weekday = 0; Hour = 3; Minute = 0; };
        };

        # Set Git commit hash for darwin-version.
        system.configurationRevision = self.rev or self.dirtyRev or null;

        # Used for backwards compatibility, please read the changelog before changing.
        # $ darwin-rebuild changelog
        system.stateVersion = 5;

        # The platform the configuration will be used on.
        nixpkgs.hostPlatform = system;
      };
    in
    {
      darwinConfigurations.mac = nix-darwin.lib.darwinSystem {
        modules = [
          configuration
          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              user = user;
            };
          }
        ];
      };

      # # Expose the package set, including overlays, for convenience.
      # darwinPackages = self.darwinConfigurations."mac".pkgs;

      # homeConfigurations.${user} = home-manager.lib.homeManagerConfiguration {
      #   inherit pkgs;
      #   modules = [{
      #     programs.home-manager.enable = true;
      #     home = {
      #       sessionPath = [
      #         "/run/current-system/sw/bin"
      #         "$HOME/.nix-profile/bin"
      #       ];
      #       username = user;
      #       homeDirectory = "/Users/${user}";
      #       stateVersion = "25.05";
      #       activation.startBrewServices = home-manager.lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      #         export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/run/current-system/sw/bin:$HOME/.nix-profile/bin:$PATH"
      #         echo "Starting brew services..."
      #         brew services restart sketchybar
      #       '';
      #     };
      #   }];
      # };
      # apps.${system}.switchAll = {
      #   type = "app";
      #   program = builtins.toString (pkgs.writeShellScript "switch-all"
      #     ''
      #       set -e
      #       echo "Switching system configuration (nix-darwin)..."
      #       darwin-rebuild switch --flake "${toString self}#mac"
      #       echo "Switching user configuration (Home Manager)..."
      #       home-manager switch --flake "${toString self}#${user}"
      #     '');
      # };
    };
}
