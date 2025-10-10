#!/bin/bash -e
# Copyright (c) 2025 1Dad <dad@1dad.io>
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# shellcheck disable=SC2006,SC2155

# package-info
pkg_name=solana-tools
pkg_version=0.1.0

# script reporting
is_num(){ [[ "$1" =~ ^[0-9]+$ ]]; }
in_array(){
	local v=${1-}; shift
	local arr=($@)
	[[ " ${arr[*]} " =~ " ${v} " ]]
}
array_search(){
	local v=${1-}; shift
	local arr=($@)
	for k in "${!arr[@]}"; do if [ "${arr[$k]}" == "${v}" ]; then echo ${k}; break; fi; done
}
implode(){ local d=${1-} f=${2-}; if shift 2; then printf %s "$f" "${@/#/$d}"; fi }
reverse(){ printf '%s\n' "$@" | tac | tr '\n' ' '; echo; }
caller(){
	local bl="log ok error warn info debug"
	local arr=(${FUNCNAME[@]/${FUNCNAME[0]}})
	for v in ${bl}; do arr=(${arr[@]/${v}}); done
	echo $(implode '::' $(reverse "${arr[@]}"))
}
log(){
	[ -z "$1" -o -z "$LOGFILE" ] && return 0
	local level=${2:-info}
	local levels=(null error warn info debug)
	local curr=$(array_search ${level} "${levels[@]}")
	is_num ${log_level} || log_level=$(array_search ${log_level:-info} "${levels[@]}")
	((${curr:-0}<=${log_level:-0})) || return 0
	level=`echo ${level} | tr '[:lower:]' '[:upper:]'`
	date +"[%b %e %H:%M:%S.%3N ${level} $(caller)] $1" | sudo -u $USER tee -a $LOGFILE >/dev/null
}
sms(){
	[ -n "$1" -a -n "${tg_btoken}" -a -n "${tg_chatid}" ] || return 0
	local message="$1"
	local subject="$2"
	[ -n "$SENDER" -a -n "${subject}" ] && subject+='@'
	[ -n "$SENDER" ] && subject+="$SENDER"
	curl -s \
		--data parse_mode=HTML \
		--data chat_id=${tg_chatid} \
		--data text="<b>${subject}</b>%0A${message}" \
		--request POST https://api.telegram.org/bot${tg_btoken}/sendMessage &>/dev/null
	return
}
is_lastmsg(){
	[ "$LOG" == 1 -o "$SMS" == 1 ] || return
	[ -z "${lastmsg}" -o -z "$1" ] && return 1
	[ -s "${lastmsg}" ] && local old=$(<${lastmsg})
	local new=`echo "$1" | md5sum | awk '{print $1}'`
	if [ "${new}" == "${old}" ]; then
		return 0
	else
		echo ${new} | ${sudo} tee ${lastmsg} >/dev/null
		return 1
	fi
}
ok(){
	local fn=${FUNCNAME[1]} str=OK
	[ -n "$LOG" ] && log "${*:-${str}}" # default
	[ -n "$SMS" ] && sms "${*:-${str}}" ${fn}
	echo -e "${LN}${fn}:${NC} ${LG}${*:-${str}}${NC}"
}
error(){
	local fn=${FUNCNAME[1]} str=${FUNCNAME[0]^}
	[ -n "$LOG" ] && log "${*:-${str}}" ${FUNCNAME[0]}
	[ -n "$SMS" ] && sms "${*:-${str}}" ${fn}
	echo -e "${LN}${fn}:${NC} ${LR}${*:-${str}}${NC}"
	exit 1
}
warn(){
	local fn=${FUNCNAME[1]} str=${FUNCNAME[0]^}
	[ -n "$LOG" ] && log "${*:-${str}}" ${FUNCNAME[0]}
	[ -n "$SMS" ] && sms "${*:-${str}}" ${fn}
	echo -e "${LN}${fn}:${NC} ${CR}${*:-${str}}${NC}"
}
info(){
	is_lastmsg "${*}" && return 0 # don't spam
	local fn=${FUNCNAME[1]} str=${FUNCNAME[0]^}
	[ -n "$LOG" ] && log "${*:-${str}}" ${FUNCNAME[0]}
	[ -n "$SMS" ] && sms "${*:-${str}}" ${fn}
	echo -e "${LN}${fn}:${NC} ${*:-${str}}"
}
debug(){
	local fn=${FUNCNAME[1]} str=${FUNCNAME[0]^}
	[ -n "$LOG" ] && log "${*:-${str}}" ${FUNCNAME[0]}
	[ -n "$SMS" ] && sms "${*:-${str}}" ${fn}
	echo -e "${LN}${fn}:${NC} ${*:-${str}}"
}

