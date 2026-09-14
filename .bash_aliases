# system
alias netstat="netstat -anltp"
alias update="sudo apt update && sudo apt upgrade && sudo apt autoremove"

# benchmarking
alias hw="curl -sL yabs.sh | bash -s -- -ig"
alias net="curl -sL yabs.sh | bash -s -- -fg"

# solana-tools
tool=$HOME/solana-tools/solana.sh
bin=`${tool} export bin`
log=`${tool} export log`
CFGFILE=`${tool} export CFGFILE`
LOGFILE=`${tool} export LOGFILE`
[[ ":$PATH:" == *":${bin}:"* ]] || export PATH="${bin}:$PATH"
[[ ":$LD_LIBRARY_PATH:" == *":${bin}:"* ]] || export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}${bin}"
alias airdrop="${tool} airdrop"
alias balance="solana balance"
alias bind="${tool} bind"
alias catchup="solana catchup --our-localhost --follow --log"
alias chrony="sudo systemctl status chrony"
alias config="nano $CFGFILE"
alias dz="${tool} dz"
alias fwstat="sudo iptables -vn -L ufw-before-input"
alias gossip="solana gossip -ul | grep '$(solana address)'"
alias leader="${tool} leader-slot"
alias optimistic="${tool} optimistic-slot"
alias log="tail -fn 100 ${log}"
alias logr="sudo journalctl -f -u relayer.service"
alias logs="tail -fn 100 $LOGFILE"
alias logv="log | grep '[0-9.]*% of active stake visible[[:alpha:][:space:]]*'"
alias logw="log | grep -A 12 'Waiting for [0-9.]*% of activated stake[[:alnum:][:space:].]*'"
alias monitor="${tool} monitor"
alias rakurai="${tool} rakurai-status"
alias relayer="${tool} relayer status"
alias restart="${tool} restart"
alias rewards="solana inflation rewards ${tool%/*}/keys/vote-account*.json"
alias setup="${tool} setup"
alias slots="${tool} slots"
alias status="${tool} validator status"
alias trim="${tool} trim"
alias txtower="${tool} txtower"
alias rxtower="${tool} rxtower"
alias vote-on="${tool} vote-on"
alias vote-off="${tool} vote-off"
alias usage="${tool} usage"
alias validators="solana validators -n -r --sort=credits -ul"
alias val="validators | sed -n 1,21p && validators | grep '$(solana address)'"
alias wd="${tool} watchdog"
