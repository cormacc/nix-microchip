# Agent guide

This flake packages proprietary Microchip tools for `x86_64-linux`. Read [README.org](README.org) for usage and packaging instructions, and [TASKS.org](TASKS.org) for outstanding work.

## Layout

- `flake.nix` exports packages and the overlay; `pkgs/default.nix` registers versions and defaults.
- `pkgs/<tool>/<version>.nix` contains the version and installer hash; `common.nix` contains shared packaging logic.
- `pkgs/mplab-x/default.nix` provides the runtime environment, compiler wrappers, `mplab-x-run` and `mplab-make`. `pkgs/mplab-x/run.sh` builds the environment with bubblewrap.

## Changes

- Follow the existing version-file pattern. Change default versions or `flake.lock` only when requested.
- Retain only the latest verified MPLAB-X version; remove superseded IDE version files and exports when upgrading. Keep legacy compiler versions for reproducible firmware builds.
- Preserve compiler payloads: ELF patching can trigger licence checks and disable PRO optimisations. See README.org's licence probes.
- Keep private downstream project details out of public documentation and task records.
- Use `.tmp/` for experiments. Keep Markdown and Org paragraphs on one logical line.

## Verification

- Build changed packages and affected wrappers, e.g. `nix build '.#mplab-x'`.
- Test runtime changes with a representative compile and link; check licence diagnostics as well as exit status. Use `mplab-make` for MPLAB-generated makefiles.
- Runtime probes need unprivileged user namespaces. Report GUI checks separately from CLI checks.
- Run `nix flake check --no-build`; distinguish existing failures recorded in TASKS.org from regressions.