# versioning stuff
ver_re='[0-9]+(\.[0-9]+)*'; suffix='(\-[a-z]+){0,1}'
is_ver(){ [[ "$1" =~ ^${ver_re}${suffix}$ ]]; }
is_tag(){ local s; [ -z "$2" ] && s=${suffix} || s="(\-${2})"; [[ "$1" =~ ^v${ver_re}${s}$ ]]; }
tag2ver(){ is_tag "$1" && echo "$1" | sed 's/[^0-9.]*//g' || echo "$1"; }
cmp_ver(){
	[ $# -eq 2 ] || error ${err_arg_count}
	is_ver "$1"  || error ${err_version} 1
	is_ver "$2"  || error ${err_version} 2
	printf '%s\n%s\n' "$2" "$1" | sort --check=quiet --version-sort
}

# variables
is_cidr(){
	local A B C D N
	IFS="./" read -r A B C D N <<< "$1"; unset IFS
	local ip=$((${A:-0}*256**3 + ${B:-0}*256**2 + ${C:-0}*256 + ${D:-0}))
	[ "${ip}" -gt 0 -a $((${ip} % 2**(32-${N:-0}))) = 0 ]
}
is_ip(){ [[ "$1" =~ ^(0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))\.){3}0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))$ ]]; }
is_pub(){ local base58='[1-9A-HJ-NP-Za-km-z]'; [[ "$1" =~ ^${base58}{32,44}$ ]]; }
is_main(){ for i in {1..2}; do [ "${FUNCNAME[$i]}" == 'main' ] && return 0; done; return 1; }
is_user(){ [[ "$1" =~ ^[[:lower:]_][[:lower:][:digit:]_-]{2,15}$ ]]; }
is_linux(){ [[ "$OSTYPE" == 'linux-gnu'* ]]; }
is_macos(){ [[ "$OSTYPE" == 'darwin'* ]]; }
is_dryrun(){ [ "${dryrun}" == 1 ]; }
is_staked(){ cmp -s ${keypair} ${staked}; }
user_chown(){ [ -n "$1" ] || error ${err_arg}; USER=$1; sudo chown -R $USER: ${tool%/*}; }
user_exists(){ [[ -n `id -u "$1" 2>/dev/null` ]]; }
[ -n "$SSH_CLIENT" ] && client=`echo $SSH_CLIENT | awk '{print $1}'` || client='systemd'
dirs=(tower ledger accounts accounts_hash accounts_index accounts_shrink snapshots snapshots_inc)
tool=`readlink -f $0`
lang=${tool%/*}/etc/default/${pkg_name}.lang
term=${tool%/*}/etc/tput.sh
source ${lang} &>/dev/null || error "Cannot read the file: ${lang}"
source ${term} &>/dev/null || error "Cannot read the file: ${term}"
oUSER=$USER
if is_linux; then
	USER=`stat -c '%U' $tool`
	user_exists $USER || user_chown $oUSER
	HOME=`getent passwd "$USER" | cut -d: -f6`
elif is_macos; then
	USER=`/usr/bin/stat -f%u $tool | /usr/bin/id -un`
	user_exists $USER || user_chown $oUSER
	HOME=`eval echo ~$(printf '%q' "$USER")` # safe
else
	error ${err_unsupported_os}
fi
sudo="sudo -u $USER"
CFGFILE=${tool%/*}/${pkg_name}.conf
LOGFILE=${tool%/*}/${pkg_name}.log
PIDFILE=${tool%/*}/ACTION.pid
cleanup=${tool%/*}/${pkg_name}.cleanup
lastmsg=${tool%/*}/${pkg_name}.lastmsg
oldunit=${tool%/*}/${pkg_name}.oldunit
trimmed=${tool%/*}/${pkg_name}.trimmed
wd_boot=${tool%/*}/${pkg_name}.wd-boot
wd_data=${tool%/*}/${pkg_name}.wd-data
wd_ping=${tool%/*}/${pkg_name}.wd-ping
wd_start=${tool%/*}/${pkg_name}.restart

# read the config
ceil(){ echo "$1" | sed -e 's/\.0*$//;s/\.[0-9]*$/+1/' | bc; }
read_conf(){
	if [ ! -f "$CFGFILE" ]; then
		cp -a ${tool%/*}/etc/default/${CFGFILE##*/} $CFGFILE || error ${err_file_write//FILE/$CFGFILE}
	fi
	source $CFGFILE &>/dev/null || error ${err_file_read//FILE/$CFGFILE}
	
	# moniker
	moniker=${moniker:-mainnet-beta}
	
	# cpu-tuner [01]
	# TODO: use n/y instead
	cpu_gov=${cpu_gov:-disabled}
	cpu_gov_default=${cpu_gov_default:-schedutil}
	cpu_min_to_max=${cpu_min_to_max:-0}
	cpu_ignore_max=${cpu_ignore_max:-1}
	
	# hot-swap
	ssh_port=${ssh_port:-22}
	ssh_user=${ssh_user:-root}
	ssh_tool=${ssh_tool:-${tool}}
	failures=${failures:-1}
	failures_offset=${failures_offset:-1}
	
	# airdrop & rebalance
	airdrop_min=${airdrop_min:-1}
	airdrop_max=${airdrop_max:-10}
	
	# logging
	log_level=${log_level:-info}
	log_limit=${log_limit:-10000}
	log_period=${log_period:-daily}
	log_rotate=${log_rotate:-7}
	
	# RPC
	rpc_url=${rpc_url:-${moniker}}
	rpc_conn_timeout=${rpc_conn_timeout:-5}
	rpc_max_time=${rpc_max_time:-10}
	rpc_retry=${rpc_retry:-5}
	rpc_retry_delay=${rpc_retry_delay:-1}
	rpc_retry_max_time=${rpc_retry_max_time:-30}
	
	# do-not-edit
	cache_ttl=${cache_ttl:-60}
	free_hugepgs=${free_hugepgs:-0}
	lock_timeout=${lock_timeout:-30}
	max_delinquent=${max_delinquent:-5}
	min_idle_time=${min_idle_time:-10}
	poll_interval=${poll_interval:-1}
	relayerd=${relayerd:-relayer}
	# systemd defaults to the RAM profile
	tower_slot_delay=${tower_slot_delay:-0} # slots
	tower_slot_speed=${tower_slot_speed:-2.5}
	tower_ttl_slots=${tower_ttl_slots:-256}
	trim_ttl=${trim_ttl:-3600} # hours
	trim_idle_time=${trim_idle_time:-5} # mins
	
	# sys-tuner
	max_files=${max_files:-2000000}
	udp_buffer=${udp_buffer:-134217728}
	swappiness=${swappiness:-1}
	cache_pressure=${cache_pressure:-50}
	
	# setup [01]
	# TODO: use n/y instead
	setup_sshd=${setup_sshd:-1}
	setup_ufw=${setup_ufw:-1}
	setup_ufw_quic=${setup_ufw_quic:-1}
	setup_f2b=${setup_f2b:-1}
	setup_sudoers=${setup_sudoers:-1}
	setup_cli=${setup_cli:-1}
	setup_cli_full=${setup_cli_full:-0}
	setup_relayer=${setup_relayer:-1}
	setup_cron=${setup_cron:-1}
	setup_aliases=${setup_aliases:-1}
	setup_finder=${setup_finder:-0}
	setup_user=${setup_user:-ubuntu}
	sudoers=${sudoers:-sudo}
	
	# dependencies
	# `block`,`stakes`,`validators` are named after the RPC methods
	local path=${tool%/*}/${moniker%%[-]*}
	block=${path}/data/blocks/SLOT.json
	stakes=${path}/data/stakes/EPOCH.json
	validators=${path}/data/validators.json
	tower_delay=`echo "scale=1; ${tower_slot_delay}/${tower_slot_speed}" | bc | sed 's/^\./0./'`
	tower_ttl=`echo "scale=1; ${tower_ttl_slots}/${tower_slot_speed}" | bc | sed 's/^\./0./'`
	tower_ttl=$(ceil ${tower_ttl}) # rounded up
	# firedancer
	fd_conf=${path}/config.toml
}; read_conf

save_conf(){
	[ $# -eq 2 ] || error ${err_arg_count}
	sed -i --follow-symlinks "s|^[#]*\($1\s*=\s*\).*\$|\1$2|" $CFGFILE || error ${err_file_write//FILE/$CFGFILE}
}

# get options from the CLI
opt_val(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }
known_id=()
pos_args=()
action=help
while test $# -gt 0; do
	case "$1" in
	# flags [01]
	-1|--oneshot)
		oneshot=1
		shift;;
	-c|--cron)
		client='cron'
		shift;;
	-D|--dryrun)
		dryrun=1
		shift;;
	-f|--force)
		force=1
		shift;;
	--fd)
		fd=1
		shift;;
	-h|--help)
		action=help
		shift;;
	--link)
		link=1
		shift;;
	--move)
		move=1
		shift;;
	-n|--now)
		now=1
		shift;;
	-p|--poll)
		poll=1
		shift;;
	-q|--quiet)
		quiet=1
		shift;;
	--reboot)
		reboot=1
		shift;;
	--unstaked)
		setup_unstaked=1
		shift;;
	# options
	--clean*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		clean=$(opt_val "$1")
		shift;;
	-g*|--governor*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		cpu_gov=$(opt_val "$1")
		shift;;
	-d*|--max-delinquent-stake*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		max_delinquent=$(opt_val "$1")
		shift;;
	-i*|--min-idle-time*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		min_idle_time=$(opt_val "$1")
		shift;;
	-u*|--url*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		rpc_url=$(opt_val "$1")
		# TODO: extract moniker from URL and update config deps if modified
		# moniker=$(get_moniker ${rpc_url})
		shift;;
	-v*|--version*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		version=$(opt_val "$1")
		is_ver ${version} || unset version
		shift;;
	# overrides BEGIN
	--known-validator*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		known_id+=($(opt_val "$1"))
		shift;;
	# flags [01]
	# TODO: make them universal by dash-converter (`-` to `_`)
	--only-known-rpc)
		only_known_rpc=${only_known_rpc:-1}
		[ ${only_known_rpc} == 1 ] || unset only_known_rpc
		shift;;
	--private-rpc)
		private_rpc=${private_rpc:-1}
		[ ${private_rpc} == 1 ] || unset private_rpc
		shift;;
	--no-genesis-fetch)
		no_genesis_fetch=${no_genesis_fetch:-1}
		[ ${no_genesis_fetch} == 1 ] || unset no_genesis_fetch
		shift;;
	--no-snapshot-fetch)
		no_snapshot_fetch=${no_snapshot_fetch:-1}
		[ ${no_snapshot_fetch} == 1 ] || unset no_snapshot_fetch
		shift;;
	--no-snapshots)
		no_snapshots=${no_snapshots:-1}
		[ ${no_snapshots} == 1 ] || unset no_snapshots
		shift;;
	--no-incremental-snapshots)
		no_incremental_snapshots=${no_incremental_snapshots:-1}
		[ ${no_incremental_snapshots} == 1 ] || unset no_incremental_snapshots
		shift;;
	# options
	# TODO: make them universal by dash-converter (`-` to `_`)
	--accounts-db-hash-threads*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		accounts_db_hash_threads=${accounts_db_hash_threads:-$(opt_val "$1")}
		shift;;
	--snapshot-interval-slots*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		snapshot_interval_slots=${snapshot_interval_slots:-$(opt_val "$1")}
		shift;;
	--full-snapshot-interval-slots*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		full_snapshot_interval_slots=${full_snapshot_interval_slots:-$(opt_val "$1")}
		shift;;
	# jito stuff
	--commission-bps*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		commission_bps=${commission_bps:-$(opt_val "$1")}
		shift;;
	--block-engine-url*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		block_engine_url=${block_engine_url:-$(opt_val "$1")}
		shift;;
	--relayer-url*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		relayer_url=${relayer_url:-$(opt_val "$1")}
		shift;;
	--shred-receiver-address*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		shred_receiver_address=${shred_receiver_address:-$(opt_val "$1")}
		shift;;
	--trust-relayer-packets)
		trust_relayer_packets=${trust_relayer_packets:-1}
		[ ${trust_relayer_packets} == 1 ] || unset trust_relayer_packets
		shift;;
	# overrides END
	--) # the end of the options
		shift
		pos_args+=("$@")
		break;;
	-*) # extra args allowed
		if [ "${action}" != 'relayer' -a "${action}" != 'validator' -a "${action}" != 'make_snapshot' ]; then
			error ${err_opt_unknown//OPT/$1} ${tip_help}
			break
		else
			pos_args+=("$1")
			shift
		fi;;
	# actions
	export|monitor|on-boot|unswap|usage|\
	airdrop|balance|bind|leader-slot|optimistic-slot|slots|stakes|\
	check-snapshot|make-snapshot|\
	wait-for-restart|trim|start|stop|restart|update|\
	jito-reload|relayer|restart-relayer|update-relayer|\
	setup|\
	txtower|rxtower|vote-off|vote-on|watchdog|\
	cpu-tuner|sys-tuner|validator)
		[ "$1" == 'export' ] && action=${1}_ || action=${1//-/_}
		[ "$1" == 'wait-for-restart' ] && action=wait4r
		if [[ "txtower" == *${1}* ]]; then
			# we need the watchdog to be idle here
			PIDFILE=${tool%/*}/watchdog.pid
			PIDWAIT=${lock_timeout}
		fi
		shift;;
	*)
		pos_args+=("$1")
		shift;;
	esac
done
# firedancer
[ "${fd}" == 1 ]   && action="fd_${action}"
[ "${poll}" == 1 ] && action=poll
# restore the positional arguments
set -- "${pos_args[@]}"
unset pos_args opt
# end of options from the CLI

# get options from the systemd unit file(s)
get_env(){ cat $FILE | sed -n "s/.*$1=\(\)/\1/p" | awk '{print $1}' | tr -d '"'; }
get_opt(){ local v=`cat $FILE | sed -n "s/--$1\(=\|[[:space:]]\)\+//p"`; echo ${v} | awk -v fb="$2" '{print ($1==""?fb:$1)}'; }
get_systemd(){
	local files=(${tool%/*}/${moniker%%[-]*}/solana*.service)
	echo `basename ${files[0]} .service` # pick up the first
}
read_systemd(){
	FILE=/etc/systemd/system/${systemd}.service
	[ -s "$FILE" ] || FILE=${tool%/*}/${moniker%%[-]*}/${systemd}.service
	[ -s "$FILE" ] || FILE=${tool%/*}/${moniker%%[-]*}/$(get_systemd).service
	[ -s "$FILE" ] || error ${err_file_read//FILE/$FILE}
	TAG=$(get_env 'TAG')
	
	# firedancer
	TAG_FD=$(get_env 'TAG_FD')
	
	keypair=$(get_opt 'identity')
	vote_acc=$(get_opt 'vote-account')
	
	# make up variables used for identity transition
	[ "${setup_unstaked}" == 1 ] && staked=${unstaked}
	auth_voter=$(get_opt 'authorized-voter')
	[ "${staked}" == 'authorized-voter' ] && staked=${auth_voter}
	[ -z "${staked}" ] && staked=validator-keypair-${moniker%%[-]*}.json
	
	# make keypairs an absolute path
	[ "${staked}" == "${staked##*/}" ] && staked=${keypair%/*}/${staked}
	[ "${unstaked}" == "${unstaked##*/}" ] && unstaked=${keypair%/*}/${unstaked}
	if ! is_pub ${vote_acc}; then
		[ "${vote_acc}" == "${vote_acc##*/}" ] && vote_acc=${keypair%/*}/${vote_acc}
	fi
	
	ledger=$(get_opt 'ledger')
	tower=$(get_opt 'tower' ${ledger})
	accounts=$(get_opt 'accounts' "${ledger}/accounts")
	accounts_hash=$(get_opt 'accounts-hash-cache-path' "${ledger}/accounts_hash_cache")
	accounts_index=$(get_opt 'accounts-index-path' "${ledger}/accounts_index")
	accounts_shrink=$(get_opt 'account-shrink-path')
	snapshots=$(get_opt 'snapshots' ${ledger})
	snapshots_inc=$(get_opt 'incremental-snapshot-archive-path' ${snapshots})
	snapshots_age=$(get_opt 'maximum-local-snapshot-age' 2500)
	log=$(get_opt 'log')
	rocksdb_shred=$(get_opt 'rocksdb-shred-compaction' 'level')
	rpc_port=$(get_opt 'rpc-port' 8899)
	unset FILE
}; read_systemd

# jito-relayer
read_relayerd(){
	FILE=/etc/systemd/system/${relayerd}.service
	[ -s "$FILE" ] || FILE=${tool%/*}/${moniker%%[-]*}/${relayerd}.service
	if [ -s "$FILE" ]; then
		RELAYER_TAG=$(get_env 'TAG')
		relayer_keypair=$(get_opt 'keypair-path')
		signing_key_pem=$(get_opt 'signing-key-pem-path')
		verifying_key_pem=$(get_opt 'verifying-key-pem-path')
	elif [ "${FUNCNAME[1]}" == 'setup' ]; then
		unset RELAYER_TAG # could be set by an old moniker
		[ -z "${quiet}" ] && warn ${err_file_read//FILE/$FILE.} ${err_relayer_disable}
	fi
	unset FILE
}; read_relayerd

# crates
set_bin(){
	local release version=$(tag2ver "$TAG")
	if is_tag $TAG jito; then # jito-solana
		if cmp_ver "${version}" "${url_jito_since:-9999}"; then
			release=releases/${version}/solana-release
		else
			release=releases/$TAG
		fi
	elif is_tag $TAG; then # agave
		if cmp_ver "${version}" "${url_anza_since:-9999}"; then
			release=releases/${version}/solana-release
		else
			release=releases/$TAG
		fi
	fi
	
	local d=$HOME/.local/share/solana
	bin=${d}/install/${release:-active_release}/bin
	solana=${bin}/solana
	keygen=${bin}/solana-keygen
	installer=${bin}/agave-install
	validator=${bin}/agave-validator
	ledger_tool=${bin}/agave-ledger-tool
	# watchtower=${bin}/agave-watchtower
	
	# firedancer
	fdctl=${d}/fd/${TAG_FD:-active_release}/bin/fdctl
	
	# jito-relayer
	is_tag $RELAYER_TAG && relayer=${d}/relayer/$RELAYER_TAG/jito-transaction-relayer
}; set_bin

# commands
set_cmd(){
	is_macos && cmd_ctime="/usr/bin/stat -f %B" || cmd_ctime="stat -c %W"
	is_macos && cmd_mtime="/usr/bin/stat -f %m" || cmd_mtime="stat -c %Y"
	is_dryrun && cmd_exec='echo' || cmd_exec='sudo'
	
	# check for coreutils version
	local v=`cp --version | head -n1 | sed 's/[^0-9.]*//g'`
	x=$(cmp_ver "${v}" 9.3) && no_clobber='--update=none' || no_clobber='-n'
	
	# check for a leftover
	[ -s "${oldunit}" ] && local old_unit=$(<${oldunit})
	
	local unit=${systemd:-$(get_systemd)}
	cmd_cpufreq="${cmd_exec} cpupower -c CORE frequency-set -r -g GOV"
	cmd_keygen="${keygen} new --no-bip39-passphrase -s"
	cmd_reload="${cmd_exec} systemctl daemon-reload"
	cmd_ssh="${sudo} ssh -o LogLevel=ERROR -o StrictHostKeychecking=no -o UserKnownHostsFile=/dev/null"
	cmd_scp=${cmd_ssh//ssh/scp}
	cmd_status="${cmd_exec} systemctl status ${old_unit:-${unit}}"
	cmd_start="${cmd_exec} systemctl start ${unit}"
	cmd_stop="${cmd_exec} systemctl stop ${old_unit:-${unit}}"
	cmd_trim="${cmd_exec} /usr/sbin/fstrim -av"
	cmd_wait="${cmd_exec} ${validator} -l ${ledger} wait-for-restart-window"
	# jito-relayer
	cmd_relayer_status="${cmd_exec} systemctl status ${relayerd}"
	cmd_relayer_restart="${cmd_exec} systemctl restart ${relayerd}"
	# firedancer
	# fixed a bug: OPTIONS must now be specified after SUBCOMMAND
	cmd_fd="${cmd_exec} ${fdctl} CMD --config ${fd_conf}"
}; set_cmd

# functions
export_(){ [ -z "$1" ] && error ${err_arg}; local var=$1; echo ${!var}; }
get_gov(){ [ "${cpu_gov}" != 'disabled' ] && echo ${cpu_gov} || echo ${cpu_gov_default}; }
mkalias(){ [ -z "$1" ] && error ${err_arg}; local var="x$1" len=${2:-6}; [ -n "${!var}" ] && echo ${!var} || echo ${var:1:${len}}; }
monitor(){ ${cmd_exec} ${validator} -l ${ledger} monitor; }
on_boot(){ date >${wd_boot} 2>/dev/null; log "$(rm -fv ${oldunit})"; log "$(rm -fv ${tool%/*}/*.pid)"; }
starter(){ if [ -z "${reboot}" ]; then ${cmd_reload} && ${cmd_start} && date >${wd_start} 2>/dev/null; else echo 'no-start'; fi; }
stopper(){ ${cmd_stop}; if [ -s "${oldunit}" ]; then rm -f ${oldunit} && setup_log ${log}; else echo 'no-leftover'; fi; }
truncate(){ [ -f "$1" ] || return 0; sed -e :a -e "\$q;N;$((${2:-10}+1)),\$D;ba" -i --follow-symlinks $1 2>/dev/null; }

unswap(){
	is_linux || error ${err_unsupported_os}
	
	local res=`free`
	local mem=`echo "${res}"   | grep -i 'Mem:'`
	local swap=`echo "${res}"  | grep -i 'Swap:'`
	local used=`echo "${swap}" | awk '{printf "%lu", $3}'`
	local free=`echo "${mem}"  | awk '{printf "%lu", $4}'`
	local cache=`echo "${mem}" | awk '{printf "%lu", $6}'`
	local avail=`echo "${mem}" | awk '{printf "%lu", $7}'`
	local total=$((${free}+${cache}+${avail}))
	
	echo -e "Free mem:\t$((${total}/1024/1024)) GB"
	echo -e "Used swap:\t$((${used}/1024/1024)) GB"
	
	if [ "${used}" -eq 0 ]; then
		warn "No swap is in use"
	elif [ "${used}" -lt "${total}" ]; then
		local str="Freeing swap (this could take a while)"
		is_dryrun && str+=" ${tip_dryrun}"
		info ${str}
		if ! is_dryrun; then
			sudo swapoff -a
			sudo swapon -a
		fi
		ok
	else
		error "Not enough memory"
	fi
}

usage(){
	local arr=("${log%/*}") d
	for d in "${dirs[@]}"; do arr+=("${!d}"); done
	arr=(`printf '%s\n' "${arr[@]}" | sort`)
	du -hs $(implode ' ' "${arr[@]}") 2>/dev/null
}

title(){
	local str=${1//PKG/${pkg_name}}
	echo ${str//VERSION/${pkg_version}}
}; TITLE=$(title "${msg_setup}")

backtitle(){
	local arr=("${pkg_name} ${pkg_version}")
	[ -f "${solana}"  ] && arr+=("$(${solana} --version 2>/dev/null | cut -d '(' -f 1 | awk '{$1=$1};1')")
	[ -f "${relayer}" ] && arr+=("$(${relayer} --version 2>/dev/null | sed 's/transaction-//g')")
	# firedancer
	[ -f "${fdctl}"   ] && arr+=("fdctl $(${fdctl} version 2>/dev/null | cut -d '(' -f 1 | awk '{$1=$1};1')")
	echo $(implode ', ' "${arr[@]}")
}; BACKTITLE=$(backtitle)

help(){
	echo -e "$BACKTITLE"
	echo
	echo -e "USAGE:"
	echo -e "    $0 <COMMAND> [FLAGS] [OPTIONS] [ARGS]"
	echo
	echo -e "FLAGS:"
	echo -e "    ${CG}-1${NC}, ${CG}--oneshot${NC}                  Make leader/optimistic-slot run only once"
	echo -e "    ${CG}-c${NC}, ${CG}--cron${NC}                     Indicate a non-interactive shell (run by cron)"
	echo -e "    ${CG}-D${NC}, ${CG}--dryrun${NC}                   Echo commands instead of running them"
	echo -e "    ${CG}-f${NC}, ${CG}--force${NC}                    Bypass any errors and confirmation prompts"
	echo -e "        ${CG}--fd${NC}                       Make up <COMMAND> for Firedancer"
	echo -e "    ${CG}-h${NC}, ${CG}--help${NC}                     Print this help and exit"
	echo -e "    ${CG}-n${NC}, ${CG}--now${NC}                      Don't wait for the restart window"
	echo -e "    ${CG}-p${NC}, ${CG}--poll${NC}                     Poll the RPC server for <COMMAND> to succeed"
	echo -e "    ${CG}-q${NC}, ${CG}--quiet${NC}                    Suppress informational output"
	echo -e "        ${CG}--reboot${NC}                   Reboot server within the restart window"
	echo -e "        ${CG}--unstaked${NC}                 Setup a non-voting validator (used in <setup>)"
	echo
	echo -e "OPTIONS:"
	echo -e "        ${CG}--clean${NC} [dir1,dirN|all]    Clean validator data within the restart window [example: --clean=ledger,accounts]"
	echo -e "    ${CG}-g${NC}, ${CG}--governor${NC} <GOVERNOR>      CPUFreq governor to override the one set in the config [default: ${cpu_gov}]"
	echo -e "    ${CG}-d${NC}, ${CG}--max-delinquent-stake${NC} <%> The maximum delinquent stake % permitted for a restart [default: ${max_delinquent}]"
	echo -e "    ${CG}-i${NC}, ${CG}--min-idle-time${NC} <MINUTES>  Minimum time that the validator should not be leader before restarting [default: ${min_idle_time}]"
	echo -e "        ${CG}--move${NC} <SOURCE> <DEST>     Move files within the restart window [example: --move /path/to/source /destination]"
	echo -e "        ${CG}--link${NC} <TARGET> <NAME>     Link files within the restart window [example: --link /path/to/target /link_name]"
	echo -e "    ${CG}-u${NC}, ${CG}--url${NC} <URL_OR_MONIKER>     URL for Solana's JSON RPC or moniker to override the config [default: ${moniker}]"
	echo -e "    ${CG}-v${NC}, ${CG}--version${NC} <VERSION>        Version to install [default: version tagged in the systemd unit file]"
	echo
	echo -e "COMMANDS:"
	echo -e "        ${CG}airdrop${NC} [ADDRESS] [-p]     Request airdrop of 1 SOL [default: identity]"
	echo -e "        ${CG}balance${NC} [ADDRESS]          Rebalance accounts with the step amount [default: balance_to]"
	echo -e "        ${CG}bind${NC} [HOST] [PUBKEY]       Pair the remote validator for identity transition"
	echo -e "        ${CG}check-snapshot${NC} [NUM_SLOTS] Check if snapshot is less than this many slots behind [default: ${snapshots_age}]"
	echo -e "        ${CG}cpu-tuner${NC} [GOVERNOR]       Tune CPU settings for the given governor [default: $(get_gov)]"
	echo -e "        ${CG}export${NC} <bin|log|tower>     Export environment variables"
	echo -e "        ${CG}jito-reload${NC}                Hot reload the Jito configuration"
	echo -e "        ${CG}leader-slot${NC} [-1]           Show countdown to the next leader slot"
	echo -e "        ${CG}make-snapshot${NC} <SLOT>       Create a new ledger snapshot for the given slot"
	echo -e "        ${CG}monitor${NC} [--fd]             Monitor the validator"
	echo -e "        ${CG}on-boot${NC}                    Set a reboot flag for the watchdog (run by cron)"
	echo -e "        ${CG}optimistic-slot${NC} [-1]       Show optimistic slot"
	echo -e "        ${CG}relayer${NC} [status]           Run relayer (only used by systemd)"
	echo -e "        ${CG}restart${NC} [restart flags]    Restart validator safely within the restart window"
	echo -e "        ${CG}restart-relayer${NC} [--now]    Restart relayer safely within the restart window"
	echo -e "        ${CG}rxtower${NC}                    Transition identity from the voting validator"
	echo -e "        ${CG}setup${NC} [--unstaked]         Setup a validator by installing prerequisites"
	echo -e "        ${CG}slots${NC} [EPOCH] [-q]         Show leader schedule (use -q for a quick view)"
	echo -e "        ${CG}stakes${NC}                     Fetch the validator stakes by the vote account"
	echo -e "        ${CG}start${NC} [EPOCH]              Start the validator at epoch boundary, or now"
	echo -e "        ${CG}stop${NC}  [EPOCH]              Stop the validator at epoch boundary, or now"
	echo -e "        ${CG}sys-tuner${NC}                  Tune system settings"
	echo -e "        ${CG}trim${NC} [-f]                  Trim all mounted FS safely within the restart window"
	echo -e "        ${CG}txtower${NC} [REMOTE_HOST]      Transition identity to a non-voting validator [default: ssh_host]"
	echo -e "        ${CG}unswap${NC}                     Free swap by swapping back into RAM"
	echo -e "        ${CG}update${NC} [--fd]              Update validator safely within the restart window"
	echo -e "        ${CG}update-relayer${NC}             Update relayer safely within the restart window"
	echo -e "        ${CG}usage${NC}                      Summarize disk usage of validator data"
	echo -e "        ${CG}validator${NC} [status]         Run the validator (only used by systemd)"
	echo -e "        ${CG}vote-off${NC}                   Stop voting by setting unstaked identity"
	echo -e "        ${CG}vote-on${NC} [EPOCH]            Start voting at epoch boundary, or now"
	echo -e "        ${CG}wait-for-restart${NC}           Monitor the validator for a good time to restart"
	echo -e "        ${CG}watchdog${NC} [off|on|status]   Run the failover watchdog (run by cron)"
	echo
	echo -e "The default command is -h"
	return 0
}

elapsed(){
	[ -n "$1" ] || error ${err_arg}
	local T=$1
	local D=$(($T/60/60/24))
	local H=$(($T/60/60%24))
	local M=$(($T/60%60))
	local S=$(($T%60))
	(( $D > 0 )) && printf '%dd ' $D
	(( $H > 0 )) && printf '%dh ' $H
	(( $M > 0 )) && printf '%dm ' $M
	# (( $D > 0 || $H > 0 || $M > 0 )) && printf 'and '
	printf '%ds\n' $S
}

tx(){
	local recipient=$1
	local from_addr=$2
	local amount=${3:-0}
	
	is_dryrun || local u=localhost
	local opt="-u ${u:-${rpc_url}}" resp
	
	# verify `recipient`
	[ -n "${recipient}" ] || error ${err_arg} recipient
	if ! is_pub ${recipient}; then
		[ -s "${recipient}" ] || error ${err_file_read//FILE/${recipient}}
	fi
	
	# verify `from_addr`
	if [ -n "${from_addr}" ]; then
		# make a transfer
		[ -s "${from_addr}" ] || error ${err_file_read//FILE/${from_addr}}
		opt="${opt} -k ${from_addr}" # add a fee payer
		resp=`${solana} ${opt} transfer --allow-unfunded-recipient --from ${from_addr} ${recipient} ${amount} 2>&1` \
			|| error `echo "${resp}" | grep -iw Error`
	else
		# request an airdrop
		opt="-u ${moniker}" # need a free RPC server
		resp=`${solana} ${opt} airdrop 1 ${recipient} 2>&1` || error `echo "${resp}" | grep -iw Error`
	fi
	
	# parse the tx ID and confirmation status
	local txid=`echo "${resp}" | grep -iw Signature | awk '{print $2}'`
	local conf=`echo "${resp}" | grep -iw confirm | awk '{print $5}' | tr -cd '[:alnum:]'`
	
	# confirm the tx if requested by the CLI
	[ -n "${conf}" -a "${conf}" == "${txid}" ] && resp=`${solana} ${opt} confirm -v ${txid} 2>/dev/null` || resp=
	[ -n "${resp}" ] && { conf=`echo "${resp}" | grep -m1 -ow confirmed` || conf='processed'; }
	[ -n "${txid}" ] && info ${txid}$([ -n "${conf}" ] && echo " -> ${conf}")
	
	# return 0 if successful, 1 otherwise
	[ -n "${resp}" -a -n "${conf}" ] || [ -z "${resp}" -a -n "${txid}" ]
}

precheck(){
	[ -z "${precheck}" ] && precheck=1 || return 0
	
	# verify the cluster
	[ "${moniker}" != 'testnet' -a "${moniker}" != 'devnet' ] && error ${err_unsupported_cluster}
	
	# verify `airdrop_to`
	[ -n "${airdrop_to}" ] || error ${err_airdrop_to}
	if ! is_pub ${airdrop_to}; then
		[ "${airdrop_to}" == "${airdrop_to##*/}" ] && airdrop_to=${keypair%/*}/${airdrop_to}
		[ -s "${airdrop_to}" ] || error ${err_file_read//FILE/${airdrop_to}}
	fi
	
	# verify `airdrop_from`
	is_pub ${airdrop_from} || error ${err_airdrop_from}
	
	# verify `airdrop_allow`
	if [ -n "${airdrop_allow}" ]; then
		local str; is_staked && str=staked || str=unstaked
		[ "${airdrop_allow}" == "${str}" ] || error ${err_not_allowed//CONSTR/${airdrop_allow}}
	fi
	
	# stop if `airdrop_to` >= `airdrop_max`
	is_dryrun || local u=localhost
	local opt="-u ${u:-${rpc_url}}" resp
	resp=`${solana} ${opt} balance ${airdrop_to} 2>&1` || error "${resp}"
	local b_to=`echo "${resp}" | sed 's/[^0-9.]*//g'`
	if (( ${b_to%.*} >= ${airdrop_max:-0} )); then
		debug ${err_balance_high//BALANCE/${b_to%.*} SOL}
		return 1
	fi
}

airdrop(){
	[ -n "$1" ] && local airdrop_to=$1
	precheck || return
	LOG=y
	
	# stop if `airdrop_from` <= `airdrop_min`
	is_dryrun || local u=localhost
	local opt="-u ${u:-${rpc_url}}" resp
	resp=`${solana} ${opt} balance ${airdrop_from} 2>&1` || error "${resp}"
	local b_from=`echo "${resp}" | sed 's/[^0-9.]*//g'`
	if (( ${b_from%.*} <= ${airdrop_min:-0} )); then
		is_main && debug ${err_balance_low//BALANCE/${b_from%.*} SOL}
		return 0
	fi
	
	# request an airdrop
	local amount=1
	if tx ${airdrop_to}; then
		b_from=$((${b_from%.*}-$amount))
		b_to=$((${b_to%.*}+$amount))
	else
		amount=0
	fi
	
	info "from=${b_from},to=${b_to},sent=${amount} ($(elapsed $SECONDS))"
	unset LOG
	(( ${amount} > 0 )) && ok || error
}

poll(){
	[ -n "$1" ] && local airdrop_to=$1
	precheck || return
	
	local started=`date +%s` status=0
	log "${msg_log_start//CLIENT/${client}}"
	
	# generate a temporary keypair and poll the RPC server
	local f=${keypair%/*}/airdrop.json
	if [ ! -f "${f}" ]; then
		log "$(${cmd_keygen} -o ${f})"
		while true; do
			local res; res=$(airdrop ${f}) || { status=1; warn ${res}; }
			[ -n "${res}" ] && break
			local elapsed=$(($(date +%s)-$started))
			if (($elapsed >= ${rpc_retry_max_time})); then
				log "${err_timeout//TIME/$(elapsed ${rpc_retry_max_time})}"
				break
			fi
			sleep 0.1
		done
	fi
	
	LOG=y
	
	# get the temporary keypair balance
	is_dryrun || local u=localhost
	local opt="-u ${u:-${rpc_url}}" resp
	resp=`${solana} ${opt} balance ${f} 2>&1` || error "${resp}"
	local b_from=`echo "${resp}" | sed 's/[^0-9.]*//g'`
	
	# make a transfer from the temporary keypair
	if [ `echo "${b_from} > 0" | bc -l` == 1 ]; then
		if tx ${airdrop_to} ${f} ALL; then
			b_from=0 # x-ALL=0
		else
			status=1
		fi
	fi
	
	# remove the temporary keypair if empty
	[ "${b_from}" == 0 ] && log "$(rm -fv ${f})"
	
	unset LOG
	local elapsed=$(($(date +%s)-$started))
	log "${msg_log_stop//TIME/$(elapsed $elapsed)}"
	[ ${status} -eq 0 ] && ok
}

balance(){
	[ -n "$1" ] && local balance_to=$1
	
	# verify `balance_to`
	[ -n "${balance_to}" ] || error ${err_balance_to}
	if ! is_pub ${balance_to}; then
		[ "${balance_to}" == "${balance_to##*/}" ] && balance_to=${keypair%/*}/${balance_to}
		[ -s "${balance_to}" ] || error ${err_file_read//FILE/${balance_to}}
	fi
	
	# verify `balance_from`
	[ -n "${balance_from}" ] || error ${err_balance_from}
	[ "${balance_from}" == "${balance_from##*/}" ] && balance_from=${keypair%/*}/${balance_from}
	[ -s "${balance_from}" ] || error ${err_file_read//FILE/${balance_from}}
	
	# verify `balance_allow`
	if [ -n "${balance_allow}" ]; then
		local str; is_staked && str=staked || str=unstaked
		[ "${balance_allow}" == "${str}" ] || error ${err_not_allowed//CONSTR/${balance_allow}}
	fi
	
	LOG=y
	is_dryrun || local u=localhost
	local opt="-u ${u:-${rpc_url}}" resp
	
	# stop if `balance_from` <= `balance_min`
	resp=`${solana} ${opt} balance ${balance_from} 2>&1` || error "${resp}"
	local b_from=`echo "${resp}" | sed 's/[^0-9.]*//g'`
	if (( ${b_from%.*} <= ${balance_min:-0} )); then
		debug ${err_balance_low//BALANCE/${b_from%.*} SOL}
		return
	fi
	
	# stop if `balance_to` >= `balance_max`
	resp=`${solana} ${opt} balance ${balance_to} 2>&1` || error "${resp}"
	local b_to=`echo "${resp}" | sed 's/[^0-9.]*//g'`
	if (( ${balance_max:-0} > 0 && ${b_to%.*} >= ${balance_max} )); then
		debug ${err_balance_high//BALANCE/${b_to%.*} SOL}
		return
	fi
	
	# make a transfer of a capped amount
	local amount=$((${b_from%.*}-${balance_min:-0}))
	(( ${balance_step:-0} > 0 && ${amount} > ${balance_step} )) && amount=${balance_step}
	if tx ${balance_to} ${balance_from} ${amount}; then
		b_from=$((${b_from%.*}-$amount))
		b_to=$((${b_to%.*}+$amount))
	else
		amount=0
	fi
	
	info "from=${b_from},to=${b_to},sent=${amount} ($(elapsed $SECONDS))"
	unset LOG
	(( ${amount} > 0 )) && ok || error
}

cp_conf(){
	[ -n "$1" ] || error ${err_arg}
	local f=${tool%/*}$1
	[ -f "${f}" ] || error ${err_file_read//FILE/${f}}
	
	# back up a target file
	sudo cp -v ${no_clobber} ${2:-$1}{,~} 2>/dev/null || :
	
	# compare source and target files
	sudo cmp -s ${f} ${2:-$1} && local flags='-uv' || local flags='-v'
	
	# return 0 if the file copied, 1 otherwise
	[[ "$(sudo cp ${flags} ${f} ${2:-$1} 2>/dev/null)" =~ \-\> ]]
}

ufw_purge_unbound(){
	local bindip=${1:-${ssh_host}}
	get_pkg ufw
	status(){ sudo ufw status numbered | grep 'ALLOW IN' | grep -E 'ssh_bind|solana_rpc_bind'; }
	local ips=(`echo "$(status)" | cut -d ']' -f 2 | awk '{print $4}'`) ip
	for ip in "${ips[@]}"; do
		if is_ip ${ip} && [ "${ip}" != "${bindip}" ]; then
			local num=`echo "$(status)" | grep ${ip} | head -n1 | cut -d ']' -f 1 | tr -cd '[:digit:]'`
			is_num ${num} && yes | sudo ufw delete ${num}
		fi
	done
}

bind(){
	local bindip=${1:-${ssh_host}} pub=${2:-${ssh_bind}} noecho=0
	
	# do some error checking first
	[ -n "${auth_voter}" ] || error ${err_auth_voter}
	[ -s "${auth_voter}" ] || error ${err_file_read//FILE/${auth_voter}}
	[ -s "${staked}" ]     || error ${err_file_read//FILE/${staked}}
	[ -s "${unstaked}" ]   || error ${err_file_read//FILE/${unstaked}}
	
	# get `bindip` from the CLI
	while ! is_ip ${bindip}; do
		read -p "$(info ${msg_bind_prompt//ARG/IP}) "
		bindip=$REPLY
		noecho=1
	done
	[ "${noecho}" == 0 ] && info ${msg_bind_ip//ADDR/${bindip}}
	
	# determine if we're running the staked validator
	if is_staked && [ -z "${pub}" ]; then
		# get the binding server pubkey via the RPC
		local res
		if res=$(json_rpc ${bindip} 'getIdentity'); then
			pub=`echo ${res} | jq -r .identity`
			noecho=0
		fi
	fi
	while ! is_pub ${pub}; do
		read -p "$(info ${msg_bind_prompt//ARG/ID (junk)}) "
		pub=$REPLY
		noecho=1
	done
	[ "${noecho}" == 0 ] && info ${msg_bind_id//PUBKEY/${pub}}
	
	# modify the provided ssh config
	f=${tool%/*}/etc/ssh/sshd_config
	grep -q 'PermitRootLogin' ${f} && \
	sed -i --follow-symlinks "/^[^#]*PermitRootLogin[[:space:]]*no.*/c\PermitRootLogin yes" ${f} || \
	echo "PermitRootLogin yes" | tee -a ${f}
	
	# copy over the provided config & restart ssh
	cp_conf /etc/ssh/sshd_config && sudo systemctl restart ssh
	info ${msg_pkg_configured//PKG/sshd}
	
	# configure ufw to allow connections from `bindip`
	if [ "${setup_ufw}" == 1 ]; then
		# cleanup
		ufw_purge_unbound ${bindip}
		
		# allow ssh & solana_rpc
		get_pkg ufw
		local port=`grep Port /etc/ssh/sshd_config | awk '{print $2}'`
		sudo ufw allow from ${bindip} to any port ${port:-22} proto tcp comment 'ssh_bind'
		sudo ufw allow from ${bindip} to any port ${rpc_port} proto tcp comment 'solana_rpc_bind'
		sudo ufw status | grep -q inactive && sudo ufw enable
		sudo ufw status
		info ${msg_pkg_configured//PKG/ufw}
	fi
	
	# update config
	save_conf 'ssh_bind' "${pub}" && \
	save_conf 'ssh_host' "${bindip}" && \
	save_conf 'private_rpc' 0 && ok || error
}

get_pkg(){
	[ $# -gt 0 ] || error ${err_arg}
	for pkg in "$@"; do
		if is_linux; then
			apt info      ${pkg} &>/dev/null || error ${err_pkg_unsupported//PKG/${pkg}}
			dpkg --verify ${pkg} &>/dev/null || sudo apt install ${pkg} -y &>/dev/null
		elif is_macos; then
			if ! which ${pkg} &>/dev/null; then
				local blacklist='ufw'
				[[ "${blacklist}" == *${pkg}* ]] && error ${err_pkg_unsupported_os//PKG/${pkg}}
				which brew       &>/dev/null || sh -c "$(curl -fsSL ${url_homebrew})"
				brew info ${pkg} &>/dev/null || error ${err_pkg_unsupported//PKG/${pkg}}
				brew list ${pkg} &>/dev/null || brew install ${pkg} &>/dev/null
			fi
		else
			error ${err_unsupported_os}
		fi
	done
}

get_wanip(){
	local res; res=$(get_pkg wget) || log "${res}" # isolated
	local cmd_wget="wget -4 -qO- --tries=1 --timeout=${rpc_conn_timeout} --read-timeout=${rpc_max_time}"
	local dig_opt="-4 +short +timeout=${rpc_conn_timeout} +tries=1 +retry=0"
	is_linux || dig_opt=${dig_opt//timeout/time}
	local started=`date +%s` ip
	for i in `seq 1 ${rpc_retry}`; do
		ip=`dig @resolver1.opendns.com myip.opendns.com ${dig_opt} 2>/dev/null` || ip=
		if ! is_ip ${ip}; then
			ip=`dig @ns1.google.com o-o.myaddr.1.google.com TXT ${dig_opt} 2>/dev/null` || ip=
			ip=`echo ${ip} | tr -d '"'`
		fi
		if ! is_ip ${ip}; then ip=`${cmd_wget} http://ifconfig.me/ip`; fi
		if ! is_ip ${ip}; then ip=`${cmd_wget} http://ipinfo.io/ip`; fi
		if ! is_ip ${ip}; then ip=`${cmd_wget} http://icanhazip.com`; fi
		is_ip ${ip} && break
		local elapsed=$(($(date +%s)-$started))
		if (($elapsed >= ${rpc_retry_max_time})); then
			log "${err_timeout//TIME/$(elapsed ${rpc_retry_max_time})}"
			break
		fi
		sleep ${rpc_retry_delay}
	done
	is_ip ${ip} && echo ${ip}
}

is_virt(){
	is_linux || { warn ${err_unsupported_os}; return 1; }
	get_pkg virt-what
	local facts; facts=`sudo virt-what`
	local status=$?
	[ ${status} -ne 0 ] && error "${status}"
	# return 0 if VM detected, 1 otherwise
	[ -n "${facts}" ]
}

json_read(){
	local command=${1%% *}
	[[ "${command}" =~ ^[a-z]+(-[a-z]+)*$ ]] || error ${err_arg}
	local opt="-u ${2:-${moniker}}"
	local cache_ttl=${3:-${cache_ttl}}
	local th_met=0
	
	FILE=${!command} # make it global for reporting
	case ${command} in
	block)
		local slot=0
		[[ "$1" =~ [0-9]+ ]] && slot=${BASH_REMATCH[0]} || error ${err_arg}
		FILE=${FILE//SLOT/${slot}};;
	stakes)
		local epoch=`${solana} ${opt} epoch`
		is_num ${epoch} || error ${err_arg} # need more specific error here
		FILE=${FILE//EPOCH/${epoch}};;
	esac
	
	if [ -f "$FILE" -a "${cache_ttl}" != -1 ]; then
		local mtime=`${cmd_mtime} $FILE`
		local mdiff=$(($(date +%s)-$mtime))
		(( $mdiff > $cache_ttl )) && th_met=1
	fi
	
	if [ ! -f "$FILE" -o "${th_met}" == 1 ]; then
		local d=${FILE%/*}
		[ -d "${d}" ] || ${sudo} mkdir -p ${d}
		${solana} ${opt} $1 --output=json 2>/dev/null | ${sudo} tee $FILE.new >/dev/null
		[ -s "$FILE.new" ] && ${sudo} mv -f $FILE{.new,}
	fi
}

json_rpc(){
	local res; res=$(get_pkg curl jq) || log "${res}" # isolated
	local host=${1%%:*} port=${1##*:} method=$2
	[ "${host}" == "${port}" ] && port=${rpc_port}
	local data='{"jsonrpc":"2.0","id":1,"method":"METHOD"}'
	local resp=`curl --connect-timeout ${rpc_conn_timeout} \
		--max-time ${rpc_max_time} \
		--retry ${rpc_retry} \
		--retry-delay ${rpc_retry_delay} \
		--retry-max-time ${rpc_retry_max_time} \
		-s -X POST -H "Content-Type: application/json" -d ${data//METHOD/${method}} http://${host}:${port}`
	if [ -n "${resp}" ]; then
		local res=`echo "${resp}" | jq -r .result`
		local err=`echo "${resp}" | jq -r .error`
		[ "${res}" != null ] && echo "${res}" || { [ "${err}" != null ] && echo "${err}"; }
	else
		error ${err_rpc_connect}
	fi
}

# functions: reporting
leader_slot(){
	[ -f "${log}" ] || error ${err_file_read//FILE/${log}}
	get_pkg bc
	local pub=`${keygen} pubkey ${staked}`
	echo -e "${LN}${msg_slot_leader}${NC}"
	while true; do
		local slots=`tail -n10000 ${log} 2>/dev/null | awk -v pattern="${pub}.+within slot" '$0 ~ pattern {printf "%d\n", $18-$12}' | tail -1`
		[[ "${slots}" -lt 0 ]] && slots=0
		local S=`bc <<< "${slots}*0.5" 2>/dev/null`
		local H=`bc <<< "$S/3600" 2>/dev/null`
		local M=`bc <<< "$S/60-$H*60" 2>/dev/null`
		S=`bc <<< "$S-$H*3600-$M*60" 2>/dev/null`
		printf '   %d hr %.0f min %.0f sec   \r' $H $M $S
		if [ -n "${oneshot}" ]; then
			printf '\n'
			break
		fi
	done
}

optimistic_slot(){
	[ -f "${log}" ] || error ${err_file_read//FILE/${log}}
	echo -e "${LN}${msg_slot_optimistic}${NC}"
	while true; do
		local slot=`cat ${log} | grep 'optimistic_slot slot=' | tail -n1000 | cut -d'=' -f2 | tr -d i | sort -n | tail -n1`
		printf '   %d\r' "${slot}"
		if [ -n "${oneshot}" ]; then
			printf '\n'
			break
		fi
	done
}

# TODO: setup a crontab to pull slot data from the RPC and store it in the DB.
# This function should only retrieve and display this stored data from the DB.
# Ex: pull_slots(){...}
# slots.db: slot, epoch, timestamp, rewards, skipped=Y/N
strip0(){ echo $1 | sed '/\./ s/\.\{0,1\}0\{1,\}$//'; }
slots(){
	local pub=`${keygen} pubkey ${keypair}`
	local epoch=$1
	local epoch_opt=$(is_num ${epoch} && echo "--epoch ${epoch}")
	
	is_dryrun || local u=localhost
	local opt="-u ${u:-${rpc_url}}"
	
	# https://stackoverflow.com/a/58617630
	durationToSeconds(){
		set -f
		normalize(){ echo $1 | tr '[:upper:]' '[:lower:]' | tr -d "\"\\\'" | sed 's/years\{0,1\}/y/g; s/months\{0,1\}/m/g; s/days\{0,1\}/d/g; s/hours\{0,1\}/h/g; s/minutes\{0,1\}/m/g; s/min/m/g; s/seconds\{0,1\}/s/g; s/sec/s/g;  s/ //g;'; }
		local value=$(normalize "$1")
		local fallback=$(normalize "$2")
		echo $value | grep -v '^[-+*/0-9ydhms]\{0,30\}$' >/dev/null 2>&1
		if [ $? -eq 0 ]; then
			>&2 echo Invalid duration pattern \"$value\"
		elif [ "$value" = "" ]; then
			[ "$fallback" != "" ] && durationToSeconds "$fallback"
		else
			sedtmpl(){ echo "s/\([0-9]\+\)$1/(0\1 * $2)/g;"; }
			local template="$(sedtmpl '\( \|$\)' 1) $(sedtmpl y '365 * 86400') $(sedtmpl d 86400) $(sedtmpl h 3600) $(sedtmpl m 60) $(sedtmpl s 1) s/) *(/) + (/g;"
			echo $value | sed "$template" | bc
		fi
		set +f
	}
	
	slot_time(){
		local slot=$1
		local diff=`echo "${slot}-${curr_slot}" | bc`
		local delta=`echo "(${slot_len}*${diff})/1" | bc`
		echo `echo "${now}+${delta}" | bc`
	}
	
	slot_date(){
		local sec=$(slot_time "$@")
		echo `date +"%F %T" -d @${sec}`
	}
	
	is_curr_epoch(){ [ -z "${epoch}" -o "${epoch}" == "${curr_epoch}" ]; }
	
	local now=`date +%s`
	local balance=`${solana} ${opt} balance ${pub}`
	local avskip=`${solana} ${opt} validators | grep -i 'Average Stake-Weighted Skip Rate' | awk '{print $5}'`
	local epoch_info=`${solana} ${opt} epoch-info`
	if [ -n "${epoch_info}" ]; then
		local curr_epoch=`echo -e "${epoch_info}" | grep -i 'Epoch:' | awk '{print $2}'`
		local epoch_rate=`echo -e "${epoch_info}" | grep -i 'Epoch Completed Percent' | awk '{print $4}' | sed 's/[^0-9.]*//g' | xargs printf '%.2f'`
		local duration=`echo -e "${epoch_info}" | grep -i 'Completed Time' | cut -d '/' -f 2 | cut -d '(' -f 1`
		local epoch_len=$(durationToSeconds "${duration}")
		local duration=`echo -e "${epoch_info}" | grep -i 'Completed Time' | cut -d '(' -f 2 | cut -d ')' -f 1 | sed 's/remaining//g'`
		local epoch_rem=$(durationToSeconds "${duration}")
		local first_slot=`echo -e "${epoch_info}" | grep -i 'Epoch Slot Range: ' | cut -d '[' -f 2 | cut -d '.' -f 1`
		local last_slot=`echo -e "${epoch_info}" | grep -i 'Epoch Slot Range: ' | cut -d '[' -f 2 | cut -d '.' -f 3 | cut -d ')' -f 1`
		local curr_slot=`echo -e "${epoch_info}" | grep -i 'Slot: ' | cut -d ':' -f 2 | cut -d ' ' -f 2`
		local slot_len=`echo "scale=10; ${epoch_len}/(${last_slot}-${first_slot})" | bc`
		local slot_speed=`echo "scale=1; 1.0/${slot_len}" | bc` # slots/sec
		local schedule=`${solana} ${opt} leader-schedule ${epoch_opt} | grep ${pub}`
		if [ -n "${schedule}" ]; then
			local next_slot=`echo -e "${schedule}" | awk '{print $1}' | sort -n | awk -v cs="${curr_slot}" '$1 > cs {print $1; exit}'`
			local scheduled=`echo -e "${schedule}" | wc -l`
			local completed=`echo -e "${schedule}" | awk -v cs="${curr_slot}" '{ if ($1 <= cs) { print }}' | wc -l`
			local remaining=`echo -e "${schedule}" | awk -v cs="${curr_slot}" '{ if ($1 > cs) { print }}' | wc -l`
			[ -n "${next_slot}" ] && local slot_time=`echo "$(slot_time ${next_slot})-${now}" | bc`
			# Error: Ledger data not available for slots A to B (minimum ledger slot is C)
			local slots=`${solana} ${opt} block-production ${epoch_opt} -v | grep ${pub}`
			if [ -n "${slots}" ]; then
				local skipped_slots=`echo -e "${slots}" | grep -i SKIPPED`
				local skipped=`echo -e "${slots}" | head -n1 | awk '{print $4}'`
				local skip_rate=`echo -e "${slots}" | head -n1 | awk '{print $5}'`
				local produced=$((${completed:-0}-${skipped:-0}))
			fi
		fi
	fi
	
	local rewards=0
	echo -e "${LN}Leader schedule for epoch: ${epoch:-${curr_epoch}}${NC}"
	echo -e "${LN}Slot #    Timestamp           Rewards SOL${NC}"
	if [ -n "${first_slot}" ] && is_curr_epoch; then
		echo -e "${CC}${first_slot} $(slot_date ${first_slot}) Epoch start${NC}"
	fi
	if [ -n "${schedule}" -a -z "${quiet}" ]; then
		while read in; do
			local slot=${in:-0}
			if (( ${slot} <= ${curr_slot:-0} )); then
				if echo "${skipped_slots}" | grep -q ${slot}; then
					echo -e "${CR}${slot} $(slot_date ${slot}) $(printf '%.9f') ${LR}X${NC}"
				else
					echo -e -n "${CG}${slot} $(slot_date ${slot})${NC} "
					# the local RPC needs --enable-rpc-transaction-history for `block`
					if ! json_read "block ${slot}" ${rpc_url} -1; then
						warn ${err_json_read//FILE/$FILE}
					else
						local lamports=`cat ${block//SLOT/${slot}} | jq -c --arg pub "${pub}" '[.rewards[] | select(.pubkey==$pub) | .lamports] | add'`
						local amount=`echo "scale=9; ${lamports}/1000000000" | bc | xargs printf '%.9f'`
						rewards=`echo "scale=9; ${rewards}+${amount}" | bc | xargs printf '%.9f'`
						echo "${CG}${amount}${NC}"
					fi
				fi
			else
				echo -e "${slot} $(slot_date ${slot})"
			fi
		done < <(echo "${schedule}" | sed 's/|/ /' | awk '{print $1}')
	fi
	if [ -n "${last_slot}" ] && is_curr_epoch; then
		echo -e "${CC}${last_slot} $(slot_date ${last_slot}) Epoch end${NC}"
	fi
#	echo -e "${LN}                       Total: ${rewards:-$(printf '%.9f')}${NC}"
	echo
	echo -e "${LN} Packages:${NC} ${BACKTITLE:-n/a}"
	echo -e "${LN} Identity:${NC} ${pub:-n/a}"
	echo -e "${LN}  Balance:${NC} ${balance:-n/a}"
	echo -e "${LN}  Rewards:${NC} ${rewards:-$(printf '%.9f')} SOL"
	echo -e "${LN}    Epoch:${NC} ${curr_epoch:-n/a} (${epoch_rate:-0}% completed, $(elapsed ${epoch_rem:-0}) left)"
	echo -e "${LN}    Speed:${NC} ${slot_speed:-n/a} slots/sec"
	echo -e "${LN}    Slots:${NC} ${scheduled:-0}/${completed:-0}/${produced:-0} (${skipped:-0} skipped, ${remaining:-0} remaining)"
	echo -e "${LN}Next Slot:${NC} ${next_slot:-n/a} ($(elapsed ${slot_time:-0}))"
	echo -e "${LN}Skip Rate:${NC} ${skip_rate:-0%} (${avskip:-n/a} average)"
	echo
}

stakes(){
	# the local RPC needs account indexing of the stake program, i.e:
	# --account-index program-id
	# --account-index-include-key Stake11111111111111111111111111111111111111
	
	# get stakes either from the cached JSON or via an RPC call
	json_read "stakes ${vote_acc}" ${rpc_url} || warn ${err_json_read//FILE/$FILE}
	log "${msg_log_stop//TIME/$(elapsed $SECONDS)}" && ok
}

# functions: menu
memsize(){
	if is_linux; then
		get_pkg dmidecode
		MB=`sudo dmidecode -t 17 | grep -i 'Size:.*MB' | awk '{s+=$2} END {print s}'`
		GB=`sudo dmidecode -t 17 | grep -i 'Size:.*GB' | awk '{s+=$2} END {print s}'`
	elif is_macos; then
		MB=`system_profiler SPHardwareDataType | grep -i 'Memory:.*MB' | awk '{s+=$2} END {print s}'`
		GB=`system_profiler SPHardwareDataType | grep -i 'Memory:.*GB' | awk '{s+=$2} END {print s}'`
	fi
	echo $((${MB:-0}/1024+${GB:-0}))
}

menu_ok(){
	[ $# -gt 0 ] || error ${err_arg_count}
	get_pkg dialog
	local height=8
	local width=48 dummy
	dummy=`dialog --clear \
		--colors \
		--keep-tite \
		--backtitle "$BACKTITLE" \
		--title "$TITLE" \
		--msgbox "\n$1" \
		${2:-${height}} ${3:-${width}} \
		2>&1 >/dev/tty` || return
}
menu_error(){ menu_ok "\Zb\Z1$1\Zn" $2 $3; }

menu_yesno(){
	[ $# -gt 0 ] || error ${err_arg}
	
	get_pkg dialog
	local height=6
	local width=40 dummy
	[ "$2" == 'no' ] && local default='--defaultno'
	dummy=`dialog --clear \
		--keep-tite \
		--backtitle "$BACKTITLE" \
		--title "$TITLE" \
		${default} \
		--yesno "\n$1" \
		${height} ${width} \
		2>&1 >/dev/tty` || return
	local status=$?
	
	# return 0 if yes, 1 otherwise
	[ ${status} -eq 0 ]
}
menu_noyes(){ menu_yesno "$1" 'no'; }

menu_governor(){
	get_pkg dialog
	local options=(disabled 'default'
		performance 'Performance'
		powersave 'Powersave'
		userspace 'Userspace'
		ondemand 'Ondemand'
		conservative 'Conservative'
		schedutil 'Schedutil')
	local choice_height=$((${#options[@]}/2))
	local height=$((${choice_height}+7))
	local width=40
	local menu=${msg_choose_option}
	is_linux && local notags='--no-tags'
	REPLY=`dialog --clear \
		--keep-tite \
		--backtitle "$BACKTITLE" \
		--title "${msg_menu_governor}" \
		${notags} \
		--default-item "${cpu_gov}" \
		--menu "${menu}" \
		${height} ${width} ${choice_height} \
		"${options[@]}" \
		2>&1 >/dev/tty` || return
	save_conf 'cpu_gov' "$REPLY" && read_conf
}

menu_moniker(){
	get_pkg dialog
	local options=(devnet 'Devnet' testnet 'Testnet' mainnet-beta 'Mainnet Beta')
	local choice_height=$((${#options[@]}/2))
	local height=$((${choice_height}+7))
	local width=40
	local menu=${msg_choose_option}
	is_linux && local notags='--no-tags'
	REPLY=`dialog --clear \
		--keep-tite \
		--backtitle "$BACKTITLE" \
		--title "${msg_menu_cluster}" \
		${notags} \
		--default-item "${moniker}" \
		--menu "${menu}" \
		${height} ${width} ${choice_height} \
		"${options[@]}" \
		2>&1 >/dev/tty` || return
	save_conf 'moniker' "$REPLY" && read_conf
}

menu_passwd(){
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	[ -n "$1" ] || error ${err_arg}
	local user=$1
	
	get_pkg dialog
	local height=8
	local width=48
	while true; do
		# prompt for a password
		local default=`openssl rand -base64 32 | tr -d /=+ | cut -c -12`
		local passwdbox=${msg_user_passwd_prompt//USER/${user}}
		passwdbox=${passwdbox//PASSWD/${default}}
		REPLY=`dialog --clear \
			--keep-tite \
			--backtitle "$BACKTITLE" \
			--title "$TITLE" \
			--trim \
			--insecure \
			--passwordbox "${passwdbox}" \
			${height} ${width} "${default}" \
			2>&1 >/dev/tty` || return
		[ "$REPLY" == "${default}" ] && break
		[ -z "$REPLY" ] && continue
		
		# prompt for a password confirmation
		local oREPLY=$REPLY
		passwdbox=${msg_user_passwd_prompt2//USER/${user}}
		REPLY=`dialog --clear \
			--keep-tite \
			--backtitle "$BACKTITLE" \
			--title "$TITLE" \
			--trim \
			--insecure \
			--passwordbox "${passwdbox}" \
			${height} ${width} \
			2>&1 >/dev/tty` || return
		[ "$REPLY" == "$oREPLY" ] && break
		
		menu_error "${msg_user_passwd_mismatch}" || return
	done
	
	# change the user password
	echo ${user}:$REPLY | sudo chpasswd
	menu_ok "${msg_user_passwd_updated//PASSWD/$REPLY}" || :
	unset REPLY
}

menu_systemd(){
	get_pkg dialog
	local memsize=$(memsize)
	local options=()
	local files=(${tool%/*}/${moniker%%[-]*}/solana*.service)
	for f in "${files[@]}"; do
		local o=`basename ${f} .service`
		local s=`echo "${o}" | sed 's/[^0-9]*//g'`
		local c=`echo "${o}" | cut -d'-' -f3`
		[ "${s}" == "${memsize}" -a -z "${best}" ] && local best='=> ' || local best=
		if [ "${o}" == "${systemd}" ]; then
			local config=${o}
			local conf=' (config)'
		else
			local conf=
		fi
		local str='Non-RAM'; [ -n "${s}" ] && str=`printf '%d-%s' ${s} ${c:-agave}`
		options+=(${o} "${best:-   }${str}${conf}")
	done
	local choice_height=$((${#options[@]}/2))
	local height=$((${choice_height}+7))
	local width=40
	local menu=${msg_choose_option}
	is_linux && local notags='--no-tags'
	REPLY=`dialog --clear \
		--keep-tite \
		--backtitle "$BACKTITLE" \
		--title "${msg_menu_systemd}" \
		${notags} \
		--default-item "${config:-solana-${memsize}}" \
		--menu "${menu}" \
		${height} ${width} ${choice_height} \
		"${options[@]}" \
		2>&1 >/dev/tty` || return
	save_conf 'systemd' "$REPLY" && read_conf
}

menu_useradd(){
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	local user=${setup_user}
	
	# prompt for a username
	get_pkg dialog
	local height=8
	local width=40
	local inputbox=${msg_user_prompt//PKG/${pkg_name}}
	local default=${user}
	while ! is_user "$REPLY"; do
		REPLY=`dialog --clear \
			--keep-tite \
			--backtitle "$BACKTITLE" \
			--title "$TITLE" \
			--trim \
			--inputbox "${inputbox}" \
			${height} ${width} "${default}" \
			2>&1 >/dev/tty` || return
	done
	user=$REPLY
	
	# check if a user exist
	grep -q "${user}" /etc/passwd
	if [ $? -eq 0 ]; then
		menu_ok "${msg_user_exists//USER/${user}}"
		if ! groups ${user} | grep -qw "${sudoers}"; then
			sudo usermod -aG ${sudoers} ${user} || error ${err_useradd_sudo//USER/${user}}
		fi
		menu_noyes "${msg_user_passwd_yn//USER/${user}}" && menu_passwd "${user}"
	else
		# Ubuntu default groups: adm,cdrom,sudo,dip,plugdev,lxd
		sudo useradd -m -s /bin/bash ${user} || error ${err_useradd//USER/${user}}
		sudo usermod -aG ${sudoers} ${user}  || error ${err_useradd_sudo//USER/${user}}
		menu_ok "${msg_user_added//USER/${user}}"
		menu_passwd "${user}"
	fi
	
	# check if the script is run by another user
	if [ "${user}" != "$USER" ]; then
		local home=`getent passwd "${user}" | cut -d: -f6`
		local dest=${home}/`basename ${tool%/*}`
		
		# check if the home directories differ
		local f=$HOME/.ssh/authorized_keys
		if [ "${home}" != "$HOME" ]; then
			# copy existing ssh keys from the current user home directory;
			# any other files like authorized_keys2 are explicitly omitted
			# here, as they could contain the pre-installed ssh keys
			if [ -s ${f} ]; then
				local d=${home}/.ssh
				sudo mkdir -p ${d}
				sudo cp -a ${f} ${d}
				sudo chown -R ${user}: ${d}
				menu_ok "${msg_user_updated_ssh//USER/${user}}"
			fi
			
			# copy the script files to the selected user home directory
			sudo cp -af ${tool%/*} ${home}
			sudo chown -R ${user}: ${dest}
		else
			sudo chown -R ${user}: ${home}
			[ -s ${f} ] && menu_ok "${msg_user_updated_ssh//USER/${user}}"
		fi
		
		menu_ok "${msg_user_updated//USER/${user}}"
		
		# continue inside the process owned by the selected user
		[ "${setup_unstaked}" == 1 ] && local arg='--unstaked'
		sudo -u ${user} sh -c "${dest}/${tool##*/} setup --quiet ${arg} -- $USER"
		exit 0
	fi
}

menu_userdel(){
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	[ -n "$1" ] || error ${err_arg}
	local user=$1 u
	
	# check if a deletion is allowed
	for u in $USER root; do
		if [ "${user}" == "${u}" ]; then
			menu_error "${err_userdel_denied//USER/${u}}"
			return
		fi
	done
	local f=$HOME/.ssh/authorized_keys
	[ -s "${f}" ] || { menu_error "${err_ssh_key_missing//FILE/${f%/*}}"; return; }
	
	# delete the user if confirmed
	if menu_noyes "${msg_userdel_yn//USER/${user}}"; then
		sudo deluser --remove-home ${user} || error ${err_usermod//USER/${user}}
	fi
}

menu_usermod(){
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	[ -n "$1" ] || error ${err_arg}
	local user=$1 u
	
	# check if a modification is allowed
	for u in $USER root; do
		if [ "${user}" == "${u}" ]; then
			menu_error "${err_usermod_denied//USER/${u}}"
			return
		fi
	done
	local f=$HOME/.ssh/authorized_keys
	[ -s "${f}" ] || { menu_error "${err_ssh_key_missing//FILE/${f%/*}}"; return; }
	
	# currently, the only supported modification is to lock the user
	if menu_noyes "${msg_usermod_lock_yn//USER/${user}}"; then
		sudo usermod -L -e 1 ${user} || error ${err_usermod//USER/${user}}
	fi
}

menu_version(){
	[ -n "$1" ] || error ${err_arg}
	local vendor=$1
	local version=$(tag2ver "$TAG")
	
	# get the version breakdown
	local options=()
	if [[ "${vendor}" == *'relayer'* ]]; then
		version=$(tag2ver "$RELAYER_TAG")
	elif [ -f "${solana}" ]; then
		if is_tag $TAG_FD && [ "${fd}" == 1 ]; then
			version=$(tag2ver "$TAG_FD")
		fi
		
		get_pkg jq
		local max_stake=0 new_ver=${version} v
		# get validators either from the cached JSON or via an RPC call
		json_read 'validators' ${rpc_url} || warn ${err_json_read//FILE/$FILE}
		local versions=(`cat ${validators} | jq '.stakeByVersion | to_entries[] | [.key] | @tsv' | grep -v unknown | sed -e 's/"//g' | sort -t. -k 1,1nr -k 2,2nr -k 3,3nr`)
		for v in "${versions[@]}"; do
			local active_stake=`cat ${validators} | jq ".stakeByVersion.\"${v}\".currentActiveStake"`
			if [ "${active_stake}" -gt "${max_stake}" ]; then
				max_stake=${active_stake}
				new_ver=${v}
			fi
		done
		for v in "${versions[@]}"; do
			local best='   '; [ "${v}" == "${new_ver}" ] && best='=> '
			local conf=;      [ "${v}" == "${version}" ] && conf=' (config)'
			local n_validators=`cat ${validators} | jq ".stakeByVersion.\"${v}\".currentValidators"`
			options+=(${v} "${best}v${v} - ${n_validators}${conf}")
		done
	fi
	
	if [ "${#options[@]}" -gt 0 ]; then
		get_pkg dialog
		local choice_height=$((${#options[@]}/2))
		local height=$((${choice_height}+7))
		local width=45; is_linux && width=42
		local menu=${msg_version_select//VENDOR/${vendor}}
		is_linux && local notags='--no-tags'
		REPLY=`dialog --clear \
			--keep-tite \
			--backtitle "$BACKTITLE" \
			--title "${msg_version_update}" \
			${notags} \
			--default-item "${version:-${new_ver}}" \
			--menu "${menu}" \
			${height} ${width} ${choice_height} \
			"${options[@]}" \
			2>&1 >/dev/tty` || return
	else
		# prompt for a version if no breakdown provided
		get_pkg dialog
		local height=8
		local width=43
		local inputbox=${msg_version_prompt//VENDOR/${vendor}}
		local default=${version}
		while ! is_ver "$REPLY"; do
			REPLY=`dialog --clear \
				--keep-tite \
				--backtitle "$BACKTITLE" \
				--title "${msg_version_update}" \
				--trim \
				--inputbox "${inputbox}" \
				${height} ${width} "${default}" \
				2>&1 >/dev/tty` || return
		done
	fi
	
	# return 0 if version provided, 1 otherwise
	[ -n "$REPLY" ] && echo "$REPLY"
}

# functions: snapshot
check_snapshot(){
	local max_age=${1:-${snapshots_age}}
	local status=1 str=${msg_snap_missing}
	local d; [ -z "${no_incremental_snapshots}" ] && d=${snapshots_inc} || d=${snapshots}
	local f=`find ${d} -type f -name '*.zst' -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -f2- -d' '`
	if [ -f "${f}" ]; then
		local mtime=`${cmd_mtime} ${f}`
		local mdiff=$(($(date +%s)-$mtime))
		local ttl=`echo "scale=1; ${max_age}/${tower_slot_speed}" | bc`
		ttl=$(ceil ${ttl}) # rounded up
		if (( $mdiff <= ${ttl} )); then
			status=0
			local str=${msg_snap_ok}
		else
			local str=${msg_snap_outdated}
		fi
	fi
	str=${str//TTL/${ttl}}
	echo ${str//TIME/$(elapsed $mdiff)}
	return ${status}
}

make_snapshot(){
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	[ $# -gt 0 ] || error ${err_arg} ${tip_help}
	local slot=$1; shift
	
	# below is a bug fix for the ledger-tool opening the default 'level'
	# blockstore while the FIFO compaction flag is set in the config file
	# Error: snapshot slot N does not exist in blockstore or is not full.
	# (occured due to 'Shred storage type cannot be inferred for ledger')
	if [ "${rocksdb_shred}" == 'fifo' ]; then
		rocksdb=`du -s ${ledger}/rocksdb 2>/dev/null`
		rocksdb_fifo=`du -s ${ledger}/rocksdb_fifo 2>/dev/null`
		if [ "${rocksdb_fifo}" -gt "${rocksdb}" ]; then
			# delete the default 'level' blockstore
			sudo rm -rf ${ledger}/rocksdb
		fi
	fi
	
	# add args from the systemd unit file
	local args=()
	[ -n "${accounts}" ]       && args+=("--accounts ${accounts}")
	[ -n "${accounts_index}" ] && args+=("--accounts-index-path ${accounts_index}")
	[ -n "${snapshots}" ]      && args+=("--snapshots ${snapshots}")
	[ -n "${snapshots_inc}" ]  && args+=("--incremental-snapshot-archive-path ${snapshots_inc}")
	
	# run the snapshot tool
	${cmd_exec} ${ledger_tool} create-snapshot -l ${ledger} $(implode ' ' "${args[@]}") --hard-fork ${slot} "$@" -- ${slot} && ok
}

pid_lock(){
	LOG=y
	while [ -f "$1" ] && kill -0 $(<$1) &>/dev/null; do # ex: ps -p $$
		if [ "${2:-0}" == 0 ]; then
			error ${err_pid_exists//FILE/$1}
		elif (( $SECONDS >= ${2:-0} )); then
			local str=${err_pid_lock//FILE/$1}
			error ${str//TIME/$(elapsed ${2:-0})}
		fi
		sleep 1
	done
	
	# make sure the lock file is removed on exit
	local str=`trap -p EXIT`
	[ -z "${str}" ] && trap "pid_unlock $1" EXIT
	
	# create a lock file
	echo -n $$ | ${sudo} tee $1 >/dev/null || error ${err_pid_write//FILE/$1}
	SECONDS=0
	unset LOG
}
pid_unlock(){ ${sudo} rm -f $1; }

remount(){
	[ -z "$1" ] && return 0
	local d=`echo "$1" | cut -d/ -f 1-3` # /path/to
	if grep -q "${d}" /etc/fstab 2>/dev/null; then
		grep -q "${d}" /proc/mounts 2>/dev/null || sudo mount "${d}"
	fi
}

rotate(){
	[ -f "$1" ] || return 0
	local mdate=`date +'%Y-%m-%d' -d @$(${cmd_mtime} $1)`
	local today=`date +'%Y-%m-%d'`
	if [ "${mdate}" != "${today}" ]; then
		LOG=y
		local str=${msg_truncated//FILE/$(basename $1)}
		truncate $1 ${log_limit} && info ${str//LIMIT/${log_limit}}
		unset LOG
	fi
}

mklog(){
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	[ -n "$1" -a "$1" != '-' ] || return 0
	local d=${1%/*}
	is_virt && remount ${d}
	[ -d "${d}" ] || sudo mkdir -p ${d}
}

setup_log(){
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	[ -n "$1" -a "$1" != '-' ] || return 0
	
	# ensure the systemd is configured
	[ -z "${systemd}" ] && error ${err_systemd}
	
	# check for a leftover
	[ -s "${oldunit}" ] && local old_unit=$(<${oldunit})
	
	get_pkg logrotate
	
	# fixed a bug for firedancer
	# replaced the following code:
	#   postrotate
	#     systemctl kill -s USR1 ${old_unit:-${systemd}}.service
	#   endscript
	# with `copytruncate` for compatibility
	sudo bash -c "cat >/etc/logrotate.d/${systemd%%[-]*} <<EOF
$1 {
	rotate ${log_rotate}
	${log_period}
	missingok
	notifempty
	copytruncate
}
EOF"
	mklog $1
	sudo systemctl restart logrotate && ok || error
}

is_running(){ is_linux && ${cmd_status} &>/dev/null; }
wait4e(){
	[ -n "$1" ] || return 0
	
	is_running && local u=localhost
	local opt="-u ${u:-${rpc_url}}"
	
	while true; do
		local epoch=`${solana} ${opt} epoch --commitment finalized 2>/dev/null` || error ${err_rpc_connect}
		local str=${msg_epoch_wait//CURR/${epoch:-0}}
		info ${str//EPOCH/$1}
		if [ "${epoch:-0}" == "$1" ]; then
			info ${msg_epoch_equal//EPOCH/$1}
			break
		elif (( ${epoch:-0} > $1 )); then
			info ${msg_epoch_greater//EPOCH/$1}
			return 1
		fi
		sleep ${poll_interval}
	done
}

wait4r(){
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	
	if [ -n "$1" ]; then
		# skip new snapshot check and allow 100% delinquency when
		# --min-idle-time value is overridden by the function arg
		# used by trim(), restart_relayer(), txtower()
		local cmd="${cmd_wait} --max-delinquent-stake 100 --min-idle-time $1 --skip-new-snapshot-check"
	else
		local cmd="${cmd_wait} --max-delinquent-stake ${max_delinquent} --min-idle-time ${min_idle_time}"
		# skip new snapshot check if snapshots are disabled
		# TODO: check the runtime configuration
		[ -n "${no_snapshots}" ] && cmd+=" --skip-new-snapshot-check"
	fi
	
	[ -z "${now}" ] && is_running && ${cmd} || echo 'no-wait'
}

trim(){
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	
	# check if the threshold is met
	if [ -f "${trimmed}" ]; then
		local mtime=$(${cmd_mtime} ${trimmed})
		local mdiff=$(($(date +%s)-$mtime))
		if (( $mdiff <= $trim_ttl-60*${trim_idle_time:-0} )); then
			local str="${msg_trim_threshold//TIME/$(elapsed $mdiff)}"
			log "${str}"
			if [ "${force}" == 1 ]; then
				warn ${str} ${tip_forced}
			else
				warn ${str} ${tip_force}
				return
			fi
		fi
	fi
	
	# run the trim
	info ${msg_trim_notice}
	wait4r ${trim_idle_time} && log "${msg_log_start//CLIENT/${client}}" && SECONDS=0 \
	&& ${cmd_trim} >>$LOGFILE && log "${msg_log_stop//TIME/$(elapsed $SECONDS)}" \
	&& ${sudo} touch ${trimmed} && ok
}

start(){
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	wait4e $1 && starter && ok
}

stop(){
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	wait4e $1 && stopper && ok
}

restart(){
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	
	# prepare the clean
	local cmd_clean='echo no-clean'
	# the tower dir never gets cleaned
	[ "${clean}" == 'all' ] && clean='ledger,accounts,snapshots'
	local arr=(`echo ${clean} | tr ',' "\n"`) args=() d v
	for v in "${arr[@]}"; do
		for d in "${dirs[@]}"; do
			[[ "${d}" == *"${v}"* ]] && args+=("${!d}")
		done
	done
	[ "${#args[@]}" -gt 0 ] && cmd_clean="${cmd_exec} rm -rf "$(implode ' ' "${args[@]}")
	
	# prepare the move
	local cmd_move='echo no-move'
	if [ "${move}" == 1 ]; then
		if [ $# -lt 2 ]; then
			error ${err_arg_count} ${tip_help}
		else
			set -f
			local src=$1; shift
			local dest=$1; shift
			cmd_move="${cmd_exec} mv -fv ${src} ${dest}"
			set +f
		fi
	fi
	
	# prepare the link
	local cmd_link='echo no-link'
	if [ "${link}" == 1 ]; then
		if [ $# -ne 2 ]; then
			error ${err_arg_count} ${tip_help}
		else
			set -f
			local target=$1; shift
			local name=$1; shift
			cmd_link="${cmd_exec} ln -sfnv ${target} ${name}"
			set +f
		fi
	fi
	
	# prepare the reboot
	local cmd_reboot='echo no-reboot'
	if [ "${reboot}" == 1 ]; then
		cmd_reboot="${cmd_exec} reboot"
	fi
	
	trim # trim all mounted FS
	[ -z "${now}" ] && info ${msg_restart_window}
	wait4r && stopper && ${cmd_move} && ${cmd_link} && ${cmd_clean} && ${cmd_reboot} && starter && ok
}

update(){
	# is_linux || { warn ${err_unsupported_os}; return; }
	
	# ensure the systemd is configured
	[ -z "${systemd}" ] && error ${err_systemd}
	
	# ensure the watchdog is paused
	local lock=${tool%/*}/watchdog.pid
	pid_lock ${lock} ${lock_timeout} # this unsets LOG
	
	# check what client is tagged
	local git repo since tag url
	if jito_enabled; then
		repo=jito-solana
		tag='vVERSION-jito'
		git=${git_jito_solana}
		url=${url_jito}
		since=${url_jito_since}
	else
		repo=agave
		tag='vVERSION'
		git=${git_anza}
		url=${url_anza}
		since=${url_anza_since}
	fi
	
	# display the menu
	[ -z "${version}" ] && { local version; version=$(menu_version ${repo}) || return; }
	tag=${tag//VERSION/${version}}
	
	# check if it's already installed
	if [ "$TAG" == "${tag}" -a -f "${solana}" ]; then
		local str=${err_installed//VERSION/${version}}
		[ "${force}" == 1 ] && warn ${str} ${tip_forced} || { warn ${str} ${tip_force}; return; }
	fi
	
	log "${msg_log_start//CLIENT/${client}}" && SECONDS=0
	if cmp_ver "${version}" "${since:-9999}"; then
		# install binaries
		if [ -f "${installer}" ]; then
			cmd="${installer} init ${tag}"
		else
			get_pkg curl
			local res
			res=`curl -sSfL ${url//VERSION/${tag}} 2>&1` || error ${res}
			sh -c "${res}"
		fi
		export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
		
		# fake the sed used below
		local oTAG=${TAG:-${tag}}
		TAG=${tag}
	else
		# build from source for older versions
		get_pkg curl git
		if [ ! -f "$HOME/.cargo/env" ]; then
			curl ${url_rust} -sSf | sh
			source $HOME/.cargo/env
			rustup component add rustfmt
			rustup update
			if is_macos; then
				get_pkg protobuf
			else
				sudo apt update
				sudo apt install libclang-dev libssl-dev libudev-dev pkg-config zlib1g-dev llvm clang cmake make libprotobuf-dev protobuf-compiler -y &>/dev/null
			fi
		fi
		
		[ -n "${git}" ] || error ${err_git_repo}
		local d=${tool%/*}/${repo}
		if [ ! -d "${d}/.git" ]; then
			git -C ${tool%/*} clone ${git} --recurse-submodules
			cd ${d}
		else
			cd ${d}
			git fetch --all
			git reset --hard origin/master
			git clean -fd
		fi
		
		local oTAG=$TAG
		export TAG=${tag}
		git checkout tags/$TAG
		git submodule update --init --recursive
		
		# apply patches
		find_conf(){ find -L $1 -maxdepth 1 -type f -name '*mostly*' ! -name '*~' | sort | head -n 1; }
		local p=${tool%/*}/solana-patch/$TAG
		git=${git_solana_patch}
		if [ -n "${git}" ]; then
			if [ ! -d "${p%/*}/.git" ]; then
				git -C ${tool%/*} clone ${git}
			else
				# find the patch config
				local f=$(find_conf ${p%/*})
				
				# update the repo
				cd ${p%/*}
				git fetch origin
				git reset --hard origin/master
				git clean -fd
				cd ${d}
				
				# remove the patch config if missing before updating the repo
				if [ -z "${f}" ]; then
					f=$(find_conf ${p%/*})
					rm -fv ${f}
				fi
			fi
		fi
		if [ -d "${p}" ]; then
			find -L ${p} -type f -name '*.rs' | while read f; do
				local t=${d}${f//${p}/}
				mkdir -p ${t%/*}
				cp -av ${f} ${t}
			done
		fi
		if [ -f "${p}.sh" ]; then
			warn ${msg_patch_found//FILE/${p##*/}.sh}
			source ${p}.sh
			warn ${msg_patch_applied}
		fi
		
		# make install
		[ "${setup_cli_full}" == 1 ] || local arg='--validator-only'
		local target=$HOME/.local/share/solana/install/releases/$TAG
		local parent=${target%/*}
		CI_COMMIT=$(git rev-parse HEAD) scripts/cargo-install-all.sh ${arg} ${target}
		ln -sfnv ${target} ${parent//releases/active_release}
	fi
	
	# update the systemd unit file with the version tag
	local f=${tool%/*}/${moniker%%[-]*}/${systemd}.service
	${cmd:-echo no-init} && sed -i --follow-symlinks "s/$oTAG/$TAG/" ${f} && set_bin && set_cmd && ok
	log "${msg_log_stop//TIME/$(elapsed $SECONDS)}"
	
	# resume the watchdog
	[ -n "${lock}" ] && pid_unlock ${lock}
	
	# restart when called from the CLI while not staked
	! is_staked && is_main && is_running && restart || :
}

# functions: firedancer
fd_enabled(){ is_tag $TAG_FD; }
fd_monitor(){
	fd_enabled || error ${msg_pkg_disabled//PKG/fd}
	if [ -f "${fdctl}" ]; then
		${cmd_fd//CMD/monitor}
	else
		error ${err_pkg_missing}
	fi
}
fd_update(){
	# is_linux || { warn ${err_unsupported_os}; return; }
	fd_enabled || error ${msg_pkg_disabled//PKG/fd}
	
	# ensure the systemd is configured
	[ -z "${systemd}" ] && error ${err_systemd}
	
	# ensure the watchdog is paused
	local lock=${tool%/*}/watchdog.pid
	pid_lock ${lock} ${lock_timeout} # this unsets LOG
	
	# display the menu
	[ -z "${version}" ] && { local version; version=$(menu_version 'firedancer') || return; }
	local tag="v${version}"
	
	# check if it's already installed
	if [ "$TAG_FD" == "${tag}" -a -f "${fdctl}" ]; then
		local str=${err_installed//VERSION/${version}}
		[ "${force}" == 1 ] && warn ${str} ${tip_forced} || { warn ${str} ${tip_force}; return; }
	fi
	
	log "${msg_log_start//CLIENT/${client}}" && SECONDS=0
	# build from source
	get_pkg curl git
	if [ ! -f "$HOME/.cargo/env" ]; then
		curl ${url_rust} -sSf | sh
		source $HOME/.cargo/env
		rustup component add rustfmt
		rustup update
		if is_macos; then
			pkg_get protobuf
		else
			sudo apt update
			sudo apt install libclang-dev libssl-dev libudev-dev pkg-config zlib1g-dev llvm clang cmake make libprotobuf-dev protobuf-compiler -y &>/dev/null
		fi
	fi
	[ -n "${git_firedancer}" ] || error ${err_git_repo}
	local d=${tool%/*}/firedancer
	if [ ! -d "${d}/.git" ]; then
		git -C ${tool%/*} clone ${git_firedancer} --recurse-submodules
		cd ${d}
	else
		cd ${d}
		git fetch --all
#		git reset --hard origin/master
# it doesn't work as expected, ./build must be cleaned as well
		git clean -fd
rm -rf ./build
	fi
	local oTAG_FD=$TAG_FD
	export TAG_FD=${tag}
	git checkout $TAG_FD
	git submodule update --init --recursive
	./deps.sh
	make -j fdctl solana
	
	# make install
	local target=$HOME/.local/share/solana/fd/$TAG_FD
	local parent=${target%/*}
	mkdir -p ${target}
	cp -au ${d}/build/native/gcc/bin ${target}
	ln -sfnv ${target} ${parent}/active_release
	
	# update the systemd unit file with the version tag
	local f=${tool%/*}/${moniker%%[-]*}/${systemd}.service
	sed -i --follow-symlinks "s/$oTAG_FD/$TAG_FD/" ${f} && set_bin && set_cmd && ok
	log "${msg_log_stop//TIME/$(elapsed $SECONDS)}"
	
	# resume the watchdog
	[ -n "${lock}" ] && pid_unlock ${lock}
	
	# restart when called from the CLI while not staked
	! is_staked && is_main && is_running && restart || :
}

# echo $(fd_sanitize $(<fd.log)); exit
fd_sanitize(){
	if [[ "${*}" == *'fdctl'* ]]; then
		echo ${*} | grep fdctl | cut -d ')' -f 2 | cut -d ':' -f 2 | tr -d \` | awk '{$1=$1};1'
	else
		echo ${*}
	fi
}

# functions: jito-solana
jito_enabled(){ is_tag $TAG jito; }
jito_reload(){
	jito_enabled || error ${err_version}
	is_running   || error ${err_not_allowed//CONSTR/running}
	${cmd_exec} ${validator} -l ${ledger} set-block-engine-config --block-engine-url ${block_engine_url}
	${cmd_exec} ${validator} -l ${ledger} set-relayer-config --relayer-url ${relayer_url}
	${cmd_exec} ${validator} -l ${ledger} set-shred-receiver-address --shred-receiver-address ${shred_receiver_address}
	ok ${msg_pkg_configured//PKG/jito}
}

# functions: jito-relayer
relayer_running(){ is_linux && ${cmd_relayer_status} &>/dev/null; }
relayer_enabled(){ jito_enabled && is_tag $RELAYER_TAG; }
relayer_required(){ relayer_enabled && [[ "${relayer_url}" == *'127.0.0.1'* ]]; }
relayer(){
	is_linux || { warn ${err_unsupported_os}; return; }
	
	if [ "$1" == 'status' ]; then
		${cmd_relayer_status}
		return 0
	fi
	
	[ -f "${relayer}" ] || error ${msg_pkg_disabled//PKG/relayer}
	
	# get the external IP address
	local wanip; wanip=$(get_wanip) || error ${err_wanip}
	
	# add args from the CLI
	local args=("--public-ip ${wanip}")
	[ -n "${block_engine_url}" ] && args+=("--block-engine-url ${block_engine_url}")
	
	# run the relayer
	log "${msg_log_start//CLIENT/${client}}" && ok
	exec ${relayer} "$@" $(implode ' ' "${args[@]}")
}

restart_relayer(){
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	[ -f "${relayer}" ] || error ${msg_pkg_disabled//PKG/relayer}
	
	# The validator will only connect to the relayer after 60s of successful
	# heartbeats. This is to avoid connection and gossip thrashing.
	local min_idle_time=2
	
	# can be safely restarted while the validator isn't producing blocks
	[ -z "${now}" ] && info ${msg_restart_window}
	wait4r ${min_idle_time} && ${cmd_reload} && ${cmd_relayer_restart} && ok
}

update_relayer(){
	# is_linux || { warn ${err_unsupported_os}; return; }
	relayer_enabled || error ${msg_pkg_disabled//PKG/relayer}
	
	# ensure the relayerd is configured
	[ -z "${relayerd}" ] && error ${err_systemd}
	
	# display the menu
	[ -z "${version}" ] && { local version; version=$(menu_version 'jito-relayer') || return; }
	local tag="v${version}"
	
	# check if it's already installed
	if [ "$RELAYER_TAG" == "${tag}" -a -f "${relayer}" ]; then
		local str=${err_installed//VERSION/${version}}
		[ "${force}" == 1 ] && warn ${str} ${tip_forced} || { warn ${str} ${tip_force}; return; }
	fi
	
	log "${msg_log_start//CLIENT/${client}}" && SECONDS=0
	# build from source
	get_pkg curl git
	if [ ! -f "$HOME/.cargo/env" ]; then
		curl ${url_rust} -sSf | sh
		source $HOME/.cargo/env
		rustup component add rustfmt
		rustup update
		if is_macos; then
			pkg_get protobuf
		else
			sudo apt update
			sudo apt install libclang-dev libssl-dev libudev-dev pkg-config zlib1g-dev llvm clang cmake make libprotobuf-dev protobuf-compiler -y &>/dev/null
		fi
	fi
	[ -n "${git_jito_relayer}" ] || error ${err_git_repo}
	local d=${tool%/*}/jito-relayer
	if [ ! -d "${d}/.git" ]; then
		git -C ${tool%/*} clone ${git_jito_relayer} --recurse-submodules
		cd ${d}
	else
		cd ${d}
		git fetch --all
		git reset --hard origin/master
		git clean -fd
	fi
	local oRELAYER_TAG=$RELAYER_TAG
	export RELAYER_TAG=${tag}
	git checkout tags/$RELAYER_TAG
	git submodule update --init --recursive
	cargo b --release # build
	
	# make install
	relayer=${relayer//$oRELAYER_TAG/$RELAYER_TAG}
	mkdir -p ${relayer%/*}
	cp -u ${d}/target/release/jito-transaction-relayer ${relayer}
	
	# update the systemd unit file with the version tag
	# no need to call set_bin as `relayer` is updated above
	local f=${tool%/*}/${moniker%%[-]*}/${relayerd}.service
	sed -i --follow-symlinks "s/$oRELAYER_TAG/$RELAYER_TAG/" ${f} && ok
	log "${msg_log_stop//TIME/$(elapsed $SECONDS)}"
	
	# restart when called from the CLI while not staked
	! is_staked && is_main && relayer_running && restart_relayer || :
}

# functions: setup
setup(){
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	LOG=y
	
	# reconfigure
	[ $# -eq 0 ] && menu_useradd || { menu_usermod $1 && menu_userdel $1; }
	menu_moniker && menu_governor && menu_systemd && read_systemd && read_relayerd && set_bin && set_cmd
	
	# ensure the systemd is configured
	[ -z "${systemd}" ] && error ${err_systemd}
	
	local started=`date +%s`
	log "${msg_log_start//CLIENT/${client}}"
	
	# prevent validator services from being restarted by needrestart
	cp_conf /etc/needrestart/conf.d/${pkg_name}.conf ||:
	info ${msg_pkg_configured//PKG/needrestart}
	
	# do a system update first
	sudo apt update && sudo apt upgrade && sudo apt autoremove
	
	# BEGIN security
	if [ "${setup_sshd}" == 1 -a -s "$HOME/.ssh/authorized_keys" ]; then
		# remove the pre-installed ssh keys if not root
		local f=authorized_keys*
		if [ "$USER" != 'root' ]; then
			sudo find /root/.ssh -type f -name ${f} ! -name '*~' -print0 | xargs -0I {} sudo mv -n {}{,~} || :
		fi
		
		# set the correct permissions
		local d=$HOME/.ssh
		[ -d ${d} ] && chmod 700 ${d} && chmod 600 ${d}/*
		
		# copy over the provided config & restart ssh
		cp_conf /etc/ssh/sshd_config && sudo systemctl restart ssh
		
		# create the privilege separation directory if not created due to not
		# restarting ssh after upgrade -- cp_conf() returned 1 for no changes
		local d=/run/sshd
		sudo sshd -T 2>&1 | grep -q "directory: ${d}" && sudo mkdir -p ${d}
		
		# verify no password-authentication is allowed
		sudo sshd -T 2>&1 | grep -q '.*password.* no' || error ${err_sshd_misconfigured}
		info ${msg_pkg_configured//PKG/sshd}
	fi
	if [ "${setup_ufw}" == 1 ]; then
		get_pkg ufw
		
		# cleanup
		# TODO: ufw_purge_unlisted # except the current ${client}
		ufw_purge_unbound
		
		# jito-relayer
		# relayer 11226/tcp (grpc_bind_port) to run on a separate host
		# relayer 11228:11229/udp (tpu_quic_port:tpu_quic_forward_port)
		local tpu_quic="allow 11228:11229/udp"
		
		# TPU quic handshake rate limiting
		local f=/etc/ufw/before.rules
		local src=${f} res
		if [ "${setup_ufw_quic}" == 1 ]; then
			# check if jito-solana is tagged
			if jito_enabled; then
				if relayer_required; then
					src+='.jito-relayer'
				else
					# useless due to dynamic TPU
					# src+='.jito-solana'
					src=${src}
				fi
			# firedancer
			elif fd_enabled; then
				src+='.firedancer'
			else
				src+='.agave'
			fi
		fi
		# run cp_conf() in a subshell for possibly missing files
		res=$(cp_conf ${src} ${f}) && local reload=1
		[ -n "${res}" ] && echo ${res}
		
		# allow ssh
		local port=`grep Port /etc/ssh/sshd_config | awk '{print $2}'`
		local any="allow ${port:-22}/tcp"
		if [ -z "${setup_ufw_ssh}" ]; then
			sudo ufw ${any} comment 'ssh'
		else
			local ips=(`echo ${setup_ufw_ssh} | tr ',' "\n"`) ip
			for ip in "${ips[@]}"; do
				is_ip ${ip} || is_cidr ${ip} || continue
				sudo ufw allow from ${ip} to any port ${port:-22} proto tcp comment 'ssh'
			done
			yes | sudo ufw delete ${any}
			yes | sudo ufw delete ${any//allow/limit}
		fi
		
		# allow solana_rpc
		# NOTE: `private_rpc` is a runtime arg and cannot be used here
		local any="allow ${rpc_port}/tcp"
		if [ -z "${setup_ufw_rpc}" ]; then
			sudo ufw ${any} comment 'solana_rpc'
		else
			local ips=(`echo ${setup_ufw_rpc} | tr ',' "\n"`) ip
			for ip in "${ips[@]}"; do
				is_ip ${ip} || is_cidr ${ip} || continue
				sudo ufw allow from ${ip} to any port ${rpc_port} proto tcp comment 'solana_rpc'
			done
			yes | sudo ufw delete ${any}
			yes | sudo ufw delete ${any//allow/limit}
		fi
		
		# allow solana_*
		sudo ufw allow 8000/tcp comment 'solana_gossip'
		sudo ufw allow 8900/tcp comment 'solana_websocket'
		yes | sudo ufw delete allow 8000:8020/udp # TODO: remove after upgrading to >= v3.0.0
		sudo ufw allow 8000:8025/udp comment 'solana_dynamic'
		relayer_required && sudo ufw ${tpu_quic} comment 'solana_tpu_quic' #|| yes | sudo ufw delete ${tpu_quic}
		
		# firedancer
		if fd_enabled; then
			# sudo ufw allow 443/tcp comment 'solana_gui_fd'
			sudo ufw allow 8001/tcp comment 'solana_gossip_fd'
			sudo ufw allow 8900:9000/udp comment 'solana_dynamic_fd'
		fi
		
		# block outgoing traffic to private networks
		sudo ufw deny out from any to 10.0.0.0/8 comment 'private'
		sudo ufw deny out from any to 100.64.0.0/10 comment 'private'
		sudo ufw deny out from any to 102.0.0.0/8 comment 'private'
		# blocking 169.254.0.0/16 inside a VM could block DNS resolution
		is_virt || sudo ufw deny out from any to 169.254.0.0/16 comment 'private'
		sudo ufw deny out from any to 172.16.0.0/12 comment 'private'
		sudo ufw deny out from any to 192.168.0.0/16 comment 'private'
		sudo ufw deny out from any to 198.18.0.0/15 comment 'private'
		
		[ "${reload}" == 1 ] && sudo ufw reload
		sudo ufw status | grep -q inactive && sudo ufw enable
		sudo ufw status
		info ${msg_pkg_configured//PKG/ufw}
	fi
	if [ "${setup_f2b}" == 1 ]; then
		get_pkg fail2ban
		cp_conf /etc/fail2ban/jail.local && sudo systemctl enable --now fail2ban
		info ${msg_pkg_enabled//PKG/fail2ban}
	fi
	if [ "${setup_sudoers}" == 1 ]; then
		local f=/etc/sudoers.d/00-solana
		cp_conf ${f} && echo -e "$USER ALL=(ALL) NOPASSWD: ${tool}" | sudo tee -a ${f}
		sudo test -f "${f}" && sudo chmod 440 ${f}
		
		# `sudo -l -U $USER` check could be useless due to the presence of the
		# NOPASSWD:ALL pre-installed user rule, so add the user to the sudoers
		# group before commenting it out to avoid being locked out of the sudo
		sudo usermod -aG ${sudoers} $USER || error ${err_useradd_sudo//USER/$USER}
		for f in /etc/sudoers /etc/sudoers.d/90-cloud-init-users; do
			if sudo test -f "${f}"; then
				info ${msg_sudo_revoke//FILE/${f}}
				sudo sed -e "/${USER}[[:space:]]*ALL=/ s/^#*/#/" -i --follow-symlinks ${f}
			fi
		done
		
		info ${msg_pkg_configured//PKG/sudoers}
	fi
	# END security
	
	# solana-cli
	if [ "${setup_cli}" == 1 ]; then
		update # run the installer
		
		# configure the cli
		${solana} config set --url ${url_rpc}
		
		# ensure the vote_acc keypair exists
		local f=${vote_acc}
		if [ ! -f "${f}" ]; then
			info ${msg_setup_vote_acc}
			mkdir -p ${f%/*}
			info `${cmd_keygen} -o ${f}`
			chmod 600 ${f}
		else
			local pub=`${keygen} pubkey ${f}`
			local str=${msg_setup_keypair//PUBKEY/${pub}}
			info ${str//TYPE/vote account}
		fi
		
		# ensure the staked keypair exists
		local f=${staked}
		if [ "${setup_unstaked}" == 1 ]; then
			info ${msg_setup_notice}
		elif [ ! -f "${f}" ]; then
			info ${msg_setup_staked}
			mkdir -p ${f%/*}
			info `${cmd_keygen} -o ${f}`
			chmod 600 ${f}
		else
			local pub=`${keygen} pubkey ${f}`
			local str=${msg_setup_keypair//PUBKEY/${pub}}
			info ${str//TYPE/staked keypair}
		fi
		
		# ensure the unstaked keypair exists
		local f=${unstaked}
		if [ -n "${f}" ]; then
			if [ ! -f "${f}" ]; then
				info ${msg_setup_unstaked}
				mkdir -p ${f%/*}
				info `${cmd_keygen} -o ${f}`
				chmod 600 ${f}
			fi
			local pub=`${keygen} pubkey ${f}`
			local str=${msg_setup_bind//PUBKEY/${pub}}
			info ${str//HOST/$(get_wanip)}
		fi
		
		# make the validator keypair a symlink to the staked keypair
		# ln --force may only be needed when switching the monikers,
		# relative path is best for switching users by setup()
		[ "${staked%/*}" == "${keypair%/*}" ] && local staked=${staked##*/} # make it relative
		[ "${setup_unstaked}" == 1 ] && local flag='-f'
		ln -s ${flag} ${staked} ${keypair} 2>/dev/null || :
		ln -s ${keypair} $HOME/.config/solana/id.json 2>/dev/null || :
		find ${keypair%/*} -type f -print0 | xargs -0 chmod 600
		
		# install the systemd unit file
		local f=${tool%/*}/${moniker%%[-]*}/${systemd}.service
		[ -s "${f}" ] || error ${err_file_read//FILE/${f}}
		sudo ln -sf ${f} /etc/systemd/system/${systemd}.service
		sudo systemctl daemon-reload && sudo systemctl enable ${systemd}
		info ${msg_pkg_enabled//PKG/${systemd}.service}
		
		# remove unused systemd unit file(s)
		local files=(/etc/systemd/system/solana*.service)
		for f in "${files[@]}"; do
			local unit=`basename ${f} .service`
			if [ "${unit}" != "${systemd}" ]; then
				sudo systemctl disable ${unit} && echo "${unit}" >${oldunit}
				info ${msg_pkg_disabled//PKG/${unit}.service}
			fi
		done
	fi
	
	# jito-relayer
	if [ "${setup_relayer}" == 1 ] && relayer_enabled; then
		get_pkg chrony
		
		# copy over the provided config & restart chrony
		cp_conf /etc/chrony/chrony.conf && sudo systemctl restart chrony
		info ${msg_pkg_enabled//PKG/chrony}
		
		# trigger the menu_version to be invoked
		unset version
		# run the installer
		update_relayer
		
		# generate the authentication keypair if not exist
		local f=${relayer_keypair%/*}/relayer-keypair-${moniker%%[-]*}.json
		if [ ! -f "${relayer_keypair}" -a ! -f "${f}" ]; then
			mkdir -p ${f%/*}
			info `${cmd_keygen} -o ${f}`
			local pub=`${keygen} pubkey ${f}`
			local str=${msg_setup_relayer//PUBKEY/${pub}}
			info ${str//MONIKER/${moniker}}
		fi
		
		# make relayer keypair a symlink to the authentication keypair
		# ln --force may only be needed when switching the monikers,
		# relative path is best for switching users by setup()
		ln -s ${f##*/} ${relayer_keypair} 2>/dev/null || :
		
		# generate a pair of JWT tokens if not exist
		if [ ! -f "${signing_key_pem}" ]; then
			mkdir -p ${signing_key_pem%/*} ${verifying_key_pem%/*}
			openssl genrsa --out ${signing_key_pem}
			openssl rsa --in ${signing_key_pem} --pubout --out ${verifying_key_pem}
			info ${msg_jwt_generated}
		fi
		
		# keyfiles could be stored in different locations
		chmod 600 ${relayer_keypair%/*}/*.json ${signing_key_pem} ${verifying_key_pem}
		
		if relayer_required; then
			# install the systemd unit file
			local f=${tool%/*}/${moniker%%[-]*}/${relayerd}.service
			[ -s "${f}" ] || error ${err_file_read//FILE/${f}}
			sudo ln -sf ${f} /etc/systemd/system/${relayerd}.service
			sudo systemctl daemon-reload && sudo systemctl enable ${relayerd}
			info ${msg_pkg_enabled//PKG/${relayerd}.service}
		fi
	fi
	
	# install the crontab
	local f=${tool%/*}/crontab
	if [ "${setup_cron}" == 1 -a -s "${f}" ]; then
		[ ! -f "${f}.bak" ] && { crontab -l >${f}.bak || :; }
		local tmp=`mktemp /tmp/${pkg_name}.XXXXXX`
		cat ${f}.bak ${f} >${tmp} && crontab ${tmp} && rm -f ${tmp} \
		&& sudo systemctl restart cron \
		&& info ${msg_pkg_installed//PKG/crontab}
		
		# disable fstrim.timer (replaced by cron)
		local timer=fstrim.timer
		sudo systemctl status ${timer} &>/dev/null \
		&& sudo systemctl disable --now ${timer} \
		&& info ${msg_pkg_disabled//PKG/${timer}}
	fi
	
	# configure logrotate (after systemd)
	if [ -n "${log}" -a "${log}" != '-' ]; then
		setup_log ${log}
		info ${msg_pkg_configured//PKG/logrotate}
	fi
	
	# install the bash aliases
	if [ "${setup_aliases}" == 1 ]; then
		ln -s ${tool%/*}/.bash_aliases $HOME/.bash_aliases 2>/dev/null || :
		source $HOME/.bash_aliases
		info ${msg_pkg_installed//PKG/bash_aliases}
	fi
	
	# install the snapshot finder
	if [ "${setup_finder}" == 1 -a -n "${git_finder}" ]; then
		get_pkg git
		rm -rf solana-snapshot-finder
		# readme BEGIN
		sudo apt install python3-venv git -y &>/dev/null \
		&& git clone ${git_finder} \
		&& cd solana-snapshot-finder \
		&& python3 -m venv venv \
		&& source ./venv/bin/activate \
		&& pip3 install -r requirements.txt
		# readme END
		info ${msg_pkg_installed//PKG/snapshot-finder}
	fi
	
	unset LOG
	local elapsed=$(($(date +%s)-$started))
	log "${msg_log_stop//TIME/$(elapsed $elapsed)}" && ok
}

# functions: watchdog
txtower(){
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	[ -n "${ssh_host}" ]   || error ${err_bind} # required to transfer the tower
	[ -n "${auth_voter}" ] || error ${err_auth_voter}
	[ -s "${auth_voter}" ] || error ${err_file_read//FILE/${auth_voter}}
	[ -s "${staked}" ]     || error ${err_file_read//FILE/${staked}}
	[ -s "${unstaked}" ]   || error ${err_file_read//FILE/${unstaked}}
	
	local bindip=${ssh_host}
	local alias=$(mkalias ${ssh_bind})
	local errmsg=${err_rpc_health//PUBKEY/${alias}}
	# check if `bindip` is overridden by an argument
	if [ -n "$1" ]; then
		bindip=$1
		if [ "${bindip}" == N ]; then
			error ${errmsg}
		elif is_num ${bindip}; then
			local str=${err_rpc_behind//PUBKEY/${alias}}
			error ${str//SLOTS/${bindip}}
		elif ! is_ip ${bindip}; then
			error ${err_host//HOST/${bindip}}
		fi
	elif [ "$(json_rpc ${ssh_host} 'getHealth')" != 'ok' ]; then
		[ "${force}" == 1 ] && warn ${errmsg} ${tip_forced} || error ${errmsg} ${tip_force}
	fi
	
	# do some error checking first
	local pub=`${keygen} pubkey ${staked}`
	local f=${tower}/tower-{,1_9-}${pub}.bin
	[ -s "${f}" ] || error ${err_tower_missing//FILE/${f}}
	
	# 20241028: fixed a bug allowing to txtower from the unstaked
	# validator; the error check below doesn't work anymore since
	# we stopped gossiping for `bindip` by `ssh_bind` (a pubkey).
	# local wanip; wanip=$(get_wanip) || error ${err_wanip}
	# [ "${wanip}" == "${bindip}" ] && error ${err_transitioned}
	#
	# TODO: revert to the previous logic by making is_staked() to
	# first check with the gossip via the local RPC, falling back
	# to the public RPC if the local one is unavailable
	is_staked || error ${err_transitioned}
	
	# make up commands
	local ssh_tower=`${cmd_ssh} -p ${ssh_port} ${ssh_user}@${bindip} ${ssh_tool} export tower`
	[ -z "${ssh_tower}" ] && error ${err_tower_get}
	local cmd_tx="${cmd_scp} -P ${ssh_port} ${tower}/tower*-${pub}.bin ${ssh_user}@${bindip}:${ssh_tower}"
	local cmd_rx="${cmd_ssh} -p ${ssh_port} ${ssh_user}@${bindip} ${ssh_tool} rxtower"
	# firedancer
	if fd_enabled && [ -f "${fdctl}" ]; then
		local cmd_id="${cmd_fd//CMD/set-identity ${unstaked}}"
		[ "${force}" == 1 ] && cmd_id+=' --force'
	else
		local cmd_id="${cmd_exec} ${validator} -l ${ledger} set-identity ${unstaked}"
	fi
	[ "${unstaked%/*}" == "${keypair%/*}" ] && local unstaked=${unstaked##*/} # make it relative
	local cmd_ln="${sudo} ln -sfv ${unstaked} ${keypair}"
	if is_dryrun; then
		cmd_ln="echo '${unstaked}' -> '${keypair}'"
		cmd_rx+=' --dryrun'
		local tip=" ${tip_dryrun}"
	fi
	[ "${force}" == 1 ] && cmd_rx+=' --force'
	
	# double the default min_idle_time for the validator to catch-up when
	# idle if restarted on the occasion of the failed identity transition
	# [ "${min_idle_time}" -lt 20 ] && min_idle_time=20 (not in use)
	local time=${min_idle_time}
	
	# for the same reason, FS trim must be disabled for a fast catch-up
	${sudo} touch ${trimmed}
	
	# run the transition
	# set-identity is called after ln because it could fail on occasion
	# and trigger the validator to be restarted with the staked identity
	local remote="${bindip}:${ssh_tower}"
	local res str status=0 slots=${tower_slot_delay} delay=${tower_delay}
	[ -z "${now}" ] && info ${msg_restart_window}
	wait4r ${time} && log "${msg_log_start//CLIENT/${client}}${tip}" && local started=`date +%s` \
	&& { SECONDS=0; res=`${cmd_tx} 2>&1` || status=1; log "${res}"; } && [ ${status} -eq 0 ] \
	&& { str=${msg_tower_prepare//REMOTE/${remote}}; log "${str//TIME/$(elapsed $SECONDS)}"; } \
	&& { res=`${cmd_ln} 2>&1` || status=1; log "${res}"; } && [ ${status} -eq 0 ] \
	&& { res=`${cmd_id} 2>&1` || status=1; log "$(fd_sanitize ${res})"; } && [ ${status} -eq 0 ] \
	&& { str=${msg_tower_delay//SLOTS/${slots}}; log "${str//TIME/${delay}s}"; sleep ${delay}; } \
	&& { SECONDS=0; res=`${cmd_tx} 2>&1` || status=1; log "${res}"; } && [ ${status} -eq 0 ] \
	&& { str=${msg_tower_release//REMOTE/${remote}}; log "${str//TIME/$(elapsed $SECONDS)}"; } \
	&& { SECONDS=0; res=`${cmd_rx} 2>&1` || status=1; log "${res} by ${bindip} in $(elapsed $SECONDS)"; }
	local elapsed=$(($(date +%s)-$started))
	local err=$(fd_sanitize $(echo "${res}" | grep -E -i 'err|failed'))
	log "${msg_log_stop//TIME/$(elapsed $elapsed)}" && [ ${status} -eq 0 ] && ok || error ${err}
}

rxtower(){
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	# ssh_host is not required to start voting
	[ -n "${auth_voter}" ] || error ${err_auth_voter}
	[ -s "${auth_voter}" ] || error ${err_file_read//FILE/${auth_voter}}
	[ -s "${staked}" ]     || error ${err_file_read//FILE/${staked}}
	
	# make up commands
	local pub=`${keygen} pubkey ${staked}`
	local f=${tower}/tower-{,1_9-}${pub}.bin
	local cmd_rm="${cmd_exec} rm -fv ${f}"
	# firedancer
	if fd_enabled && [ -f "${fdctl}" ]; then
		local cmd_id="${cmd_fd//CMD/set-identity ${staked}}"
		[ "${force}" == 1 ] && cmd_id+=' --force'
	else
		local cmd_id="${cmd_exec} ${validator} -l ${ledger} set-identity --require-tower ${staked}"
	fi
	[ "${staked%/*}" == "${keypair%/*}" ] && local staked=${staked##*/} # make it relative
	local cmd_ln="${sudo} ln -sfv ${staked} ${keypair}"
	if is_dryrun; then
		cmd_ln="echo '${staked}' -> '${keypair}'"
		local tip=" ${tip_dryrun}"
	fi
	
	# do some error checking first
	if [ ! -s "${f}" ]; then
		local str=${err_tower_missing//FILE/${f}}
		[ "${force}" == 1 ] && warn ${str} ${tip_forced} || error ${str} ${tip_force}
		cmd_id=${cmd_id//--require-tower/} # lift the requirement
	else
		local mtime=`${cmd_mtime} ${f}`
		local mdiff=$(($(date +%s)-$mtime))
		if (( $mdiff > $tower_ttl )); then
			local str=${err_tower_outdated//TIME/$(elapsed $mdiff)}
			[ "${force}" == 1 ] && warn ${str} ${tip_forced} || error ${str} ${tip_force}
			cmd_id=${cmd_id//--require-tower/} # lift the requirement
			# since an outdated tower file could cause a fatal error, delete it
			# until the tower auto-discard PR is merged into the master branch
			# [deletion is now handled within the transition below]
		else
			local str=${msg_tower_ok//TIME/$(elapsed $mdiff)}
			cmd_rm="echo ${str//TTL/${tower_ttl}}"
		fi
	fi
	
	# FS trim must be disabled for the validator to catch-up faster
	# if restarted on the occasion of the failed identity transition
	${sudo} touch ${trimmed}
	
	# run the transition
	# set-identity is called after ln because it could fail on occasion
	# and trigger the validator to be restarted with the unstaked identity
	local res status=0
	log "${msg_log_start//CLIENT/${client}}${tip}" && SECONDS=0 \
	&& { res=`${cmd_rm} 2>&1` || status=1; log "${res}"; } && [ ${status} -eq 0 ] \
	&& { res=`${cmd_ln} 2>&1` || status=1; log "${res}"; } && [ ${status} -eq 0 ] \
	&& { res=`${cmd_id} 2>&1` || status=1; log "$(fd_sanitize ${res})"; }
	local err=$(fd_sanitize $(echo "${res}" | grep -E -i 'err|failed'))
	log "${msg_log_stop//TIME/$(elapsed $SECONDS)}" && [ ${status} -eq 0 ] && ok || error ${err}
}

vote_off(){
	# A simplified version of txtower() without tower file manipulation
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	# ssh_host is not required to stop voting
	[ -n "${auth_voter}" ] || error ${err_auth_voter}
	[ -s "${auth_voter}" ] || error ${err_file_read//FILE/${auth_voter}}
	[ -s "${unstaked}" ]   || error ${err_file_read//FILE/${unstaked}}
	
	# make up commands
	# firedancer
	if fd_enabled && [ -f "${fdctl}" ]; then
		local cmd_id="${cmd_fd//CMD/set-identity ${unstaked}}"
		[ "${force}" == 1 ] && cmd_id+=' --force'
	else
		local cmd_id="${cmd_exec} ${validator} -l ${ledger} set-identity ${unstaked}"
	fi
	[ "${unstaked%/*}" == "${keypair%/*}" ] && local unstaked=${unstaked##*/} # make it relative
	local cmd_ln="${sudo} ln -sfv ${unstaked} ${keypair}"
	if is_dryrun; then
		cmd_ln="echo '${unstaked}' -> '${keypair}'"
		local tip=" ${tip_dryrun}"
	fi
	
	# FS trim must be disabled for the validator to catch-up faster
	# if restarted on the occasion of the failed identity transition
	${sudo} touch ${trimmed}
	
	# run the transition
	# set-identity is called after ln because it could fail on occasion
	# and trigger the validator to be restarted with the staked identity
	local res status=0
	log "${msg_log_start//CLIENT/${client}}${tip}" && SECONDS=0 \
	&& { res=`${cmd_ln} 2>&1` || status=1; log "${res}"; } && [ ${status} -eq 0 ] \
	&& { res=`${cmd_id} 2>&1` || status=1; log "$(fd_sanitize ${res})"; }
	local err=$(fd_sanitize $(echo "${res}" | grep -E -i 'err|failed'))
	log "${msg_log_stop//TIME/$(elapsed $SECONDS)}" && [ ${status} -eq 0 ] && ok || error ${err}
}

vote_on(){
	force=1 # make the tower file optional
	wait4e $1 && rxtower
}

watchdog(){
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	LOG=y; rotate $LOGFILE
	# Possible scenarios of what can cause a failover to be triggered:
	#
	# 1a - on demand, by locally executing txtower() on the co-hosted
	# staked validator (planned transition) - it's NOT monitored here;
	#
	# 2. SELF-DETECTED
	# 2a - on reboot of the co-hosted staked validator, as well as
	# 2b - on unattended restart of the co-hosted staked validator, by
	# switching from the staked to the unstaked identity before running
	# the validator (if the binding is set in the config to allow hot
	# swapping, otherwise no auto-switching should take place) - this
	# is invoked by main::validator;
	#
	# 2c - on network outage detected by the co-hosted staked validator,
	# by locally executing vote_off() to stop voting;
	#
	# 2d - on RPC failure of the co-hosted staked validator, as well as
	# 2e - on delinquency of the co-hosted staked validator, by locally
	# executing txtower(-n) to transfer the tower file and stop voting;
	#
	# 2f - on the absence of the remote unstaked validator (no action,
	# a blocker for other actions, monitoring purposes only);
	#
	# 2a, 2b and 2c should accompany the remote unstaked validator to
	# safely detect the delinquency of the staked validator and start
	# voting by force-executing rxtower(-f) (remotely-detected by 3e):
	#
	# 3. REMOTELY-DETECTED
	# 3e - on delinquency of the remote staked validator, by locally
	# force-executing rxtower(-f) on the co-hosted unstaked validator
	# after 2e timeout exceeded an extra threshold.
	#
	# To summarize the above, we will only handle 2a-e & 3e scenarios
	# to fail over.
	
	# do some error checking first
	[ -n "${auth_voter}" ] || error ${err_auth_voter}
	[ -s "${auth_voter}" ] || error ${err_file_read//FILE/${auth_voter}}
	[ -s "${staked}" ]     || error ${err_file_read//FILE/${staked}}
	[ -s "${unstaked}" ]   || error ${err_file_read//FILE/${unstaked}}
	
	# set SMS settings
	# return 1 if the configured version of the CLI is not installed
	SENDER=$(mkalias $(${keygen} pubkey ${unstaked}))
	
	# get the latest failover state
	local stamp stake event times ready
	init_wd(){ stamp=; stake=; event=; times=0; ready=N; }
	save_wd(){ echo "${stamp}:${stake}:${event}:${times}:${1:-${ready}}" | ${sudo} tee ${wd_data} >/dev/null; }
	
	init_wd
	# read_wd() is below
	if [ -f "${wd_data}" ]; then
		local str=$(<${wd_data})
		IFS=':'; local arr=(${str}); unset IFS
		if [ ${#arr[@]} -eq 5 ]; then
			stamp=${arr[0]} # last seen unix timestamp
			stake=${arr[1]} # staked/unstaked
			event=${arr[2]} # bindip/delinq/norpc/offline/reboot/restart
			times=${arr[3]} # number of consecutive failures
			ready=${arr[4]} # Y=yes/N=no/R=readycheck/D=disabled
			# to better understand the meaning of $ready, imagine we have
			# a traffic light with Red=No, Yellow=Get-ready and Green=Yes
		fi
	fi
	
	# process the subcommand
	unset LOG
	case "$1" in
	off)
		# init_wd is disabled to preserve the last event
		save_wd 'D'
		ok ${msg_wd_disabled}
		return 0;;
	on)
		[ -f "${wd_boot}" ] && ${sudo} rm -f ${wd_boot}
		init_wd
		save_wd 'N'
		ok ${msg_wd_enabled}
		return 0;;
	status)
		case ${ready} in
		D) info ${msg_wd_disabled};;
		R) info ${msg_wd_disabled_recheck};;
		*) info ${msg_wd_enabled};;
		esac
		return 0;;
	*)
		[ -n "$1" ] && error ${err_arg};;
	esac
	LOG=y
	
	# Part 0: Who let the [watch]dogs out?
	# determine if we're running the staked validator to play out the
	# self-detected scenarios for a co-hosted validator, otherwise the
	# remotely-detected scenarios will be played out by the remote one
	local data=("staked=$(is_staked && echo 'Y' || echo 'N')")
	
	# Part 1: collect diagnostic data (for scenarios other than 2a,2b)
	if [ ! -f "${wd_boot}" ]; then
		if is_main; then
			# determine if we're ok by querying the getHealth RPC method
			local rpc=N
			local res=$(json_rpc 'localhost' 'getHealth')
			if [ "${res}" == 'ok' ]; then
				rpc=Y
			elif [[ "${res}" == *'code'* ]]; then # error
				local num=`echo ${res} | jq -r .data.numSlotsBehind`
				[ "${num:-0}" -gt 0 ] && rpc=${num}
			fi
			data+=("rpc=${rpc}")
			
			# determine if we're online (not having any network outage)
			local wanip; wanip=$(get_wanip) || warn ${err_wanip}
			[ -z "${wanip}" ] && wanip=N
			data+=("wan=${wanip}")
			
			# determine if the remote unstaked validator is healthy
			if is_staked && [ -n "${ssh_host}" ]; then
				unset LOG
				local bindip=N
				local res=$(json_rpc ${ssh_host} 'getHealth')
				if [ "${res}" == 'ok' ]; then
					bindip=${ssh_host}
				elif [[ "${res}" == *'code'* ]]; then # error
					local num=`echo ${res} | jq -r .data.numSlotsBehind`
					[ "${num:-0}" -gt 0 ] && bindip=${num}
				fi
				data+=("bind=${bindip}")
				LOG=y
			fi
			
			# get validators either from the cached JSON or via an RPC call
			# to an external RPC server - localhost can get false positives
			if ! json_read 'validators' ${rpc_url} 30; then
				warn ${err_json_read//FILE/$FILE}
			else
				local res; res=$(get_pkg jq) || warn ${res} # isolated
				local pub=`${keygen} pubkey ${staked}`
				local json_data=`cat ${validators} | jq '.validators[] | select(.identityPubkey == "'${pub}'")'`
				local last_vote=`echo "${json_data}" | jq -r .lastVote`
				local delinquent=`echo "${json_data}" | jq -r .delinquent`
				[ "${delinquent}" == true ] && delinquent=Y
				[ "${delinquent}" == false ] && delinquent=N
				data+=("delinq=${delinquent}")
				data+=("vote=${last_vote}")
			fi
		elif [ "${ready}" != D ]; then # invoked by main::validator on restart
			local restart=Y
			if [ -f "${wd_start}" ]; then
				# 20240512: fixed an unattended restart bug (any -> attended-only)
				# Only an attended restart should prevent watchdog from failing over.
				# When attended the server for administration, any automated failover
				# action taken in parallel by the watchdog could lead to a failure.
				SMS=y; info ${msg_wd_disabled_restart}; unset SMS
				times=0 # fixed a bug with a false positive on all-clear
				ready=N
				${sudo} rm -f ${wd_start} # delete until the next start
			fi
		fi
	fi # [ ! -f "${wd_boot}" ]
	
	# display diagnostic data
	data+=("ready=${ready}")
	is_dryrun && data+=('dryrun=Y')
	info $(implode , "${data[@]}") "($(elapsed $SECONDS))"
	
	cleanup(){
		[ -s "${cleanup}" ] || return 0
		SECONDS=0
		sudo rm -rf $(<${cleanup})
		log "${msg_log_stop//TIME/$(elapsed $SECONDS)}"
	}
	
	# Part 2: do a ready check (isolated from failing over)
	# Check if watchdog is enabled/ready to take any failover action.
	# Do nothing with the not-yet-caught-up validator, as it could have
	# been the result of any incomplete failover action taken either by
	# the co-hosted or the remote validator. Disable upon a successful
	# failover and then wait for rpc=Y & delinquent=N to enable again.
	is_offline(){ [ "${wanip}" == N -a -z "${delinquent}" ]; }
	if [ ! -f "${wd_boot}" -a -z "${restart}" ]; then
		if [ "${ready}" != Y ]; then
			SMS=1 # send once
			if is_offline; then
				info ${msg_no_network}
			elif [ "${rpc}" == N ]; then
				info ${msg_no_rpc}
			elif is_num ${rpc}; then
				local str=${err_rpc_behind//PUBKEY/$SENDER}
				info ${str//SLOTS/${rpc}}
			elif [ "${delinquent}" == Y ]; then
				info ${msg_delinquent}
			else
				case ${ready} in
				D) # disabled
					info ${msg_wd_disabled};;
				R) # readycheck
					unset SMS; info ${msg_wd_enabled_recheck}
					ready=Y;;
				N) # not ready: `wd_data` init, or attended restart
					info ${msg_wd_enabled}
					ready=Y;;
				esac
				cleanup
			fi
			unset SMS # keep quiet
		fi
	fi
	
	# check if SMS should be sent
	if [ "${ready}" == Y ]; then
		SMS=y
		# check if heartbeat should be sent
		if [ -f "${wd_ping}" ]; then
			${sudo} rm -f ${wd_ping}
			if [ -n "${stamp}" ]; then
				local mtime=${stamp} # last seen
				local mdiff=$(($(date +%s)-$mtime))
				local elapsed=$(elapsed $mdiff)
			else
				local elapsed=${msg_wd_never}
			fi
			# TODO: send a detailed report (state+data)
			unset LOG; info ${msg_wd_ready//TIME/${elapsed}}; LOG=y
		fi
	elif [ "${ready}" != D -a -f "${wd_boot}" ]; then
		ready=Y; SMS=y # get ready for the reboot
	fi
	
	# NOTE: shouldn't we automatically switch back from the remote
	# now staked validator to the local unstaked (current one) for
	# any reason, other than that the now staked validator triggers
	# a failover (back_force_limit)? In the current design, none of
	# the validators can determine its superior status.
	
	# Part 3: run the failover action based on the collected data
	local res failed=N status=0
	
	# event codes
	local E_BINDIP=bindip
	local E_DELINQ=delinq
	local E_NO_RPC=norpc
	local E_OFFLINE=offline
	local E_REBOOT=reboot
	local E_RESTART=restart
	set_event(){
		local event_=$1
		local stake_=$(is_staked && echo 'staked' || echo 'unstaked')
		if [ "${stake}" != "${stake_}" ] || [ "${event}" != "${event_}" ]; then
			# either `stake` or `event` changed, so reset the `times` counter
			stake=${stake_}
			event=${event_}
			times=0
		fi
		times=$(($times+1))
		failed=Y
	}
	
	is_ok(){ [ ${status} -eq 0 ]; }
	if [ "${ready}" == Y ] && is_staked; then
		# SELF-DETECTED (2a-f)
		tip_seen=${tip_seen//LIMIT/${failures}}
		# 2a: reboot (while staked)
		if [ -f "${wd_boot}" ]; then
			set_event $E_REBOOT
			warn ${err_rebooted}
			if [ -n "${ssh_host}" ]; then
				res=$(vote_off) || status=1 # allowed to fail
				echo "${res}"
				is_ok && ok ${msg_vote_off} || warn ${msg_vote_off} ${tip_errors}
			else
				log "${err_bind}"
			fi
			${sudo} rm -f ${wd_boot}
		# 2b: restart (unattended)
		elif [ "${restart}" == Y ]; then
			set_event $E_RESTART
			warn ${err_restarted}
			if [ -n "${ssh_host}" ]; then
				res=$(vote_off) || status=1 # allowed to fail
				echo "${res}"
				is_ok && ok ${msg_vote_off} || warn ${msg_vote_off} ${tip_errors}
			else
				log "${err_bind}"
			fi
		# 2c: network outage
		elif is_offline; then
			unset SMS # no SMS can be sent while offline
			set_event $E_OFFLINE
			warn ${err_network} ${tip_seen//TIMES/$times}
			if [ "${times}" -ge "${failures}" ]; then
				if [ -n "${ssh_host}" ]; then
					res=$(vote_off) || status=1 # may but shouldn't fail
					echo "${res}"
					is_ok && ok ${msg_vote_off} || warn ${msg_vote_off} ${tip_errors}
				else
					log "${err_bind}"
				fi
			fi
		# 2d-1: RPC failure (N)
		# rpc=Y/N   - up/down
		# rpc=[0-9] - behind (delinquent), handled below by 2e: delinquency
		elif false && [ "${rpc}" == N ]; then
			set_event $E_NO_RPC
			[ "${times}" -gt "${failures}" ] && unset SMS # don't spam
			warn ${err_rpc} ${tip_seen//TIMES/$times}
			if [ "${times}" -ge "${failures}" ]; then
				if [ -n "${ssh_host}" ]; then
					SMS=y
					now=1 # no slots can be processed while the RPC is down
					res=$(txtower ${bindip}) || status=1 # no failures accepted
					echo "${res}"
					is_ok && ok ${msg_tower_tx} || warn ${msg_tower_tx} ${tip_errors}
				else
					log "${err_bind}"
				fi
			fi
			SMS=y
		# 2d-2: RPC failure (N+num)
		# rpc=Y/N   - up/down
		# rpc=[0-9] - behind (delinquent), handled herein
		elif true && [ "${rpc}" != Y ]; then
			set_event $E_NO_RPC
			if is_num ${rpc}; then
				local str=${err_rpc_behind//PUBKEY/$SENDER}
				warn ${str//SLOTS/${rpc}} ${tip_seen//TIMES/$times}
			else
				[ "${times}" -gt "${failures}" ] && unset SMS # don't spam
				warn ${err_rpc} ${tip_seen//TIMES/$times}
			fi
			if [ "${times}" -ge "${failures}" ]; then
				if [ -n "${ssh_host}" ]; then
					SMS=y
					now=1 # no slots can be processed while the RPC is down
					res=$(txtower ${bindip}) || status=1 # no failures accepted
					echo "${res}"
					is_ok && ok ${msg_tower_tx} || warn ${msg_tower_tx} ${tip_errors}
				else
					log "${err_bind}"
				fi
			fi
			SMS=y
		# 2e: delinquency (we should never drop in here if 2d-2 is On)
		elif [ "${delinquent}" == Y ]; then
			set_event $E_DELINQ
			[ "${times}" -gt "${failures}" ] && unset SMS # don't spam
			warn ${err_delinquent} ${tip_seen//TIMES/$times}
			if [ "${times}" -ge "${failures}" ]; then
				if [ -n "${ssh_host}" ]; then
					SMS=y
					now=1 # no slots can be processed while delinquent
					res=$(txtower ${bindip}) || status=1 # no failures accepted
					echo "${res}"
					is_ok && ok ${msg_tower_tx} || warn ${msg_tower_tx} ${tip_errors}
				else
					log "${err_bind}"
				fi
			fi
			SMS=y
		# 2f: no bind IP (monitoring only)
		elif [ "${bindip}" == N ] || is_num ${bindip}; then
			# `ssh_host` is configured
			set_event $E_BINDIP
			local alias=$(mkalias ${ssh_bind})
			# reporting `behind` here is disabled, since it's now reported
			# by the unstaked node itself while caching up with the cluster
			if false && is_num ${bindip}; then
				local str=${err_rpc_behind//PUBKEY/${alias}}
				warn ${str//SLOTS/${bindip}}
			elif [ "${times}" == 1 ]; then # once per event
				warn ${err_rpc_health//PUBKEY/${alias}}
			fi
		fi
	elif [ "${ready}" == Y ]; then
		# REMOTELY-DETECTED (3a-e)
		failures=$(($failures+$failures_offset)) # be late by `failures_offset`
		tip_seen=${tip_seen//LIMIT/${failures}}
		# 3a: reboot (do nothing)
		if [ -f "${wd_boot}" ]; then
			set_event $E_REBOOT
			info ${msg_rebooted}
			${sudo} rm -f ${wd_boot}
		# 3b: restart (do nothing)
		# 3c: network outage (do nothing)
		elif is_offline; then
			unset SMS # no SMS can be sent while offline
			set_event $E_OFFLINE
			if [ "${times}" == 1 ]; then # once per event
				warn ${err_network}
			fi
		# 3d: RPC failure (do nothing)
		elif [ "${rpc}" != Y ]; then
			set_event $E_NO_RPC
			if is_num ${rpc}; then
				local str=${err_rpc_behind//PUBKEY/$SENDER}
				warn ${str//SLOTS/${rpc}}
			elif [ "${times}" == 1 ]; then # once per event
				warn ${err_rpc}
			fi
		# 3e: delinquency
		elif [ "${delinquent}" == Y ]; then
			set_event $E_DELINQ
			[ "${times}" -gt "${failures}" ] && unset SMS # don't spam
			warn ${err_delinquent} ${tip_seen//TIMES/$times}
			if [ "${times}" -ge "${failures}" ]; then
				SMS=y
				res=$(vote_on) || status=1 # may but shouldn't fail
				echo "${res}"
				is_ok && ok ${msg_vote_on} || warn ${msg_vote_on} ${tip_errors}
			fi
			SMS=y
		fi
	fi
	
	# save the failover state
	if [ "${failed}" == Y -a "${times}" -eq 1 ]; then stamp=`date +%s`; fi
	if [ "${failed}" == N -a "${times}" -gt 0 ]; then
		# OK now, but FAILED the last time it was run
		
		local str=${msg_all_clear}
		
		# we can also track network status changes by touching a file
		# on going offline for the 1st time, and deleting it when we're
		# back online again with a subsequent notification sent by SMS
		[ "${event}" == $E_OFFLINE ] && str=${msg_network}
		
		local ctime=${stamp} # last seen
		local cdiff=$(($(date +%s)-$ctime))
		ok ${str//TIME/$(elapsed $cdiff)}
		
		times=0 # all clear
		ready=R # do a ready check
		unset SMS; info ${msg_wd_disabled_recheck}; SMS=y
	fi
	save_wd
	
	unset LOG SMS
}

# functions: validator
cpu_tuner(){
	is_linux || { warn ${err_unsupported_os}; return; }
	is_virt && { warn ${msg_vm_true}; return; }
	
	# verify the governor (supplied by an argument)
	local governors=$(</sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors)
	local gov=$1
	if [ -z "${gov}" ]; then
		gov=$(get_gov)
		warn ${msg_cpu_gov_missing//GOV/${gov}}
	fi
	if [ -n "${governors##*${gov}*}" ]; then
		gov=${cpu_gov_default}
		warn ${msg_cpu_gov_invalid//GOV/${gov}}
	elif [ $# -gt 0 ]; then
		info ${msg_cpu_gov_ok//GOV/${gov}}
	fi
	
	# get the CPU defaults
	local min_freq=$(</sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq)
	local max_freq=$(</sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq)
	local min=`echo "scale=1; $min_freq / 1000000" | bc`"GHz"
	local max=`echo "scale=1; $max_freq / 1000000" | bc`"GHz"
	local str=${msg_cpu_notice//MIN/${min}}
	info ${str//MAX/${max}}
	
	# set the CPU frequency scaling
	get_pkg bc linux-tools-common linux-tools-`uname -r`
	[ "${cpu_min_to_max}" == 1 ] && min=${max}
	[ "${cpu_ignore_max}" == 1 ] && max=
	str=${msg_cpu_set//GOV/${gov}}; str=${str//MIN/${min:-none}}
	info ${str//MAX/${max:-none}}
	local status=0
	local cmd=${cmd_cpufreq//GOV/${gov}}
	[ -n "${min}" ] && cmd+=" --min ${min}"
	[ -n "${max}" ] && cmd+=" --max ${max}"
	for ((i=0;i<$(nproc);i++)); do
		local cmd_core=${cmd//CORE/${i}}
		${cmd_core} || { status=1; warn ${err_cpu_set//CMD/${cmd_core}}; }
	done
	
	[ ${status} -eq 0 ] && ok ${msg_cpu_tuned} || warn ${msg_cpu_tuned} ${tip_errors}
}

sys_tuner(){
	is_linux || { warn ${err_unsupported_os}; return; }
	
	# Optimize sysctl knobs
	sudo bash -c "cat >/etc/sysctl.d/21-solana-validator.conf <<EOF
# Increase UDP buffer sizes
net.core.rmem_default = ${udp_buffer}
net.core.rmem_max = ${udp_buffer}
net.core.wmem_default = ${udp_buffer}
net.core.wmem_max = ${udp_buffer}

# Increase memory mapped files limit
vm.max_map_count = ${max_files}

# Increase number of allowed open file descriptors
fs.nr_open = ${max_files}

# Adjust the swap settings
vm.swappiness = ${swappiness}
vm.vfs_cache_pressure = ${cache_pressure}
EOF"
	sudo sysctl -p /etc/sysctl.d/21-solana-validator.conf
	
	# Increase systemd and session file limits
	
	# Add LimitNOFILE=${max_files}
	# to the [Service] section of your systemd service file, if you use one, otherwise add
	# DefaultLimitNOFILE=${max_files}
	# to the [Manager] section of /etc/systemd/system.conf, then
	# sudo systemctl daemon-reload
	
	sudo bash -c "cat >/etc/security/limits.d/90-solana-nofiles.conf <<EOF
# Increase process file descriptor count limit
* - nofile ${max_files}
EOF"
	
	# set the maximum number of open file descriptors for the shell
	ulimit -n ${max_files}
	
	ok ${msg_sys_tuned}
}

validator(){
	is_linux || { warn ${err_unsupported_os}; return; }
	
	if [ "$1" == 'status' ]; then
		${cmd_status}
		return 0
	fi
	
	add_account_index(){ in_array $1 "${args[@]}" || args+=("--account-index $1"); }
	add_account_index_key(){ in_array $1 "${args[@]}" || args+=("--account-index-include-key $1"); }
	cleanup(){
		[ -z "$1" ] && return 0
		local d=`echo "$1" | cut -d/ -f 1-3` # /path/to
		if [ -d "$1" ] && [[ "${d}" == *'ramdisk'* ]]; then
			sudo rm -rf $1/*
			log "${msg_log_stop//TIME/$(elapsed $SECONDS)}"
		fi
	}
	
	# remount dirs if VM detected
	if is_virt; then
		info ${msg_vm_mount}
		local d
		for d in "${dirs[@]}"; do remount "${!d}"; done
	else
		info ${msg_vm_false}
	fi
	
	# ensure the log dir exists
	mklog ${log}
	
	# clean up cache on ramdisk
	cleanup ${accounts_hash}
	
	# play 2a,2b failover scenarios
	local lock=${tool%/*}/watchdog.pid
	pid_lock ${lock} ${lock_timeout} && watchdog # this unsets LOG
	
	# tune system performance
	sys_tuner
	[ "${cpu_gov}" != 'disabled' ] && cpu_tuner ${cpu_gov}
	
	# the restart window must have already been passed, so turn it off
	# for trim and relayer functions called from inside this function
	now=1 && trim # trim all mounted FS to catch up faster
	
	# jito-relayer
	# check if relayer is enabled and required by the systemd unit file
	if [ -f "${relayer}" ] && relayer_required; then
		# do not restart if running already, as it can cause connection
		# issues with currenlty connected remote validators
		${cmd_relayer_status} &>/dev/null && local status=1
		[ "${status}" != 1 ] && restart_relayer
	fi
	
	# add args from the CLI: flags, options, jito stuff
	local args=()
	
	# flags [01], options
	[ -n "${only_known_rpc}" ]   && args+=("--only-known-rpc")
	[ -n "${private_rpc}" ]      && args+=("--private-rpc")
	[ -n "${no_genesis_fetch}" ] && args+=("--no-genesis-fetch")
	if [ -n "${no_snapshots}" ]; then
		args+=("--no-snapshots")
		unset no_snapshot_fetch
		
		# fixed a bug: if snapshots are disabled, accounts directory
		# with a snapshot leftover blows up over time, so delete the
		# snapshot leftover for the accounts to get cleaned properly
		local d=${accounts}/snapshot
		if [ -n "$(ls -A ${d})" ]; then
			echo "${d}/* ${snapshots}/snapshots/*" | ${sudo} tee ${cleanup} >/dev/null
		fi
	else # snapshots enabled
		[ -n "${no_incremental_snapshots}" ] && args+=("--no-incremental-snapshots")
		if [ "${snapshot_interval_slots}" -gt 0 ]; then
			args+=("--snapshot-interval-slots ${snapshot_interval_slots}")
			if [ -z "${no_incremental_snapshots}" ]; then
				if [ "${full_snapshot_interval_slots}" -gt 0 ]; then
					args+=("--full-snapshot-interval-slots ${full_snapshot_interval_slots}")
				fi
			fi
		fi
		
		# accounts_db_hash_threads: 1 if snapshots disabled, 2-6 otherwise
		if [ "${accounts_db_hash_threads:-0}" -lt 2 ]; then
			unset accounts_db_hash_threads
		fi
	fi
	if [ "${accounts_db_hash_threads:-0}" -gt 0 ]; then
		args+=("--accounts-db-hash-threads ${accounts_db_hash_threads}")
	fi
	if [ -n "${no_snapshot_fetch}" ]; then
		# check if the most recent snapshot is provided and it's not
		# older than --maximum-local-snapshot-age before setting the
		# --no-snapshot-fetch flag, otherwise it won't start
		local flag='--no-snapshot-fetch'
		local str=${msg_flag_ignored} res
		if res=$(check_snapshot); then
			args+=(${flag})
			str=${msg_flag_allowed}
		fi
		log "${res}, ${str//FLAG/${flag}}"
	fi
	
	# jito stuff
	if jito_enabled; then
		[ -n "${commission_bps}" ]         && args+=("--commission-bps ${commission_bps}")
		[ -n "${block_engine_url}" ]       && args+=("--block-engine-url ${block_engine_url}")
		[ -n "${relayer_url}" ]            && args+=("--relayer-url ${relayer_url}")
		[ -n "${shred_receiver_address}" ] && args+=("--shred-receiver-address ${shred_receiver_address}")
	fi
	# jito-relayer
	# check if relayer is enabled and required by the systemd unit file
	if [ -f "${relayer}" ] && relayer_required; then
		add_account_index 'program-id'
		add_account_index_key 'AddressLookupTab1e1111111111111111111111111'
		[ -n "${trust_relayer_packets}" ] && args+=("--trust-relayer-packets")
	fi
	
	# fixed a bug: The validator's identity pubkey cannot be a --known-validator
	local pub=`${keygen} pubkey ${staked}` v
	for v in "${known_id[@]}"; do
		[ "${v}" != "${pub}" ] && args+=("--known-validator ${v}")
	done
	
	# run the validator
	log "${msg_log_start//CLIENT/${client}}" && ok
	pid_unlock ${lock}
	
	# firedancer
	if fd_enabled; then
		if [ -f "${fdctl}" ]; then
			# TODO: make it remount() style
			sudo chown -R $USER: /mnt/*
			
			${cmd_fd//CMD/configure init all}
			log "${msg_pkg_configured//PKG/fdctl}"
			exec ${cmd_fd//CMD/run}
		else
			error ${err_file_read//FILE/${fdctl}}
		fi
	else
		# free up the hugepages if switching from firedancer to agave
		if [ "${free_hugepgs}" == 1 ]; then
			if [ -f "${fdctl}" -a -d "/mnt/.fd" ]; then
				${cmd_fd//CMD/configure fini hugetlbfs}
				log "${msg_hugepages_freed}"
			fi
		fi
		exec ${validator} "$@" $(implode ' ' "${args[@]}")
	fi
}

# main
pid_lock ${PIDFILE//ACTION/${action}} $PIDWAIT
$action "$@"
pid_unlock $PIDFILE
# EOF
