# Sourced by launch.sh and setup.sh (bash). Loads the optional config file
#   ${GEONIX_CONFIG:-${XDG_CONFIG_HOME:-~/.config}/geonix/geonix.env}
# made of KEY=VALUE lines (blank lines and # comments are ignored, values may
# be quoted, a leading ~ or $HOME is expanded). Only GEONIX_* keys are read,
# and a variable that is already set in the environment always wins.
geonix_load_config() {
  local file="${GEONIX_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/geonix/geonix.env}"
  [ -f "$file" ] || return 0
  local line key value
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in '' | '#'*) continue ;; esac
    line="${line#export }"
    case "$line" in *=*) ;; *) continue ;; esac
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in GEONIX_*) ;; *) continue ;; esac
    case "$key" in *[!A-Z0-9_]*) continue ;; esac
    case "$value" in
      \"*\") value="${value#\"}"; value="${value%\"}" ;;
      \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    case "$value" in '~' | '~/'*) value="$HOME${value#\~}" ;; esac
    value="${value//\$\{HOME\}/$HOME}"
    value="${value//\$HOME/$HOME}"
    [ -n "${!key:-}" ] && continue
    export "$key=$value"
  done <"$file"
}
