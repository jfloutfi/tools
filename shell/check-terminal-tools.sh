#!/usr/bin/env zsh

# check-terminal-tools.sh
#
# Checks the terminal/tooling environment on macOS and Linux.
#
# Reports:
#   - installation status
#   - version
#   - package/install source
#   - executable path
#
# Supported package ecosystems:
#
# macOS:
#   - macOS system
#   - Homebrew formulae
#   - Homebrew casks
#
# Linux:
#   - Debian / Ubuntu / Mint / Pop!_OS (apt/dpkg)
#   - Fedora / RHEL (dnf/rpm)
#   - openSUSE (zypper/rpm)
#   - Arch / Manjaro / EndeavourOS (pacman)
#   - Alpine (apk)
#   - Nix
#   - Cargo
#   - npm
#   - ~/.local/bin
#
# Requires zsh.

# ------------------------------------------------------------------------------
# PATH
# ------------------------------------------------------------------------------

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

setopt NO_NOMATCH

# ------------------------------------------------------------------------------
# Color support
# ------------------------------------------------------------------------------

USE_COLOR=0

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
  USE_COLOR=1
fi

# Optional overrides:
#
#   FORCE_COLOR=1 ./check-terminal-tools.sh
#   NO_COLOR=1    ./check-terminal-tools.sh

if [[ "${FORCE_COLOR:-0}" == "1" ]]; then
  USE_COLOR=1
fi

if (( USE_COLOR )); then

  RESET=$'\033[0m'

  # Status
  COLOR_INSTALLED=$'\033[38;2;46;204;113m'
  COLOR_MISSING=$'\033[38;2;255;95;86m'
  COLOR_WARNING=$'\033[38;2;255;189;46m'
  COLOR_SKIPPED=$'\033[38;2;120;120;120m'

  # Package managers / platforms
  COLOR_BREW=$'\033[38;2;251;176;64m'
  COLOR_MACOS=$'\033[38;2;180;180;180m'

  # Debian
  COLOR_DEBIAN=$'\033[38;2;206;0;86m'

  # Ubuntu
  COLOR_UBUNTU=$'\033[38;2;233;84;32m'

  # Linux Mint
  COLOR_MINT=$'\033[38;2;134;190;67m'

  # Pop!_OS
  COLOR_POP=$'\033[38;2;72;185;199m'

  # Fedora
  COLOR_FEDORA=$'\033[38;2;60;110;180m'

  # openSUSE
  COLOR_SUSE=$'\033[38;2;115;186;37m'

  # Arch
  COLOR_ARCH=$'\033[38;2;23;147;209m'

  # Alpine
  COLOR_ALPINE=$'\033[38;2;13;89;127m'

  # Nix
  COLOR_NIX=$'\033[38;2;126;186;228m'

  # Rust / Cargo
  COLOR_CARGO=$'\033[38;2;222;165;132m'

  # npm
  COLOR_NPM=$'\033[38;2;203;56;55m'

  COLOR_MANUAL=$'\033[38;2;145;145;145m'

else

  RESET=""

  COLOR_INSTALLED=""
  COLOR_MISSING=""
  COLOR_WARNING=""
  COLOR_SKIPPED=""

  COLOR_BREW=""
  COLOR_MACOS=""

  COLOR_DEBIAN=""
  COLOR_UBUNTU=""
  COLOR_MINT=""
  COLOR_POP=""
  COLOR_FEDORA=""
  COLOR_SUSE=""
  COLOR_ARCH=""
  COLOR_ALPINE=""
  COLOR_NIX=""
  COLOR_CARGO=""
  COLOR_NPM=""

  COLOR_MANUAL=""

fi

# ------------------------------------------------------------------------------
# OS / distribution detection
# ------------------------------------------------------------------------------

OS="$(/usr/bin/uname -s 2>/dev/null || uname -s)"

