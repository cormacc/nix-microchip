# Runs its arguments as a command inside the MPLAB-X root filesystem. default.nix prepends
# the assignments of root (the root filesystem, merged at build time) and bwrap.
#
# The compilers must run unmodified in this environment: an autoPatchelf'd compiler detects
# the change and drops to Free mode, and a default buildFHSEnv sandbox makes xclm fail
# ("UID 0 not supported").

if [ "$#" -eq 0 ]; then
  echo "usage: ${0##*/} <command> [args...]" >&2
  exit 2
fi
# Nested wrappers run directly only when the active root filesystem contains their identity.
if [ -n "${MPLAB_X_ENV:-}" ]; then
  if [ "${#generatorBinds[@]}" -ne 0 ]; then
    printf '%s: cannot run inside environment %q; requires an IDE-bind environment\n' \
      "${0##*/}" "$MPLAB_X_ENV" >&2
    exit 1
  fi
  IFS=: read -ra environmentIds <<< "$MPLAB_X_ENV"
  for id in "${environmentIds[@]}"; do
    [ "$id" = "$environmentId" ] && exec "$@"
  done
  printf '%s: cannot run in environment %q; requires environment %q\n' \
    "${0##*/}" "$MPLAB_X_ENV" "$environmentId" >&2
  exit 1
fi

generatorBinds=()
if [ -n "$generatorBindList" ]; then
  while IFS=$'\t' read -r source target; do
    generatorBinds+=("$source" "$target")
  done < "$generatorBindList"
  generatorBinds+=("$root$mplabxDir/packs" "$mplabxDir/packs")
  generatorBinds+=("$root$mplabxDir/sys" "$mplabxDir/sys")
fi

shopt -s dotglob nullglob

# uid 0 is the mapping with which the PRO licence probes passed. The new root is a tmpfs
# that is private to this call, so concurrent calls (e.g. make -j) do not interfere.
args=(--unshare-user --uid 0 --gid 0 --tmpfs /)

# Every mount that xclm sees as a block device costs each compiler call one `ls` of
# <mount>/license/, so the environment binds only these host trees (writable) and the
# working directory. Other top-level host entries (e.g. /boot, /mnt) are not visible.
# A tree that is absent (e.g. /home in the Nix build sandbox) is skipped.
declare -A top=([root]=1)
for d in dev home nix proc run sys tmp var; do
  top[$d]=1
  [ -e "/$d" ] || continue
  if [ "$d" = dev ]; then
    args+=(--dev-bind /dev /dev)
  else
    args+=(--bind "/$d" "/$d")
  fi
done
args+=(--symlink "$HOME" /root)

# merge DIR ALIAS SUB: give DIR the entries of the root filesystem and of the host, with
# the precedence of an overlay mount: an entry of the root filesystem hides the host entry,
# unless both are real directories, which are merged. A host-only entry is a symlink into
# ALIAS, a bind of the host's top-level directory, because an own bind for each entry would
# be a block-device mount (see above). SUB is DIR below that top-level directory.
merge() {
  local dir=$1 alias=$2 sub=$3 p h name
  local -A seen=()
  for p in "$root$dir"/*; do
    name=${p##*/}
    seen[$name]=1
    h=$dir/$name
    if [ "${#generatorBinds[@]}" -ne 0 ] && [[ $h = /opt/microchip || $h = /opt/microchip/mplabx || $h = "$mplabxDir" ]]; then
      args+=(--dir "$h")
      [ "$h" = "$mplabxDir" ] || merge "$h" "$alias" "$sub/$name"
    elif [[ -d $p && ! -L $p && -d $h && ! -L $h ]]; then
      args+=(--dir "$h")
      merge "$h" "$alias" "$sub/$name"
    else
      args+=(--symlink "$p" "$h")
    fi
  done
  for h in "$dir"/*; do
    name=${h##*/}
    [[ -n ${seen[$name]:-} ]] && continue
    args+=(--symlink "$alias$sub/$name" "$h")
    need_alias=1
  done
}

for p in "$root"/*; do
  name=${p##*/}
  h=/$name
  [[ -n ${top[$name]:-} ]] && continue
  # The build sandbox has no /opt. Generator bind targets need real parent directories.
  if [[ -d $p && ! -L $p ]] && { [[ -d $h && ! -L $h ]] || { [ "${#generatorBinds[@]}" -ne 0 ] && [ "$h" = /opt ]; }; }; then
    need_alias=
    args+=(--dir "$h")
    merge "$h" "/.host-$name" ""
    if [ -n "$need_alias" ]; then
      args+=(--ro-bind "$h" "/.host-$name")
    fi
  else
    args+=(--symlink "$p" "$h")
  fi
done

# Without this bind, a working directory outside the trees above (e.g. a CI checkout under
# /builds) is not visible.
case "$PWD" in
  /dev|/dev/*|/home|/home/*|/nix|/nix/*|/proc|/proc/*|/run|/run/*|/sys|/sys/*|/tmp|/tmp/*|/var|/var/*) ;;
  *) args+=(--bind "$PWD" "$PWD") ;;
esac
for ((index = 0; index < ${#generatorBinds[@]}; index += 2)); do
  args+=(--ro-bind "${generatorBinds[index]}" "${generatorBinds[index + 1]}")
done
args+=(--remount-ro /)

export MPLAB_X_ENV=$environmentIdentityList
# The 32-bit loader does not search /lib32 by itself (sim30 needs libstdc++ from there).
# 64-bit programs skip the 32-bit libraries in it.
export LD_LIBRARY_PATH="/lib32${LD_LIBRARY_PATH:+:}${LD_LIBRARY_PATH:-}"
# --args reads the arguments from a file descriptor. The argument count grows with the
# host's /etc and /usr, and the kernel limits the size of a command line. bwrap closes the
# descriptor; a redirection on the bwrap command itself would leak bash's copy (fd 63) to
# the command.
exec 3< <(printf '%s\0' "${args[@]}")
exec "$bwrap" --args 3 --chdir "$PWD" -- "$@"
