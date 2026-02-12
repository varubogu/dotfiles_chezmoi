#!/bin/bash

help() {
    cat << EOF
Usage: setup.bash [options]

Options:
    --noroot         Do not use sudo for root-required installations.
    --chezmoi-only   Configure only chezmoi installation and dotfiles cloning (no package installs).
    -h --help         Show this help message.

EOF
}

# Exit script on error
set -e

# .local/lib/functions.bash start

echo_log() {
    echo "***dotfiles[$1] $2"
}

echo_log_info() {
    echo_log "INFO" "$1"
}

echo_log_error() {
    echo_log "ERROR" "$1"
}

echo_log_warn() {
    echo_log "WARN" "$1"
}

is_command_available() { command -v "$1" &> /dev/null; }


is_linux() { [ "$(uname)" = "Linux" ]; }

is_mac() { [ "$(uname)" = "Darwin" ];}

is_wsl() {
    [ -n "${WSL_DISTRO_NAME}" ] || \
    [ -n "${WSLG_DIR}" ] || \
    (grep -qEi "(Microsoft|WSL)" /proc/version 2>/dev/null && \
    [ -r "/mnt/c/Users" ])
}

is_windows() {
    case "$(uname -r)" in
        *Microsoft*)
            return 0
            ;;
        *CYGWIN*|*MINGW*|*MSYS*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}


echo_env() {
    echo_log_info "TERM: $TERM Shell: $SHELL"
    echo_log_info "OS: $(uname)"
    echo_log_info "LANG: $LANG"
    echo_log_info "Home: $HOME PWD: $PWD"
    echo_log_info "User: $USER"
    echo_log_info "Editor: $EDITOR"
}

# .local/lib/functions.bash end





# コマンドオプション処理
is_root=true
is_chezmoi_only=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --noroot)
            is_root=false
            shift
            ;;
        --chezmoi-only)
            is_chezmoi_only=true
            shift
            ;;
        -h|--help)
            help
            exit 0
            ;;
        *)
            echo_log_error "Unknown option: $1"
            help
            exit 1
            ;;
    esac
done

# 環境変数 DOTFILES_REPO_URL で上書き可能（private repo 等は secrets で対応）
REPO_URL="${DOTFILES_REPO_URL:-https://github.com/varubogu/dotfiles.git}"
BIN_DIR=$HOME/.local/bin/dotfiles




setup_brew() {
    echo_log_info "Checking brew..."
    if is_command_available brew; then
        echo_log_info "brew already installed"
    else
        echo_log_info "brew is not installed."
        if is_mac; then
            echo_log_info "mac brew installation..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            echo_log_info "brew installed successfully"
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> $HOME/.zshrc
            eval "$(/opt/homebrew/bin/brew shellenv)"
            echo_log_info "mac brew setting done"
        elif is_linux; then
            echo_log_info "linux brew skip"
        else
            echo_log_error "brew installation failed. Please install it manually."
            exit 1
        fi
    fi
}

setup_chezmoi() {
    echo_log_info "Checking chezmoi..."
    if is_command_available chezmoi; then
        echo_log_info "chezmoi already installed"
    else
        echo_log_info "chezmoi is not installed. Installing..."
        if is_command_available brew; then
            brew install chezmoi
        elif is_command_available apt-get; then
            sudo apt-get update && sudo apt-get install -y chezmoi
        else
            echo_log_error "Unable to install chezmoi. Please install it manually."
            exit 1
        fi
    fi

    echo_log_info "Cloning dotfiles..."
    if [ -d "$HOME/.local/share/chezmoi/.git" ]; then
        echo_log_info "chezmoi source already initialized"
        chezmoi git pull
    else
        echo_log_info "Initializing chezmoi from $REPO_URL"
        chezmoi init --apply=false "$REPO_URL"
    fi
}

main() {
    cd $HOME || exit

    if is_mac; then
        # Macの場合、パッケージ管理ソフトが無いのでbrewをインストール
        setup_brew
    fi

    setup_chezmoi

    if [ "$is_chezmoi_only" = true ]; then
        echo_log_info "chezmoi-only setup completed."
        exit 0
    fi

    # XDG Base Directory Specificationを設定
    echo_log_info "XDG Base Directory Specification"
    . $HOME/.config/xdg_base_dir/set_env.bash

    #　環境に合わせてパッケージをインストール
    if is_mac; then
        echo_log_info "mac install"
        . $BIN_DIR/install/install_mac.zsh
        echo_log_info "Installed mac dotfiles successfully!"
    else
        if is_command_available apt-get; then
            echo_log_info "apt-get install"
            . $BIN_DIR/install/install_apt-get.bash $is_root
            echo_log_info "Installed apt dotfiles successfully!"
        fi
    fi

    # シンボリックリンクを貼る
    echo_log_info "symlink execution"
    . $BIN_DIR/symlink/symlink.bash

    # if [[ "$SHELL" == *"/zsh"* ]]; then
    #     echo "zshrc execution"
    #     . $HOME/.zshrc
    # elif [[ "$SHELL" == *"/bash"* ]]; then
    #     echo "bashrc execution"
    #     . $HOME/.bashrc
    # fi

    if [ -f $HOME/.local/bin/dotfiles/setup/setup.os.bash ]; then
        echo_log_info "os specific setup"
        . $HOME/.local/bin/dotfiles/setup/setup.os.bash
        echo_log_info "os specific setup done"
    fi

    # zinit install
    bash -c "$(curl --fail --show-error --silent --location https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"



    echo_log_info "Installed dotfiles successfully!"

    if [[ "$SHELL" == *"/zsh"* ]]; then
        echo_log_info "next step: zshrc reload"
        echo 'source $HOME/.zshrc'
    elif [[ "$SHELL" == *"/bash"* ]]; then
        echo_log_info "next step: zsh execution (requires sudo)"
        echo_log_info 'chsh -s "$(which zsh)"'
        echo_log_info "or"
        echo_log_info "next step: bashrc reload"
        echo_log_info 'source $HOME/.bashrc'
    fi
}

main