DISTRO_NAME=""
DISTRO_ID=""
DISTRO_LIKE=""
DISTRO_FAMILY=""

detect_linux_distro() {
  [[ "$OS" != "Linux" ]] && return

  if [[ -r /etc/os-release ]]; then
    local key
    local value

    while IFS='=' read -r key value; do
      value="${value#\"}"
      value="${value%\"}"
      value="${value#\'}"
      value="${value%\'}"

      case "$key" in
        PRETTY_NAME)
          DISTRO_NAME="$value"
          ;;

        ID)
          DISTRO_ID="$value"
          ;;

        ID_LIKE)
          DISTRO_LIKE="$value"
          ;;
      esac
    done < /etc/os-release
  fi

  [[ -z "$DISTRO_NAME" ]] && DISTRO_NAME="Linux"

  local family_string=" ${DISTRO_ID:l} ${DISTRO_LIKE:l} "

  case "$family_string" in
    *opensuse*|*suse*)
      DISTRO_FAMILY="suse"
      ;;

    *fedora*|*rhel*|*centos*)
      DISTRO_FAMILY="fedora"
      ;;

    *debian*|*ubuntu*)
      DISTRO_FAMILY="debian"
      ;;

    *arch*)
      DISTRO_FAMILY="arch"
      ;;

    *alpine*)
      DISTRO_FAMILY="alpine"
      ;;

    *)
      DISTRO_FAMILY="unknown"
      ;;
  esac
}

detect_linux_distro

# ------------------------------------------------------------------------------
# Color selection
# ------------------------------------------------------------------------------

status_color_for() {
  local tool_status="$1"

  case "$tool_status" in
    installed)
      print -rn -- "$COLOR_INSTALLED"
      ;;

    missing)
      print -rn -- "$COLOR_MISSING"
      ;;

    "no cmd")
      print -rn -- "$COLOR_WARNING"
      ;;

    *)
      print -rn -- "$COLOR_MANUAL"
      ;;
  esac
}

debian_family_color() {
  case "${DISTRO_ID:l}" in
    ubuntu)
      print -rn -- "$COLOR_UBUNTU"
      ;;

    linuxmint)
      print -rn -- "$COLOR_MINT"
      ;;

    pop|pop_os)
      print -rn -- "$COLOR_POP"
      ;;

    debian)
      print -rn -- "$COLOR_DEBIAN"
      ;;

    *)
      case "${DISTRO_LIKE:l}" in
        *ubuntu*)
          print -rn -- "$COLOR_UBUNTU"
          ;;

        *debian*)
          print -rn -- "$COLOR_DEBIAN"
          ;;

        *)
          print -rn -- "$COLOR_DEBIAN"
          ;;
      esac
      ;;
  esac
}

source_color_for() {
  local source="$1"

  case "$source" in

    brew\ formula:*|brew\ cask:*)
      print -rn -- "$COLOR_BREW"
      ;;

    "macOS system")
      print -rn -- "$COLOR_MACOS"
      ;;

    apt/dpkg:*|dpkg:*|nala/dpkg:*|aptitude/dpkg:*)
      debian_family_color
      ;;

    dnf/rpm:*|yum/rpm:*)
      print -rn -- "$COLOR_FEDORA"
      ;;

    zypper/rpm:*)
      print -rn -- "$COLOR_SUSE"
      ;;

    pacman:*)
      print -rn -- "$COLOR_ARCH"
      ;;

    apk:*)
      print -rn -- "$COLOR_ALPINE"
      ;;

    nix)
      print -rn -- "$COLOR_NIX"
      ;;

    cargo)
      print -rn -- "$COLOR_CARGO"
      ;;

    npm)
      print -rn -- "$COLOR_NPM"
      ;;

    brew\ prefix/manual|unknown/manual|~/.local/bin)
      print -rn -- "$COLOR_MANUAL"
      ;;

    *)
      print -rn -- "$COLOR_MANUAL"
      ;;
  esac
}

