# Keep production and previews on the same reviewed patch set.
{ pkgs, check ? true }:
assert pkgs.herdr.version == "0.9.0";
pkgs.herdr.overrideAttrs (old: {
  patches = (old.patches or []) ++ [
    ./patches/herdr-pane-footer.patch
    ./patches/herdr-popup-title.patch
    ./patches/herdr-preserve-launch-flags.patch
  ];
} // pkgs.lib.optionalAttrs check {
  doCheck = true;
  checkPhase = ''
    cargo test --offline --release --bin herdr pane_footer
    cargo test --offline --release --bin herdr popup_title
    cargo test --offline --release --bin herdr launch_flags
  '';
})
