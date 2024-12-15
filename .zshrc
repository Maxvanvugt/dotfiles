# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

plugins=(git zsh-autocomplete fzf zsh-autosuggestions)

eval "$(oh-my-posh init zsh --config ./posh-theme.omp.json)"
source $ZSH/oh-my-zsh.sh