# ------------------------------------------------------------------------------
# Generic command helpers
# ------------------------------------------------------------------------------

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

command_path() {
  local cmd="$1"
  local resolved=""

  resolved="$(whence -p "$cmd" 2>/dev/null)"

  if [[ -z "$resolved" ]]; then
    resolved="$(command -v "$cmd" 2>/dev/null)"
  fi

  print -r -- "$resolved"
}

resolve_command() {
  local candidates="$1"
  local candidate

  for candidate in ${=candidates}; do
    if command_exists "$candidate"; then
      print -r -- "$candidate"
      return 0
    fi
  done

  return 1
}

first_line_from_output() {
  local output="$1"

  print -r -- "${output%%$'\n'*}"
}

# ------------------------------------------------------------------------------
# Version handling
# ------------------------------------------------------------------------------

clean_version_output() {
  local output="$1"
  local line=""

  line="$(first_line_from_output "$output")"

  # Version column intentionally contains ONLY the numeric version.
  #
  # Examples:
  #
  #   Ghostty 1.3.1
  #       -> 1.3.1
  #
  #   git version 2.50.1 (Apple Git)
  #       -> 2.50.1
  #
  #   jq-1.8.2
  #       -> 1.8.2
  #
  #   codex-cli 0.150.1
  #       -> 0.150.1

  if [[ "$line" =~ '([0-9]+([.][0-9]+)+)' ]]; then
    print -r -- "$match[1]"
  else
    print -r -- "-"
  fi
}

get_command_version() {
  local cmd="$1"
  local output=""

  case "$cmd" in
    pbcopy|pbpaste)
      print -r -- "-"
      return
      ;;
  esac

  output="$("$cmd" --version 2>/dev/null)"

  if [[ -n "$output" ]]; then
    clean_version_output "$output"
    return
  fi

  print -r -- "-"
}

# ------------------------------------------------------------------------------
# Homebrew
# ------------------------------------------------------------------------------

find_brew() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    print -r -- "/opt/homebrew/bin/brew"
    return 0
  fi

  if [[ -x /usr/local/bin/brew ]]; then
    print -r -- "/usr/local/bin/brew"
    return 0
  fi

  if command_exists brew; then
    command_path brew
    return 0
  fi

  return 1
}

BREW_CMD="$(find_brew 2>/dev/null)"
BREW_PREFIX=""

if [[ -n "$BREW_CMD" ]]; then
  BREW_PREFIX="$("$BREW_CMD" --prefix 2>/dev/null)"
fi

typeset -A BREW_SOURCE_CACHE
typeset -A BREW_VERSION_CACHE

cache_brew_package() {
  local pkg="$1"

  if (( ${+BREW_SOURCE_CACHE[$pkg]} )); then
    return
  fi

  local brew_source=""
  local brew_version=""
  local version_output=""

  if [[ -n "$BREW_CMD" ]]; then

    if "$BREW_CMD" list --formula "$pkg" >/dev/null 2>&1; then
      brew_source="brew formula: $pkg"

      version_output="$(
        "$BREW_CMD" list --versions "$pkg" 2>/dev/null
      )"

      brew_version="$(clean_version_output "$version_output")"

    elif "$BREW_CMD" list --cask "$pkg" >/dev/null 2>&1; then
      brew_source="brew cask: $pkg"

      version_output="$(
        "$BREW_CMD" list --cask --versions "$pkg" 2>/dev/null
      )"

      brew_version="$(clean_version_output "$version_output")"
    fi

  fi

  BREW_SOURCE_CACHE[$pkg]="$brew_source"
  BREW_VERSION_CACHE[$pkg]="$brew_version"
}

brew_package_source() {
  local pkg="$1"

  cache_brew_package "$pkg"

  print -r -- "${BREW_SOURCE_CACHE[$pkg]}"
}

