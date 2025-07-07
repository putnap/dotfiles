{
  description = "Zenful Darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    # home-manager.url = "github:nix-community/home-manager";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, nix-homebrew, home-manager }:
    let
      system = "aarch64-darwin";
      user = "papu";
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
                # Productivity terminal stuff
                git
                stow
                lazygit
                lazydocker
                delta
                yazi
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

                # dev SDKs
                python3
                pipx
                uv
                go
                chafa
                cargo
                nodejs
                pnpm
                yarn
                jdk
                zig
                elixir

                # cloud tools
                google-cloud-sdk
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
                nix flake update --flake "$(readlink -f ~/.config/nix)"
                sudo darwin-rebuild switch --flake "$(readlink -f ~/.config/nix)#mac"
              }
            '';
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
            "nowplaying-cli"
          ];
          taps = [
            "FelixKratz/formulae"
            "nikitabobko/tap"
            "homebrew/services"
          ];
          casks = [
            "stretchly"
            "ghostty"
            "aerospace"
            "sf-symbols"
            "karabiner-elements"
            "raycast"
          ];
          masApps = { };
          onActivation.cleanup = "zap";
          onActivation.autoUpdate = true;
          onActivation.upgrade = true;
        };

        system.activationScripts.applications.text =
          let
            env = pkgs.buildEnv {
              name = "system-applications";
              paths = config.environment.systemPackages;
              pathsToLink = "/Applications";
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
          dock.autohide = true;
          loginwindow.GuestEnabled = false;
          finder.AppleShowAllExtensions = true;
          NSGlobalDomain.AppleICUForce24HourTime = true;
          NSGlobalDomain.AppleInterfaceStyle = "Dark";
          NSGlobalDomain.KeyRepeat = 2;
          NSGlobalDomain.NSWindowShouldDragOnGesture = true;
          NSGlobalDomain."com.apple.swipescrolldirection" = false;
        };

        # Keyboard
        system.keyboard.enableKeyMapping = true;
        system.keyboard.remapCapsLockToEscape = true;

        # Add ability to used TouchID for sudo authentication
        security.pam.services.sudo_local.touchIdAuth = true;

        # Necessary for using flakes on this system.
        nix.settings.experimental-features = "nix-command flakes";

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
