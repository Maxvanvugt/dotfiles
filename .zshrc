# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"
source ~/.secrets

plugins=(git zsh-autocomplete fzf zsh-autosuggestions)

export PATH=/home/max/.local/bin:/snap/bin:$PATH

eval "$(oh-my-posh init zsh --config ~/posh-theme.omp.json)"
source $ZSH/oh-my-zsh.sh

# export EDITOR=lvim
# export VISUAL=lvim

[[ -s "/home/max/.sdkman/bin/sdkman-init.sh" ]] && source "/home/max/.sdkman/bin/sdkman-init.sh"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

setopt EXTENDED_HISTORY
