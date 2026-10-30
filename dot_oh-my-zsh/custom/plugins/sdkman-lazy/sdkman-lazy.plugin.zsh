# Keep installed SDKs available without initializing SDKMAN.
export SDKMAN_DIR="${SDKMAN_DIR:-$HOME/.sdkman}"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] || return

() {
  local candidate_dir candidate_name candidate_bin home_var
  for candidate_dir in "$SDKMAN_DIR"/candidates/*/current(N/); do
    candidate_name=${candidate_dir:h:t}
    home_var="${(U)candidate_name}_HOME"
    export "$home_var=$candidate_dir"
    candidate_bin=$candidate_dir
    [[ -d "$candidate_dir/bin" ]] && candidate_bin="$candidate_dir/bin"
    (( ${path[(Ie)$candidate_bin]} )) || path=("$candidate_bin" $path)
  done
  export PATH
}

autoload -Uz add-zsh-hook

_sdkman_lazy_load() {
  add-zsh-hook -d chpwd _sdkman_lazy_check
  unfunction sdk
  source "$SDKMAN_DIR/bin/sdkman-init.sh"
}

sdk() {
  _sdkman_lazy_load
  (( $+functions[sdk] )) || return 1
  sdk "$@"
}

_sdkman_lazy_check() {
  if [[ -f .sdkmanrc ]]; then
    _sdkman_lazy_load
  fi
}

add-zsh-hook chpwd _sdkman_lazy_check
# SDKMAN also applies .sdkmanrc when a terminal starts inside a project.
_sdkman_lazy_check
