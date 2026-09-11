# Keep production and previews on the same reviewed patch set.
{ pkgs, check ? true }:
pkgs.herdr.overrideAttrs (old: {
  patches = (old.patches or []) ++ [
    ./patches/herdr-pane-footer.patch
    ./patches/herdr-popup-title.patch
    ./patches/herdr-preserve-launch-flags.patch
  ];
} // pkgs.lib.optionalAttrs check {
  doCheck = true;
  nativeCheckInputs = (old.nativeCheckInputs or []) ++ [ pkgs.cargo-nextest ];
  checkPhase = ''
    runHook preCheck
    for suite in pane_footer popup_title launch_flags; do
      cargo nextest run --offline --release \
        --target ${pkgs.stdenv.hostPlatform.rust.rustcTarget} \
        --bin herdr -E "test($suite)" --no-tests=fail
    done
    runHook postCheck
  '';
})
