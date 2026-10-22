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

## Disk space

The Microchip packages fill the Nix store quickly. `mplab-x-unwrapped` 6.35 writes 1.97 GB, and its separate optional `.packs` derivation writes 14.04 GB; an XC32 6.00 installation is about 9 GB. On 2026-10-22, garbage collection between worker rounds freed 93 to 234 GiB each time, and the user's manual cleanups during the same work freed more than 500 GB (534 GB in one run, user report). One round of parallel workers can use more than 500 GB. Monitor and clean up without a request from the user:

- Run `df -h /nix/store` before each build that runs an installer or builds `mplab-x`, and before you delegate build work. If less than 300 GB is free, clean up before you build.
- While workers build, check `df -h /nix/store` at each collect: use collect timeouts of 15 minutes or less, not one long wait. If less than 200 GB is free, stop new build work and clean up at the next safe point.
- Clean up after each build round, whatever the free space.
- Record `df -h /nix/store` before and after each garbage collection, and report both. The "freed" figure from `nix-collect-garbage` alone is not evidence that the disk has space.
- Evaluate this repository as a Git flake: `.#attr`, `git+file://<dir>`, or `builtins.getFlake ("git+file://" + toString <dir>)`. Never use `builtins.getFlake (toString <dir>)` or a `path:` reference to the repository: that copies the whole directory, including the gitignored `.tmp/`, into the store on each evaluation (measured 2026-10-22: 33 GB for each copy, against 376 KB for `git+file://`). On 2026-10-22 such copies used 384 GiB in about an hour. A `path:` reference to a small directory under `.tmp/` is acceptable.
- To find such copies, list large `-source` paths: `nix-shell -p sqlite --run "sqlite3 -readonly 'file:/nix/var/nix/db/db.sqlite?immutable=1' \"select path from ValidPaths where path like '%-source' and narSize > 1073741824;\""`. Delete each with `nix-store --delete <path>`, which refuses a path that is still in use.
- Out-links from `nix build -o` are GC roots. Use `--no-link` unless a later step reads the out-link, and delete each out-link when the step that reads it is finished.
- Clean up between build rounds, not while a build that you or a worker needs is running: garbage collection deletes a finished output that has no root.
  1. Save the list of out-links under `.tmp/` to a file: `nix-store --gc --print-roots | grep "$PWD/.tmp/"`.
  2. Delete each listed symlink, except those in `.tmp/gcroots/`.
  3. Remove finished worktrees under `.tmp/herdr-orch/worktrees/` with `git worktree remove`.
  4. Run `nix-collect-garbage -d`. The `-d` option also deletes old profile generations; the user accepts this.
- Keep only the `mplab-x-unwrapped` root in `.tmp/gcroots/` (`nix build '.#mplab-x-unwrapped' --out-link .tmp/gcroots/mplab-x-unwrapped`). Build `.packs` with `--no-link` only when needed. Without the IDE root, garbage collection deletes the IDE, and the next build runs the installer again.
- Delete large scratch files under `.tmp/` (e.g. extracted installers) when the task that made them is finished.
- In a delegated build assignment, tell the worker to run `df` before each large build, to delete its out-links when it no longer needs them, and to stop with BLOCKED if less than 150 GB is free. The parent runs garbage collection.

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