brew_package_version() {
  local pkg="$1"

  cache_brew_package "$pkg"

  print -r -- "${BREW_VERSION_CACHE[$pkg]}"
}

# ------------------------------------------------------------------------------
# Package source detection
# ------------------------------------------------------------------------------

DETECTED_SOURCE=""
DETECTED_PACKAGE_VERSION=""

detect_package_info() {
  local tool_path="$1"
  local brew_pkg="$2"

  DETECTED_SOURCE="unknown/manual"
  DETECTED_PACKAGE_VERSION="-"

  # --------------------------------------------------------------------------
  # macOS
  # --------------------------------------------------------------------------

  if [[ "$OS" == "Darwin" ]]; then

    # macOS system tools
    if [[ "$tool_path" == /usr/bin/* ||
          "$tool_path" == /bin/* ||
          "$tool_path" == /usr/sbin/* ||
          "$tool_path" == /sbin/* ]]; then

      DETECTED_SOURCE="macOS system"
      return
    fi

    local brew_source=""
    local brew_version=""

    brew_source="$(brew_package_source "$brew_pkg")"
    brew_version="$(brew_package_version "$brew_pkg")"

    # Homebrew formula executables
    if [[ -n "$BREW_PREFIX" &&
          "$tool_path" == "$BREW_PREFIX"/* &&
          -n "$brew_source" ]]; then

      DETECTED_SOURCE="$brew_source"
      DETECTED_PACKAGE_VERSION="${brew_version:--}"
      return
    fi

    # Homebrew cask applications
    if [[ "$tool_path" == /Applications/* &&
          "$brew_source" == "brew cask:"* ]]; then

      DETECTED_SOURCE="$brew_source"
      DETECTED_PACKAGE_VERSION="${brew_version:--}"
      return
    fi

    # Manual installation located under a common Homebrew prefix
    if [[ "$tool_path" == /opt/homebrew/* ||
          "$tool_path" == /usr/local/* ]]; then

      DETECTED_SOURCE="brew prefix/manual"
      return
    fi
  fi

  # --------------------------------------------------------------------------
  # Linux
  # --------------------------------------------------------------------------

  if [[ "$OS" == "Linux" ]]; then

    # ------------------------------------------------------------------------
    # Debian / Ubuntu / Mint / Pop!_OS
    # ------------------------------------------------------------------------

    if command_exists dpkg; then
      local dpkg_output=""
      local pkg=""

      dpkg_output="$(dpkg -S "$tool_path" 2>/dev/null)"

      if [[ -n "$dpkg_output" ]]; then
        dpkg_output="${dpkg_output%%$'\n'*}"
        pkg="${dpkg_output%%:*}"

        DETECTED_SOURCE="apt/dpkg: $pkg"

        if command_exists dpkg-query; then
          local package_version=""

          package_version="$(
            dpkg-query \
              -W \
              -f='${Version}' \
              "$pkg" \
              2>/dev/null
          )"

          if [[ -n "$package_version" ]]; then
            DETECTED_PACKAGE_VERSION="$(
              clean_version_output "$package_version"
            )"
          fi
        fi

        return
      fi
    fi

    # ------------------------------------------------------------------------
    # Arch / Manjaro / EndeavourOS
    # ------------------------------------------------------------------------

    if command_exists pacman; then
      local pacman_output=""
      local package_words
      local pkg=""

      pacman_output="$(pacman -Qo "$tool_path" 2>/dev/null)"

      if [[ -n "$pacman_output" &&
            "$pacman_output" != *"error:"* ]]; then

        package_words=("${(@z)pacman_output}")
        pkg="${package_words[-2]}"

        DETECTED_SOURCE="pacman: $pkg"

        local package_info=""

        package_info="$(pacman -Q "$pkg" 2>/dev/null)"

        if [[ -n "$package_info" ]]; then
          DETECTED_PACKAGE_VERSION="$(
            clean_version_output "$package_info"
          )"
        fi

        return
      fi
    fi

    # ------------------------------------------------------------------------
    # Fedora / RHEL / openSUSE / RPM-based systems
    # ------------------------------------------------------------------------

    if command_exists rpm; then
      local rpm_package=""

      rpm_package="$(rpm -qf "$tool_path" 2>/dev/null)"

      if [[ -n "$rpm_package" &&
            "$rpm_package" != *"not owned"* &&
            "$rpm_package" != *"is not owned"* ]]; then

        case "$DISTRO_FAMILY" in

          fedora)
            DETECTED_SOURCE="dnf/rpm: $rpm_package"
            ;;

          suse)
            DETECTED_SOURCE="zypper/rpm: $rpm_package"
            ;;

          *)
            if command_exists dnf; then
              DETECTED_SOURCE="dnf/rpm: $rpm_package"
            elif command_exists zypper; then
              DETECTED_SOURCE="zypper/rpm: $rpm_package"
            elif command_exists yum; then
              DETECTED_SOURCE="yum/rpm: $rpm_package"
            else
              DETECTED_SOURCE="rpm: $rpm_package"
            fi
            ;;
        esac

        local rpm_version=""

        rpm_version="$(
          rpm \
            -q \
            --qf '%{VERSION}\n' \
            "$rpm_package" \
            2>/dev/null
        )"

        if [[ -n "$rpm_version" ]]; then
          DETECTED_PACKAGE_VERSION="$(
            clean_version_output "$rpm_version"
          )"
        fi

        return
      fi
    fi

    # ------------------------------------------------------------------------
    # Alpine
    # ------------------------------------------------------------------------

    if command_exists apk; then
      local apk_output=""
      local pkg=""

      apk_output="$(apk info -W "$tool_path" 2>/dev/null)"

      if [[ -n "$apk_output" ]]; then
        pkg="${apk_output##* is owned by }"

        DETECTED_SOURCE="apk: $pkg"

        DETECTED_PACKAGE_VERSION="$(
          clean_version_output "$pkg"
        )"

        return
      fi
    fi
  fi

  # --------------------------------------------------------------------------
  # Common user install locations
  # --------------------------------------------------------------------------

  if [[ "$tool_path" == "$HOME/.cargo/bin/"* ]]; then
    DETECTED_SOURCE="cargo"
    return
  fi

  if [[ "$tool_path" == "$HOME/.local/bin/"* ]]; then
    DETECTED_SOURCE="~/.local/bin"
    return
  fi

  if [[ "$tool_path" == "$HOME/.npm-global/"* ||
        "$tool_path" == *"/node_modules/"* ]]; then

    DETECTED_SOURCE="npm"
    return
  fi

  if [[ "$tool_path" == /nix/store/* ]]; then
    DETECTED_SOURCE="nix"
    return
  fi
}

# ------------------------------------------------------------------------------
# Table output
# ------------------------------------------------------------------------------

print_section() {
  print
  print "┌─ $1"

  print "├────────────────────┬────────────┬────────────────┬────────────────────────────────────┬──────────────────────────────────────────────"

  printf \
    "│ %-18s │ %-10s │ %-14s │ %-34s │ %s\n" \
    "Tool" \
    "Status" \
    "Version" \
    "Source" \
    "Path"

  print "├────────────────────┼────────────┼────────────────┼────────────────────────────────────┼──────────────────────────────────────────────"
}

end_section() {
  print "└────────────────────┴────────────┴────────────────┴────────────────────────────────────┴──────────────────────────────────────────────"
}

print_row() {
  local tool="$1"
  local tool_status="$2"
  local version="$3"
  local source="$4"
  local tool_path="$5"

  local status_color=""
  local source_color=""

  status_color="$(status_color_for "$tool_status")"
  source_color="$(source_color_for "$source")"

  # Escape sequences are printed outside the %-width expressions.
  # This prevents ANSI colors from breaking table alignment.

  printf "│ %-18s │ " "$tool"

  printf \
    "%s%-10s%s" \
    "$status_color" \
    "$tool_status" \
    "$RESET"

  printf " │ %-14s │ " "$version"

  printf \
    "%s%-34.34s%s" \
    "$source_color" \
    "$source" \
    "$RESET"

  printf " │ %s\n" "$tool_path"
}

# ------------------------------------------------------------------------------
# Tool checking
# ------------------------------------------------------------------------------

check_tool() {
  local display_name="$1"
  local command_candidates="$2"
  local brew_pkg="$3"
  local platform="$4"

  local cmd=""

  cmd="$(resolve_command "$command_candidates" 2>/dev/null)"

  # Command exists
  if [[ -n "$cmd" ]]; then
    local tool_path=""
    local version=""

    tool_path="$(command_path "$cmd")"
    version="$(get_command_version "$cmd")"

    detect_package_info "$tool_path" "$brew_pkg"

    # Package-manager version fallback
    if [[ "$version" == "-" &&
          "$DETECTED_PACKAGE_VERSION" != "-" ]]; then

      version="$DETECTED_PACKAGE_VERSION"
    fi

    print_row \
      "$display_name" \
      "installed" \
      "$version" \
      "$DETECTED_SOURCE" \
      "$tool_path"

    return
  fi

  # No executable, but perhaps an installed Homebrew cask
  if [[ "$OS" == "Darwin" && -n "$BREW_CMD" ]]; then
    local brew_source=""
    local brew_version=""

    brew_source="$(brew_package_source "$brew_pkg")"
    brew_version="$(brew_package_version "$brew_pkg")"

    if [[ -n "$brew_source" ]]; then
      print_row \
        "$display_name" \
        "no cmd" \
        "${brew_version:--}" \
        "$brew_source" \
        "-"

      return
    fi
  fi

  # Missing
  print_row \
    "$display_name" \
    "missing" \
    "-" \
    "$platform" \
    "-"
}

# ------------------------------------------------------------------------------
# Report
# ------------------------------------------------------------------------------

print
print "Terminal tools check"
print "OS:       $OS"

if [[ "$OS" == "Linux" ]]; then
  print "Distro:   $DISTRO_NAME"

  if [[ -n "$DISTRO_FAMILY" ]]; then
    print "Family:   $DISTRO_FAMILY"
  fi
fi

if [[ -n "$BREW_CMD" ]]; then
  print "Homebrew: $BREW_CMD"
fi

# ------------------------------------------------------------------------------
# Cross-platform tools
# ------------------------------------------------------------------------------

print_section "Cross-platform tools"

check_tool "Ghostty"     "ghostty"      "ghostty"      "macOS/Linux"
check_tool "zmx"         "zmx"          "zmx"          "macOS/Linux"
check_tool "fzf"         "fzf"          "fzf"          "macOS/Linux"
check_tool "ripgrep"     "rg"           "ripgrep"      "macOS/Linux"
check_tool "eza"         "eza"          "eza"          "macOS/Linux"

# Debian-family alternatives
check_tool "bat"         "bat batcat"   "bat"          "macOS/Linux"
check_tool "fd"          "fd fdfind"    "fd"           "macOS/Linux"

check_tool "zoxide"      "zoxide"       "zoxide"       "macOS/Linux"

check_tool "jq"          "jq"           "jq"           "macOS/Linux"
check_tool "yq"          "yq"           "yq"           "macOS/Linux"
check_tool "tldr"        "tldr"         "tldr"         "macOS/Linux"

check_tool "Helix"       "hx"           "helix"        "macOS/Linux"
check_tool "Yazi"        "yazi"         "yazi"         "macOS/Linux"

check_tool "Git"         "git"          "git"          "macOS/Linux"
check_tool "GitHub CLI"  "gh"           "gh"           "macOS/Linux"
check_tool "tuicr"       "tuicr"        "tuicr"        "macOS/Linux"
check_tool "GPG"         "gpg"          "gnupg"        "macOS/Linux"

check_tool "direnv"      "direnv"       "direnv"       "macOS/Linux"

check_tool "Claude"      "claude"       "claude"       "macOS/Linux"
check_tool "Codex"       "codex"        "codex"        "macOS/Linux"

check_tool "Herdr"       "herdr"        "herdr"        "macOS/Linux"

check_tool "Podman"      "podman"       "podman"       "macOS/Linux"
check_tool "podman-tui"  "podman-tui"   "podman-tui"   "macOS/Linux"

check_tool "Glow"        "glow"         "glow"         "macOS/Linux"
check_tool "procs"       "procs"        "procs"        "macOS/Linux"
check_tool "dua"         "dua"          "dua-cli"      "macOS/Linux"

check_tool "btop"        "btop"         "btop"         "macOS/Linux"
check_tool "Fastfetch"   "fastfetch"    "fastfetch"    "macOS/Linux"

check_tool "LocalSend"   "localsend"    "localsend"    "macOS/Linux"

end_section

# ------------------------------------------------------------------------------
# macOS-specific tools
# ------------------------------------------------------------------------------

if [[ "$OS" == "Darwin" ]]; then

  print_section "macOS-specific tools"

  check_tool "pbcopy"  "pbcopy"   "macOS built-in" "macOS only"
  check_tool "pbpaste" "pbpaste"  "macOS built-in" "macOS only"

  end_section

  print
  print "Linux-only tools skipped on macOS:"
  print

  printf "  %s-%s %-12s %s\n" \
    "$COLOR_SKIPPED" "$RESET" \
    "wl-clipboard" \
    "Linux/Wayland clipboard bridge"

  printf "  %s-%s %-12s %s\n" \
    "$COLOR_SKIPPED" "$RESET" \
    "clipse" \
    "Linux clipboard history TUI"

  printf "  %s-%s %-12s %s\n" \
    "$COLOR_SKIPPED" "$RESET" \
    "impala" \
    "Linux Wi-Fi TUI / iwd"

  printf "  %s-%s %-12s %s\n" \
    "$COLOR_SKIPPED" "$RESET" \
    "wiremix" \
    "Linux PipeWire audio TUI"

  printf "  %s-%s %-12s %s\n" \
    "$COLOR_SKIPPED" "$RESET" \
    "walker" \
    "Linux app launcher"

  printf "  %s-%s %-12s %s\n" \
    "$COLOR_SKIPPED" "$RESET" \
    "bluetui" \
    "Linux Bluetooth / BlueZ TUI"

# ------------------------------------------------------------------------------
# Linux-specific tools
# ------------------------------------------------------------------------------

elif [[ "$OS" == "Linux" ]]; then

  print_section "Linux-specific tools"

  check_tool "wl-copy"  "wl-copy"   "wl-clipboard" "Linux/Wayland"
  check_tool "wl-paste" "wl-paste"  "wl-clipboard" "Linux/Wayland"

  check_tool "clipse"   "clipse"    "clipse"       "Linux"

  check_tool "impala"   "impala"    "impala"       "Linux/iwd"
  check_tool "wiremix"  "wiremix"   "wiremix"      "Linux/PipeWire"

  check_tool "walker"   "walker"    "walker"       "Linux/Wayland"

  check_tool "bluetui"  "bluetui"   "bluetui"      "Linux/BlueZ"

  end_section

  print
  print "macOS-only tools skipped on Linux:"
  print

  printf "  %s-%s%s pbcopy\n" \
    "$COLOR_SKIPPED" \
    "$RESET"

  printf "  %s-%s%s pbpaste\n" \
    "$COLOR_SKIPPED" \
    "$RESET"

else

  print
  print "Unsupported OS: $OS"

fi

print
print "Done."