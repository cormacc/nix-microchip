# Agent guide

This flake packages proprietary Microchip tools for `x86_64-linux`. Read [README.org](README.org) for usage and packaging instructions, and [TASKS.org](TASKS.org) for outstanding work.

## Layout

- `flake.nix` exports packages and the overlay; `pkgs/default.nix` registers versions and defaults.
- `pkgs/<tool>/<version>.nix` contains the version and installer hash; `common.nix` contains shared packaging logic.
- `pkgs/mplab-x/rootfs.nix` builds the shared runtime filesystem and command wrappers. `pkgs/xc-cli/default.nix` provides the compiler-only environment. `pkgs/mplab-x/default.nix` provides the IDE environment. `pkgs/mplab-x/run.sh` builds each environment with bubblewrap.

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

## Regression testing

Test compilers in `xc-cli`, and also in `mplab-x` when the change affects it. For each compiler, compile and link one test file, and run the README.org licence probe for a licensed compiler. Choose one level:

- Basic, for most changes: one licensed compiler, the production default XC16 (`xc16_1_61`), and one licence-free compiler, the latest XC-DSC (`xc-dsc_4_00`, which needs a DFP).
- Thorough, for changes to `pkgs/mplab-x/rootfs.nix`, `run.sh`, the FHS library lists or `flake.lock`: one version of each compiler: the production default XC16 (`xc16_1_61`, used in place of the latest XC16), and the latest `xc8_4_00`, `xc32_6_00` and `xc-dsc_4_00`.

Do not test every packaged version. Also test each release below whose concern the change touches. Add a release to this list, with its reason, when it needs special treatment.

- `xc16_1_21`: the only 32-bit compiler, so it tests `/lib32` and the 32-bit FHS libraries. Its `xclm -status` has no `Mode: PRO` line, so use the `-O3` probe.
- `xc8_3_10`: a licensed XC8 for licence changes. Its Free-mode diagnostic `(2051)` does not change the exit status. It needs a DFP.
- `xc32_5_10`: the only licensed XC32, for licence changes. `xclm -status` shows `Mode: cpp`, not `Mode: PRO`.
- `xc-dsc_3_31`: the only licensed XC-DSC, for licence changes. It uses the `swxc16-pro` feature, and it needs a DFP for newer devices (e.g. dsPIC33CK64MP105).
