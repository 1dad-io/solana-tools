#!/bin/bash -e
# Copyright (c) 2025 Solfege Limited
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

# ternary operator: cond ? a : b
if_num(){ (( $1 )) && echo "$3" || echo "$5"; }
if_str(){ [[ $1 ]] && echo "$3" || echo "$5"; }
if_fun(){ if $1; then echo "$3"; else echo "$5"; fi; }

# BEGIN reporting
is_num(){ [[ "$1" =~ ^[0-9]*\.?[0-9]+$ ]]; }
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
# END reporting

# BEGIN versioning
ver_re='[0-9]+(\.[0-9]+)*'
suffix='(\-[.a-z0-9]+){0,1}'
is_ver(){ [[ "$1" =~ ^${ver_re}${suffix}$ ]]; }
is_tag(){ local s; [ -z "$2" ] && s=${suffix} || s="(\-${2})[.a-z0-9]*"; [[ "$1" =~ ^v${ver_re}${s}$ ]]; }
tag2ver(){ is_tag "$1" && echo "$1" | sed -E "s/${suffix}//g" | sed 's/[^.0-9]*//g' || echo "$1"; }
cmp_ver(){
	[ $# -eq 2 ] || error ${err_arg_count}
	is_ver "$1"  || error ${err_version} 1
	is_ver "$2"  || error ${err_version} 2
	printf '%s\n%s\n' "$2" "$1" | sort --check=quiet --version-sort
}
# END versioning

# BEGIN vars/types
empty(){ [ -z "$1" -o "$1" == 0 ]; }
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
[ -n "$SSH_CLIENT" ] && client=`echo $SSH_CLIENT | awk '{print $1}'` || client=systemd
dirs=(tower ledger accounts accounts_index accounts_shrink snapshots snapshots_inc)
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
# END vars/types

# BEGIN config
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
	failures_offset=${failures_offset:-1} # to be deprecated
	cooldown=${cooldown:-3}
	
	# airdrop & rebalance
	airdrop_min=${airdrop_min:-1}
	airdrop_max=${airdrop_max:-10}
	
	# doublezero
	dz_enabled=${dz_enabled:-0}
	dz_fees_epoch_offset=${dz_fees_epoch_offset:-1}
	dz_fees_epoch_progress=${dz_fees_epoch_progress:-90}
	
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
	nofile=${nofile:-2000000}
	memlock=${memlock:-2000000}
	udp_buffer=${udp_buffer:-134217728}
	swappiness=${swappiness:-1}
	cache_pressure=${cache_pressure:-50}
	
	# setup [01]
	# TODO: use n/y instead
	setup_sshd=${setup_sshd:-1}
	setup_ufw=${setup_ufw:-1}
	setup_ufw_before=${setup_ufw_before:-1}
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
	dz_fees_csv=${path}/data/fees/EPOCH.csv
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
# END config

# BEGIN options-cli
opt_val(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }
known_id=()
pos_args=()
while test $# -gt 0; do
	case "$1" in
	# flags [01]
	-1|--oneshot)
		oneshot=1
		shift;;
	-c|--cron)
		cron=1
		client=cron
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
	# jito-solana
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
	--bam-url*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		bam_url=${bam_url:-$(opt_val "$1")}
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
	# rakurai
	--rewards-merkle-root-authority*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		rewards_merkle_root_authority=${rewards_merkle_root_authority:-$(opt_val "$1")}
		shift;;
	--rakurai-activation-program-id*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		rakurai_activation_program_id=${rakurai_activation_program_id:-$(opt_val "$1")}
		shift;;
	--reward-distribution-program-id*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		reward_distribution_program_id=${reward_distribution_program_id:-$(opt_val "$1")}
		shift;;
	--banking-packet-delay-ms*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		banking_packet_delay_ms=${banking_packet_delay_ms:-$(opt_val "$1")}
		shift;;
	--target-slot-adjustment-ms*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		target_slot_adjustment_ms=${target_slot_adjustment_ms:-$(opt_val "$1")}
		shift;;
	--client-mode*)
		opt=$1
		if ! grep -q '=' <<< "$1"; then shift; fi
		[ $# -gt 0 -a "$1" != '--' ] || error ${err_arg_missing//OPT/${opt}}
		client_mode=${client_mode:-$(opt_val "$1")}
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
	rakurai-status|\
	jito-reload|relayer|restart-relayer|update-relayer|\
	dz|\
	setup|\
	txtower|rxtower|vote-off|vote-on|watchdog|\
	cpu-tuner|sys-tuner|validator)
		# isolate action from subcommands
		if [ -n "${action}" ]; then
			pos_args+=("$1") 
		else
			[ "$1" == 'export' ] && action=${1}_ || action=${1//-/_}
			[ "$1" == 'wait-for-restart' ] && action=wait4r
			if [[ "txtower" == *${1}* ]]; then
				# we need the watchdog to be idle here
				PIDFILE=${tool%/*}/watchdog.pid
				PIDWAIT=${lock_timeout}
			fi
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
# END options-cli

# BEGIN options-systemd
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
	
	# doublezero
	[ "${dz_keypair}" == "${dz_keypair##*/}" ] && dz_keypair=${keypair%/*}/${dz_keypair}
	
	ledger=$(get_opt 'ledger')
	tower=$(get_opt 'tower' ${ledger})
	accounts=$(get_opt 'accounts' "${ledger}/accounts")
	accounts_index=$(get_opt 'accounts-index-path')
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
# END options-systemd

# BEGIN binaries
set_bin(){
	local d=$HOME/.local/share/solana
	bin=${d}/install/releases/$TAG/bin
	if [ ! -d "${bin}" ]; then
		# fallback to active_release
		bin=${d}/install/active_release/bin
	fi
	solana=${bin}/solana
	keygen=${bin}/solana-keygen
	installer=${bin}/agave-install
	validator=${bin}/agave-validator
	ledger_tool=${bin}/agave-ledger-tool
	# watchtower=${bin}/agave-watchtower
	
	# firedancer
	fdctl=${d}/fd/${TAG_FD:-active_release}/bin/fdctl
	
	# jito-relayer
	relayer=${d}/relayer/${RELAYER_TAG:-active_release}/jito-transaction-relayer
	
	# rakurai
	env_keep=
	if is_tag ${TAG} rakurai; then
		# export the scheduler binary path
		[[ ":$LD_LIBRARY_PATH:" == *":${bin}:"* ]] || export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}${bin}"
		env_keep="LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
	fi
}; set_bin
# END binaries

# BEGIN commands
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
	cmd_wait="${cmd_exec} ${env_keep} ${validator} -l ${ledger} wait-for-restart-window"
	
	# jito-relayer
	cmd_relayer_status="${cmd_exec} systemctl status ${relayerd}"
	cmd_relayer_restart="${cmd_exec} systemctl restart ${relayerd}"
	
	# firedancer
	# fixed a bug: OPTIONS must now be specified after SUBCOMMAND
	cmd_fd="${cmd_exec} ${fdctl} CMD --config ${fd_conf}"
	
	# doublezero
	cmd_dz_restart="${cmd_exec} systemctl restart ${dz_systemd}"
	cmd_dz_status="${cmd_exec} systemctl status ${dz_systemd}"
}; set_cmd
# END commands

# BEGIN one-liners
export_(){ [ -z "$1" ] && error ${err_arg}; local var=$1; echo ${!var}; }
get_gov(){ [ "${cpu_gov}" != 'disabled' ] && echo ${cpu_gov} || echo ${cpu_gov_default}; }
monitor(){ ${cmd_exec} ${env_keep} ${validator} -l ${ledger} monitor; }
on_boot(){ date >${wd_boot} 2>/dev/null; log "$(rm -fv ${oldunit})"; log "$(rm -fv ${tool%/*}/*.pid)"; }
starter(){ if [ -z "${reboot}" ]; then ${cmd_reload} && ${cmd_start} && date >${wd_start} 2>/dev/null; else echo 'no-start'; fi; }
stopper(){ ${cmd_stop}; if [ -s "${oldunit}" ]; then rm -f ${oldunit} && setup_log ${log}; else echo 'no-leftover'; fi; }
symlink(){ [[ ! -L "$2" || "$(readlink -f "$2")" != "$(readlink -f "$1")" ]] && ln -sfnv "$1" "$2"; }
truncate(){ [ -f "$1" ] || return 0; sed -e :a -e "\$q;N;$((${2:-10}+1)),\$D;ba" -i --follow-symlinks $1 2>/dev/null; }
# END one-liners

# BEGIN common
assert_allowed(){
	[ -n "$1" ] || return 0
	local str=$(if_fun is_staked ? staked : unstaked)
	[ "$1" == "${str}" ] || error ${err_not_allowed//COND/$1}
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

curr_epoch(){
	local opt="-u ${1:-${moniker}}"
	local epoch=`${solana} ${opt} epoch --commitment finalized 2>/dev/null` || error ${err_rpc_connect}
	echo ${epoch}
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

is_running(){ is_linux && ${cmd_status} &>/dev/null; }

is_virt(){
	is_linux || { warn ${err_unsupported_os}; return 1; }
	get_pkg virt-what
	local facts; facts=`sudo virt-what`
	local status=$?
	[ ${status} -ne 0 ] && error "${status}"
	# return 0 if VM detected, 1 otherwise
	[ -n "${facts}" ]
}

mkalias(){
	if [ -z "$1" ]; then
		echo 'misconfigured'
		return 1
	fi
	local var="x$1" len=${2:-6}
	[ -n "${!var}" ] && echo ${!var} || echo ${var:1:${len}}
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
# END common

# BEGIN help
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
	echo -e "        ${CG}dz${NC} [SUBCOMMAND]            Run doublezero with any: up/down/pda/fees/fund/init/setup/user"
	echo -e "        ${CG}export${NC} <bin|log|tower>     Export environment variables"
	echo -e "        ${CG}jito-reload${NC}                Hot reload the Jito configuration"
	echo -e "        ${CG}leader-slot${NC} [-1]           Show countdown to the next leader slot"
	echo -e "        ${CG}make-snapshot${NC} <SLOT>       Create a new ledger snapshot for the given slot"
	echo -e "        ${CG}monitor${NC} [--fd]             Monitor the validator"
	echo -e "        ${CG}on-boot${NC}                    Set a reboot flag for the watchdog (run by cron)"
	echo -e "        ${CG}optimistic-slot${NC} [-1]       Show optimistic slot"
	echo -e "        ${CG}rakurai-status${NC}             Show runtime status information about rakurai"
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
# END help

# BEGIN airdrop/rebalance
tx(){
	local recipient=$1
	local from_addr=$2
	local amount=${3:-0}
	local u=$(if_fun is_running ? localhost : "${rpc_url}")
	local opt="-u ${u}" resp
	
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
	
	# confirm the tx if requested via CLI
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
	assert_allowed ${airdrop_allow}
	
	# stop if `airdrop_to` >= `airdrop_max`
	local u=$(if_fun is_running ? localhost : "${rpc_url}")
	local opt="-u ${u}" resp
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
	local u=$(if_fun is_running ? localhost : "${rpc_url}")
	local opt="-u ${u}" resp
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
	local u=$(if_fun is_running ? localhost : "${rpc_url}")
	local opt="-u ${u}" resp
	resp=`${solana} ${opt} balance ${f} 2>&1` || error "${resp}"
	local b_from=`echo "${resp}" | sed 's/[^0-9.]*//g'`
	
	# make a transfer from the temporary keypair
	if [ `echo "${b_from} > 0" | bc` == 1 ]; then
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
	assert_allowed ${balance_allow}
	
	LOG=y
	local u=$(if_fun is_running ? localhost : "${rpc_url}")
	local opt="-u ${u}" resp
	
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
# END airdrop/rebalance

# BEGIN bind
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
	save_conf 'ssh_bind' "${pub}"
	save_conf 'ssh_host' "${bindip}"
	
	ok
}
# END bind

# BEGIN json-rpc
file_fetch(){
	local url=$1
	local out=${2:-$(basename ${url%%\?*})} # strip query when naming
	local ttl=${3:-${cache_ttl}}
	local th_met=0
	
	if [ -f "${out}" -a "${ttl}" != -1 ]; then
		local mtime=`${cmd_mtime} ${out}`
		local mdiff=$(($(date +%s)-$mtime))
		(( $mdiff > $ttl )) && th_met=1
	fi
	
	if [ ! -f "${out}" -o "${th_met}" == 1 ]; then
		local d=${out%/*} tmp=${out}.partial res
		[ "${d}" == "${out}" -o -d "${d}" ] || ${sudo} mkdir -p ${d}
		res=`${sudo} curl --connect-timeout ${rpc_conn_timeout} \
			--continue-at - \
			--fail \
			--location \
			--max-time ${rpc_max_time} \
			--retry-connrefused \
			--retry-delay ${rpc_retry_delay} \
			--retry-max-time ${rpc_retry_max_time} \
			--retry ${rpc_retry} \
			-s --show-error \
			--output "${tmp}" "${url}" 2>&1` || { warn "${res}"; return 1; }
		${sudo} mv -f "${tmp}" "${out}" # file can be empty
	fi
}

json_fetch(){
	local command=${1%% *}
	[[ "${command}" =~ ^[a-z]+(-[a-z]+)*$ ]] || error ${err_arg}
	local opt="-u ${2:-${moniker}}"
	local out=${!command}
	local ttl=${3:-${cache_ttl}}
	local th_met=0
	
	case ${command} in
	block)
		local slot=0
		[[ "$1" =~ [0-9]+ ]] && slot=${BASH_REMATCH[0]} || error ${err_arg}
		out=${out//SLOT/${slot}};;
	stakes)
		local epoch=$(curr_epoch $2)
		is_num ${epoch} || error ${err_arg} # need more specific error here
		out=${out//EPOCH/${epoch}};;
	esac
	
	if [ -f "${out}" -a "${ttl}" != -1 ]; then
		local mtime=`${cmd_mtime} ${out}`
		local mdiff=$(($(date +%s)-$mtime))
		(( $mdiff > $ttl )) && th_met=1
	fi
	
	if [ ! -f "${out}" -o "${th_met}" == 1 ]; then
		local d=${out%/*} tmp=${out}.new
		[ "${d}" == "${out}" -o -d "${d}" ] || ${sudo} mkdir -p ${d}
		set -o pipefail
		if ! ${solana} ${opt} $1 --output=json 2>/dev/null | ${sudo} tee ${tmp} >/dev/null; then
			warn ${err_json_fetch//FILE/${out}}
			return 1
		elif [ -s "${tmp}" ]; then
			${sudo} mv -f "${tmp}" "${out}" # non-empty file
		fi
		set +o pipefail
	fi
}

json_rpc(){
	local res; res=$(get_pkg curl jq) || log "${res}" # isolated
	local host=${1%%:*} port=${1##*:} method=$2
	[ "${host}" == "${port}" ] && port=${rpc_port}
	local data='{"jsonrpc":"2.0","id":1,"method":"METHOD"}'
	local resp=`curl --connect-timeout ${rpc_conn_timeout} \
		--fail \
		--location \
		--max-time ${rpc_max_time} \
		--retry-connrefused \
		--retry-delay ${rpc_retry_delay} \
		--retry-max-time ${rpc_retry_max_time} \
		--retry ${rpc_retry} \
		-s -X POST -H "Content-Type: application/json" -d ${data//METHOD/${method}} http://${host}:${port}`
	if [ -n "${resp}" ]; then
		local res=`echo "${resp}" | jq -r .result`
		local err=`echo "${resp}" | jq -r .error`
		[ "${res}" != null ] && echo "${res}" || { [ "${err}" != null ] && echo "${err}"; }
	else
		error ${err_rpc_connect}
	fi
}
# END json-rpc

# BEGIN menu
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
	
	# check if user exists
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
		
		# get validators either from the cached JSON or via an RPC call
		if json_fetch 'validators' ${rpc_url}; then
			get_pkg jq
			local max_stake=0 max_stake_v=${version} v
			local versions=(`cat ${validators} | jq '.stakeByVersion | to_entries[] | [.key] | @tsv' | grep -v unknown | sed -e 's/"//g' | sort -t. -k 1,1nr -k 2,2nr -k 3,3nr`)
			for v in "${versions[@]}"; do
				local active_stake=`cat ${validators} | jq ".stakeByVersion.\"${v}\".currentActiveStake"`
				if [ "${active_stake}" -gt "${max_stake}" ]; then
					max_stake=${active_stake}
					max_stake_v=${v}
				fi
			done
			for v in "${versions[@]}"; do
				local best='   ' conf=
				[ "${v}" == "${max_stake_v}" ] && best='=> '
				[ "${v}" == "${version}"     ] && conf=' (config)'
				local n_validators=`cat ${validators} | jq ".stakeByVersion.\"${v}\".currentValidators"`
				options+=(${v} "${best}v${v} - ${n_validators}${conf}")
			done
		fi
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
			--default-item "${version:-${max_stake_v}}" \
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
# END menu

# BEGIN logging
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
# END logging

# BEGIN start/stop/restart
wait4e(){
	[ -n "$1" ] || return 0
	
	local u=$(if_fun is_running ? localhost : "${rpc_url}")
	while true; do
		local epoch=$(curr_epoch ${u})
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

ps_cmd(){ echo `ps ax -o args | grep ${1:-.}`; }
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
		local runtime=$(ps_cmd ${validator##*/})
		[[ "${runtime}" =~ --no-(incremental-)?snapshots ]] && cmd+=" --skip-new-snapshot-check"
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
# END start/stop/restart

# BEGIN update
make_tag(){ is_tag "$1" && echo "$1" | sed -E "s/^v${ver_re}${suffix}$/v$2\2/" || echo "v$2"; }
save_tag(){
	# if no TAG is found, the user prefers not to declare a specific TAG,
	# and the active_release symlink will be used to resolve the binaries
	local name=${2:-TAG}
	local f=${tool%/*}/${moniker%%[-]*}/${3:-${systemd}}.service
	sed -i --follow-symlinks "s/\(Environment=${name}=\)[^[:space:]]*/\1$1/" ${f} || error ${err_file_write//FILE/${f}}
}
update(){
	# is_linux || { warn ${err_unsupported_os}; return; }
	
	# ensure the systemd is configured
	[ -z "${systemd}" ] && error ${err_systemd}
	
	# ensure the watchdog is paused
	local lock=${tool%/*}/watchdog.pid
	pid_lock ${lock} ${lock_timeout} # this unsets LOG
	
	# default client: agave
	local oTAG=$TAG
	local branch=master
	local tags=tags
	local git=${git_anza}
	local url=${url_anza}
	local repo=validator
	set_git(){
		if rakurai_enabled; then
			branch=main
			tags=release
			git=${git_rakurai}
			url=
		elif jito_enabled; then
			branch=master
			tags=tags
			git=${git_jito_solana}
			url=${url_jito}
		fi
		[ -n "${git}" ] && repo=$(echo "${git##*/}" | sed 's/\.git//g')
	}; set_git
	
	# TAG may be unset, read from the systemd, or provided via CLI
	if [ -z "${version}" ]; then
		# no `version` CLI argument is provided, display the menu
		local version; version=$(menu_version ${repo}) || return
		TAG=$(make_tag $TAG ${version})
	else
		# `version` is provided to replace `TAG`, so drop it now
		TAG=$(make_tag '' ${version}) && set_git # re-initialize
	fi
	
	# set environment
	TARGET=$HOME/.local/share/solana/install/releases/$TAG
	local parent=${TARGET%/*}
	local active=${parent//releases/active_release}
	info "TAG=$TAG"
	
	# check if it's already installed
	if [ -s "$TARGET/bin/${solana##*/}" ]; then
		local str=${err_pkg_installed//PKG/$TAG}
		if [ "${force}" == 1 ]; then
			warn ${str} ${tip_forced}
		else
			# update the systemd unit file with the new tag
			[ "$TAG" == "$oTAG" ] || save_tag $TAG
			
			# set new active_release
			symlink $TARGET ${active} || info ${err_file_exists//FILE/${active}}
			
			warn ${str} ${tip_force}
			return
		fi
	fi
	
	log "${msg_log_start//CLIENT/${client}}" && SECONDS=0
	if [ -z "${git}" ]; then
		# install binaries
		if [ -f "${installer}" ]; then
			local cmd="${installer} init $TAG"
		else
			[ -n "${url}" ] || ${err_url}
			get_pkg curl
			local res
			res=`curl -sSfL ${url//VERSION/$TAG} 2>&1` || error ${res}
			sh -c "${res}"
		fi
		export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
	else
		# build from source
		REPO=${tool%/*}/${repo}
		
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
		
		if [ ! -d "$REPO/.git" ]; then
			git -C ${tool%/*} clone ${git} --recurse-submodules
			cd $REPO
		else
			cd $REPO
			git fetch --all
			git reset --hard origin/${branch}
			git clean -fd
		fi
		export TAG=$TAG
		git checkout ${tags}/$TAG
		git submodule update --init --recursive
		
		# apply patches
		find_conf(){ find -L $1 -maxdepth 1 -type f -name '*mostly*' ! -name '*~' | sort | head -n 1; }
		PATCH=${tool%/*}/solana-patch
		PATCH_BUILD=0
		git=${git_solana_patch}
		if [ -n "${git}" ]; then
			if [ ! -d "$PATCH/.git" ]; then
				git -C ${tool%/*} clone ${git}
			else
				# find the patch config
				local f=$(find_conf $PATCH)
				
				# update the patch repo
				cd $PATCH
				git fetch origin
				git reset --hard origin/master
				git clean -fd
				cd $REPO
				
				# remove the patch config if it was missing before update
				if [ -z "${f}" ]; then
					f=$(find_conf $PATCH)
					rm -fv ${f}
				fi
			fi
		fi
		local p=$PATCH/$TAG
		if [ -d "${p}" ]; then
			find -L ${p} -type f -name '*.rs' | while read f; do
				local t=$REPO${f//${p}/}
				mkdir -p ${t%/*}
				cp -av ${f} ${t}
			done
		fi
		if [ -f "${p}.sh" ]; then
			info ${msg_patch_found//FILE/${p##*/}.sh}
			source ${p}.sh
			info ${msg_patch_applied}
		fi
		
		if [ "$PATCH_BUILD" != 1 ]; then
			# build & make install
			[ "${setup_cli_full}" == 1 ] || local arg='--validator-only'
			CI_COMMIT=$(git rev-parse HEAD) scripts/cargo-install-all.sh ${arg} $TARGET
		fi
		
		# set new active_release
		symlink $TARGET ${active} || info ${err_file_exists//FILE/${active}}
	fi
	
	# update the systemd unit file with the new tag
	${cmd:-echo no-init} && save_tag $TAG && set_bin && set_cmd && ok
	log "${msg_log_stop//TIME/$(elapsed $SECONDS)}"
	
	# resume the watchdog
	[ -n "${lock}" ] && pid_unlock ${lock}
	
	# restart when called from the CLI while not staked
	! is_staked && is_main && is_running && restart || :
	
	unset PATCH PATCH_BUILD REPO TARGET
}
# END update

# BEGIN firedancer
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
	
	# client: firedancer
	local oTAG=$TAG_FD
	local branch=master
	local git=${git_firedancer}
	[ -n "${git}" ] || error ${err_git_repo}
	local repo=$(echo "${git##*/}" | sed 's/\.git//g')
	
	# TAG may be unset, read from the systemd, or provided via CLI
	if [ -z "${version}" ]; then
		# no `version` CLI argument is provided, display the menu
		local version; version=$(menu_version ${repo}) || return
		TAG_FD=$(make_tag $TAG_FD ${version})
	else
		# `version` is provided to replace `TAG_FD`, so drop it now
		TAG_FD=$(make_tag '' ${version})
	fi
	
	# set environment
	TARGET=$HOME/.local/share/solana/fd/$TAG_FD
	local parent=${TARGET%/*}
	local active=${parent}/active_release # fd has its own active_release
	info "TAG_FD=$TAG_FD"
	
	# check if it's already installed
	if [ -s "$TARGET/bin/${fdctl##*/}" ]; then
		local str=${err_pkg_installed//PKG/$TAG_FD}
		if [ "${force}" == 1 ]; then
			warn ${str} ${tip_forced}
		else
			# update the systemd unit file with the new tag
			[ "$TAG_FD" == "$oTAG" ] || save_tag $TAG_FD 'TAG_FD'
			
			# set new active_release
			symlink $TARGET ${active} || info ${err_file_exists//FILE/${active}}
			
			warn ${str} ${tip_force}
			return
		fi
	fi
	
	log "${msg_log_start//CLIENT/${client}}" && SECONDS=0
	
	# build from source
	REPO=${tool%/*}/${repo}
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
	
	if [ ! -d "$REPO/.git" ]; then
		git -C ${tool%/*} clone ${git} --recurse-submodules
		cd $REPO
	else
		cd $REPO
		git fetch --all
		git reset --hard origin/${branch}
		git clean -fd
		
		# git clean doesn't work as expected, ./build must be cleaned
		rm -rf ./build
	fi
	
	export TAG_FD=$TAG_FD
	git checkout $TAG_FD
	git submodule update # --init --recursive (no args in the docs)
	./deps.sh
	make -j fdctl solana
	
	# make install
	mkdir -p $TARGET
	cp -au $REPO/build/native/gcc/bin $TARGET
	
	# set new active_release
	symlink $TARGET ${active} || info ${err_file_exists//FILE/${active}}
	
	# update the systemd unit file with the new tag
	save_tag $TAG_FD 'TAG_FD' && set_bin && set_cmd && ok
	log "${msg_log_stop//TIME/$(elapsed $SECONDS)}"
	
	# resume the watchdog
	[ -n "${lock}" ] && pid_unlock ${lock}
	
	# restart when called from the CLI while not staked
	! is_staked && is_main && is_running && restart || :
	
	unset REPO TARGET
}

# echo $(fd_sanitize $(<fd.log)); exit
fd_sanitize(){
	if [[ "${*}" == *'fdctl'* ]]; then
		echo ${*} | grep fdctl | cut -d ')' -f 2 | cut -d ':' -f 2 | tr -d \` | awk '{$1=$1};1'
	else
		echo ${*}
	fi
}
# END firedancer

# BEGIN rakurai
rakurai_enabled(){ is_tag $TAG rakurai; }
rakurai_status(){
	rakurai_enabled || error ${msg_pkg_disabled//PKG/rakurai}
	date
	for p in "block time" "Banking packet delay" "rakurai_status"; do
		line=$(grep "$p" ${log} | tail -n1)
		echo "$p: ${line:-not found}"
	done
}
# END rakurai

# BEGIN jito-solana
jito_enabled(){ is_tag $TAG jito || rakurai_enabled; }
jito_reload(){
	jito_enabled || error ${err_version}
	is_running   || error ${err_not_allowed//COND/running}
	set_arg(){ empty "$1" && echo '""' || echo "$1"; }
	[ -n "${block_engine_url}" ]       && ${cmd_exec} ${env_keep} ${validator} -l ${ledger} set-block-engine-config --block-engine-url "$(set_arg ${block_engine_url})"
	[ -n "${shred_receiver_address}" ] && ${cmd_exec} ${env_keep} ${validator} -l ${ledger} set-shred-receiver-address --shred-receiver-address "$(set_arg ${shred_receiver_address})"
	[ -n "${relayer_url}" ]            && ${cmd_exec} ${env_keep} ${validator} -l ${ledger} set-relayer-config --relayer-url "$(set_arg ${relayer_url})"
	[ -n "${bam_url}" ]                && ${cmd_exec} ${env_keep} ${validator} -l ${ledger} set-bam-config --bam-url "$(set_arg ${bam_url})"
	ok ${msg_pkg_configured//PKG/}
}
# END jito-solana

# BEGIN jito-relayer
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
	
	# client: jito-relayer
	local oTAG=$RELAYER_TAG
	local branch=master
	local tags=tags
	local git=${git_jito_relayer}
	[ -n "${git}" ] || error ${err_git_repo}
	local repo=$(echo "${git##*/}" | sed 's/\.git//g')
	
	# TAG may be unset, read from the systemd, or provided via CLI
	if [ -z "${version}" ]; then
		# no `version` CLI argument is provided, display the menu
		local version; version=$(menu_version ${repo}) || return
		RELAYER_TAG=$(make_tag $RELAYER_TAG ${version})
	else
		# `version` is provided to replace `RELAYER_TAG`, so drop it now
		RELAYER_TAG=$(make_tag '' ${version})
	fi
	
	# set environment
	TARGET=$HOME/.local/share/solana/relayer/$RELAYER_TAG
	local parent=${TARGET%/*}
	local active=${parent}/active_release # relayer has its own active_release
	info "RELAYER_TAG=$RELAYER_TAG"
	
	# check if it's already installed
	if [ -s "$TARGET/${relayer##*/}" ]; then
		local str=${err_pkg_installed//PKG/$RELAYER_TAG}
		if [ "${force}" == 1 ]; then
			warn ${str} ${tip_forced}
		else
			# update the systemd unit file with the new tag
			[ "$RELAYER_TAG" == "$oTAG" ] || save_tag $RELAYER_TAG 'TAG' ${relayerd}
			
			# set new active_release
			symlink $TARGET ${active} || info ${err_file_exists//FILE/${active}}
			
			warn ${str} ${tip_force}
			return
		fi
	fi
	
	log "${msg_log_start//CLIENT/${client}}" && SECONDS=0
	
	# build from source
	REPO=${tool%/*}/${repo}
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
	
	if [ ! -d "$REPO/.git" ]; then
		git -C ${tool%/*} clone ${git} --recurse-submodules
		cd $REPO
	else
		cd $REPO
		git fetch --all
		git reset --hard origin/${branch}
		git clean -fd
	fi
	
	export RELAYER_TAG=$RELAYER_TAG
	git checkout ${tags}/$RELAYER_TAG
	git submodule update --init --recursive
	cargo b --release # build
	
	# make install
	mkdir -p $TARGET
	cp -au $REPO/target/release/jito-transaction-relayer $TARGET
	
	# set new active_release
	symlink $TARGET ${active} || info ${err_file_exists//FILE/${active}}
	
	# update the systemd unit file with the new tag
	save_tag $RELAYER_TAG 'TAG' ${relayerd} && set_bin && ok
	log "${msg_log_stop//TIME/$(elapsed $SECONDS)}"
	
	# restart when called from the CLI while not staked
	! is_staked && is_main && relayer_running && restart_relayer || :
	
	unset REPO TARGET
}
# END jito-relayer

# BEGIN doublezero
dz_enabled(){ [ "${dz_enabled}" == 1 ]; }
dz_init(){
	is_staked || error ${err_unstaked}
	
	local opt="-u ${moniker} -k ${staked}"
	local pub=`${keygen} pubkey ${staked}`
	local dz_pub=`${dz} address`
	if [ -n "${ssh_bind}" ]; then
		local arg="--backup-validator-ids ${ssh_bind}"
		local arg2=",backup_ids=${ssh_bind}"
	fi
	
	# attest validator ownership
	${dz_solana} passport find-validator -u ${moniker}
	
	# prepare the connection
	${dz_solana} passport prepare-validator-access -u ${moniker} --doublezero-address ${dz_pub} --primary-validator-id ${pub} ${arg}
	
	# generate signature
	local sig=`${solana} sign-offchain-message service_key=${dz_pub}${arg2} -k ${staked}`
	
	# initiate a connection request
	${dz_solana} passport request-validator-access ${opt} --doublezero-address ${dz_pub} --primary-validator-id ${pub} ${arg} --signature ${sig} \
		&& ok || err
}

pda_fetch(){
	local pub=`${keygen} pubkey ${staked}`
	[ -n "${quiet}" ] && local arg='-b' || local arg=
	${dz_solana} revenue-distribution fetch validator-deposits -u ${moniker} -n ${pub} ${arg}
}

pda_fund(){
	LOG=y
	
	# set SMS settings
	SENDER=$(mkalias $(${keygen} pubkey ${unstaked}))
	
	local opt="-u ${moniker} -k ${staked}"
	local pub=`${keygen} pubkey ${staked}`
	local arg resp str
	if [ `echo "${1:-0} >= 0.000000001" | bc` == 1 ]; then
		arg="--fund ${1}"
		str=${msg_dz_pda_fund_yn//AMOUNT/${1}}
	else
		arg='--initialize'
		str=${msg_dz_pda_init_yn}
	fi
	
	read -p "${str}" REPLY </dev/tty
	if [[ $REPLY =~ ^[Yy](es)?$ ]]; then
		resp=`${dz_solana} revenue-distribution validator-deposit ${opt} -n ${pub} ${arg} 2>&1` || error "${resp}"
		quiet=1; resp=$(pda_fetch) || error "${resp}"
		SMS=y; info "paid=${1:-0},pda=${resp}"; unset SMS
	else
		info ${msg_aborted}
	fi
	
	unset LOG
}

pda_fees(){
	# verify the cluster
	[ "${moniker}" != 'mainnet-beta' ] && error ${err_unsupported_cluster}
	
	# verify `dz_fees_allow`
	assert_allowed ${dz_fees_allow}
	
	LOG=y
	
	# look `dz_fees_epoch_offset` epochs back
	local u=$(if_fun is_running ? localhost : "${rpc_url}")
	local offset=${1:-${dz_fees_epoch_offset}}
	local epoch=$(curr_epoch ${u})
	is_num ${epoch} || error ${err_arg} # need more specific error here
	if [ "${epoch}" -gt "${offset}" ]; then
		epoch=$((${epoch}-${offset}))
	fi
	
	# fetch doublezero fees for `epoch`
	local url=${dz_fees//EPOCH/${epoch}}
	local out=${dz_fees_csv//EPOCH/${epoch}}
	file_fetch ${url} ${out} -1 || return 1
	
	# calc the amount due for payment
	local pub=`${keygen} pubkey ${staked}` pda
	quiet=1; pda=$(pda_fetch) || error "${pda}"
	is_num ${pda} || error ${err_arg_numeric//ARG/pda}
	local lamports=`cat ${out} | grep ${pub} | awk -F, '$3 ~ /^[0-9]+$/ { print $3 }'`
	local fees=`echo "scale=9; ${lamports:-0}/1000000000" | bc | xargs printf '%.9f'`
	local debt=`echo "${fees:-0}-${pda:-0}" | bc | xargs printf '%.9f'`
	local fund=$(if_num $(echo "${debt} > 0" | bc) ? Y : N)
	info "epoch=${epoch},due=${fees},pda=${pda},debt=${debt},fund=${fund}"
	
	# ensure the PDA needs funding
	if [ "${fund}" == N ]; then
		local str=${err_dz_pda_funded}
		[ "${force}" == 1 ] && warn ${str} ${tip_forced} || { warn ${str} ${tip_force}; return; }
	fi
	
	# ensure the PDA is empty
	if [ `echo "${pda} > 0" | bc` == 1 ]; then
		local str=${err_dz_pda_not_empty}
		[ "${force}" == 1 ] && warn ${str} ${tip_forced} || { warn ${str} ${tip_force}; return; }
	fi
	
	# fund the PDA
	local cmd=$(if_str "${cron}" ? yes : ':')
	${cmd} | pda_fund $(if_str "${force}" ? ${fees} : ${debt})
	
	unset LOG
}

dz_setup(){
	# check if it's already installed
	if [ -f "${dz}" ]; then
		local str=${err_pkg_installed//PKG/doublezero}
		[ "${force}" == 1 ] && warn ${str} ${tip_forced} || { warn ${str} ${tip_force}; return; }
	else
		# install doublezero
		curl -1sLf ${url_doublezero} | sudo -E bash
		get_pkg doublezero
	fi
	
	# create the doublezero config directory
	mkdir -p $HOME/.config/doublezero
	
	# ensure the doublezero keypair exists
	local f=${dz_keypair}
	if [ ! -f "${f}" ]; then
		info ${msg_setup_dz_keypair}
		mkdir -p ${f%/*}
		info `${dz} keygen -o ${f}`
		chmod 600 ${f}
	else
		local pub=`${dz} address`
		local str=${msg_setup_keypair//PUBKEY/${pub}}
		info ${str//TYPE/doublezero}
	fi
	
	# make `dz_keypair` a symlink to the doublezero default keypair
	ln -s ${dz_keypair} $HOME/.config/doublezero/id.json 2>/dev/null || :
	
	# configure environment
	local d=/etc/systemd/system/doublezerod.service.d
	sudo mkdir -p ${d}
	echo -e "[Service]\nExecStart=\nExecStart=/usr/bin/doublezerod -sock-file /run/doublezerod/doublezerod.sock -env ${moniker}" | sudo tee ${d}/override.conf >/dev/null
	sudo systemctl daemon-reload && ${cmd_dz_restart}
	${dz} config set --env ${moniker} >/dev/null
	info "${msg_pkg_configured//PKG/${dz_systemd}} for ${moniker}"
	
	ok ${msg_pkg_installed//PKG/doublezero}
}

dz_user_list(){
	local pub=`${dz} address`
	${dz} user list | grep ${pub}
}

dz(){
	is_dryrun || is_linux || error ${err_unsupported_os}
	dz_enabled || error ${msg_pkg_disabled//PKG/doublezero}
	
	# process the subcommand
	case "$1" in
	address|balance|latency|status)
		${dz} "$1";;
	up)
		${sudo} bash -c "${dz_up}";;
	down)
		${sudo} bash -c "${dz_down}";;
	pda)
		pda_fetch;;
	fees)
		pda_fees ${2:-};;
	fund)
		pda_fund ${2:-};;
	init)
		dz_init;;
	setup)
		dz_setup;;
	user)
		dz_user_list;;
	*)
		[ -z "$1" ] && ${dz} status || error ${err_arg};;
	esac
}
# END doublezero

# BEGIN setup
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
		
		# apply custom iptables rules that are processed before the main rules
		local f=/etc/ufw/before.rules
		local src=${f} res
		if [ "${setup_ufw_before}" == 1 ]; then
			if jito_enabled; then
				if relayer_required; then
					src+='.jito-relayer'
				else
					src+='.jito-solana'
				fi
			elif fd_enabled; then
				: # firedancer not compatible with iptables (ufw)
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
		
		# allow solana_ws
		# NOTE: `private_rpc` is a runtime arg and cannot be used here
		yes | sudo ufw delete allow 8900/tcp # delete solana_websocket (transient fix)
		local ws_port=$((${rpc_port:-0}+1))
		local any="allow ${ws_port}/tcp"
		if [ -z "${setup_ufw_ws}" ]; then
			sudo ufw ${any} comment 'solana_ws'
		else
			local ips=(`echo ${setup_ufw_ws} | tr ',' "\n"`) ip
			for ip in "${ips[@]}"; do
				is_ip ${ip} || is_cidr ${ip} || continue
				sudo ufw allow from ${ip} to any port ${ws_port} proto tcp comment 'solana_ws'
			done
			yes | sudo ufw delete ${any}
			yes | sudo ufw delete ${any//allow/limit}
		fi
		
		# allow solana_*
		sudo ufw allow 8000/tcp      comment 'solana_gossip'
		sudo ufw allow 8000:8025/udp comment 'solana_dynamic'
		
		# allow jito-relayer
		# relayer 11226/tcp (grpc_bind_port) to run on a separate host
		# relayer 11228:11229/udp (tpu_quic_port:tpu_quic_forward_port)
		local tpu_quic="allow 11228:11229/udp"
		if relayer_required; then
			sudo ufw ${tpu_quic} comment 'solana_tpu_quic'
		else
			yes | sudo ufw delete ${tpu_quic}
		fi
		
		# allow firedancer
		if fd_enabled; then
			sudo ufw allow 8001/tcp      comment 'solana_fd_gossip'
			sudo ufw allow 8900:9000/udp comment 'solana_fd_dynamic'
		fi
		
		# allow doublezero
		# DoubleZero uses link-local address space: 169.254.0.0/16 for
		# the GRE tunnel between a validator and the DoubleZero Device
		local dz_in="allow in proto tcp from 169.254.0.0/16 to 169.254.0.0/16 port 179"
		local dz_out="allow out proto tcp from 169.254.0.0/16 to 169.254.0.0/16 port 179"
		local dz_lm="allow 44880/udp" # liveness manager
		if dz_enabled; then
			yes | sudo ufw delete deny out from any to 169.254.0.0/16
			sudo ufw ${dz_in}  comment 'solana_dz_in'
			sudo ufw ${dz_out} comment 'solana_dz_out'
			sudo ufw ${dz_lm}  comment 'solana_dz_lm'
		else
			yes | sudo ufw delete ${dz_in}
			yes | sudo ufw delete ${dz_out}
			yes | sudo ufw delete ${dz_lm}
		fi
		
		# block outgoing traffic to private networks
		sudo ufw deny out from any to 10.0.0.0/8     comment 'private'
		sudo ufw deny out from any to 100.64.0.0/10  comment 'private'
		sudo ufw deny out from any to 102.0.0.0/8    comment 'private'
		# blocking 169.254.0.0/16 inside a VM could block DNS resolution
		is_virt || sudo ufw deny out from any to 169.254.0.0/16 comment 'private'
		sudo ufw deny out from any to 172.16.0.0/12  comment 'private'
		sudo ufw deny out from any to 192.168.0.0/16 comment 'private'
		sudo ufw deny out from any to 198.18.0.0/15  comment 'private'
		
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
		
		# configure the CLI
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
		local repo=${tool%/*}/${git_finder##*/}
		rm -rf ${repo}
		get_pkg git python3-venv
		git -C ${tool%/*} clone ${git_finder}
		cd ${repo}
		python3 -m venv venv
		source ./venv/bin/activate
		pip3 install -r requirements.txt
		info ${msg_pkg_installed//PKG/snapshot-finder}
	fi
	
	unset LOG
	local elapsed=$(($(date +%s)-$started))
	log "${msg_log_stop//TIME/$(elapsed $elapsed)}" && ok
}
# END setup

# BEGIN snapshot
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
	[ -n "${accounts_index}" ] && args+=("--accounts-index-path ${accounts_index}" "--enable-accounts-disk-index")
	[ -n "${snapshots}" ]      && args+=("--snapshots ${snapshots}")
	[ -n "${snapshots_inc}" ]  && args+=("--incremental-snapshot-archive-path ${snapshots_inc}")
	
	# run the snapshot tool
	${cmd_exec} ${ledger_tool} create-snapshot -l ${ledger} $(implode ' ' "${args[@]}") "$@" -- ${slot} && ok
}
# END snapshot

# BEGIN stats
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
	local u=$(if_fun is_running ? localhost : "${rpc_url}")
	local opt="-u ${u}"
	
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
					if json_fetch "block ${slot}" ${rpc_url} -1; then
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
	json_fetch "stakes ${vote_acc}" ${rpc_url} ||:
	log "${msg_log_stop//TIME/$(elapsed $SECONDS)}" && ok
}
# END stats

# BEGIN unswap
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
# END unswap

# BEGIN usage
usage(){
	local arr=("${log%/*}") d
	for d in "${dirs[@]}"; do arr+=("${!d}"); done
	arr=(`printf '%s\n' "${arr[@]}" | sort`)
	du -hs $(implode ' ' "${arr[@]}") 2>/dev/null
}
# END usage

# BEGIN watchdog
txtower(){
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	[ -n "${ssh_host}" ]   || error ${err_bind} # required to transfer the tower
	[ -n "${auth_voter}" ] || error ${err_auth_voter}
	[ -s "${auth_voter}" ] || error ${err_file_read//FILE/${auth_voter}}
	[ -s "${staked}" ]     || error ${err_file_read//FILE/${staked}}
	[ -s "${unstaked}" ]   || error ${err_file_read//FILE/${unstaked}}
	
	is_staked || error ${err_transitioned}
	
	# check if the remote unstaked validator is healthy
	local bindip=${ssh_host}
	local alias=$(mkalias ${ssh_bind})
	local errmsg=${err_rpc_health//PUBKEY/${alias}}
	if [ -n "$1" ]; then
		bindip=$1 # overridden by the function argument
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
	
	# check if the tower file exists
	local pub=`${keygen} pubkey ${staked}`
	local f=${tower}/tower-{,1_9-}${pub}.bin
	[ -s "${f}" ] || error ${err_tower_missing//FILE/${f}}
	
	# make up commands
	local ssh_tower=`${cmd_ssh} -p ${ssh_port} ${ssh_user}@${bindip} ${ssh_tool} export tower`
	[ -z "${ssh_tower}" ] && error ${err_tower_get}
	local cmd_tx="${cmd_scp} -P ${ssh_port} ${tower}/tower*-${pub}.bin ${ssh_user}@${bindip}:${ssh_tower}"
	local cmd_rx="${cmd_ssh} -p ${ssh_port} ${ssh_user}@${bindip} ${ssh_tool} rxtower"
	if fd_enabled && [ -f "${fdctl}" ]; then # firedancer
		local cmd_id="${cmd_fd//CMD/set-identity ${unstaked}} --force"
		# [ "${force}" == 1 ] && cmd_id+=' --force'
	else
		local cmd_id="${cmd_exec} ${env_keep} ${validator} -l ${ledger} set-identity ${unstaked}"
	fi
	[ "${unstaked%/*}" == "${keypair%/*}" ] && local unstaked=${unstaked##*/} # make it relative
	local cmd_ln="${sudo} ln -sfv ${unstaked} ${keypair}"
	if is_dryrun; then
		cmd_ln="echo '${unstaked}' -> '${keypair}'"
		cmd_rx+=' --dryrun'
		local tip=" ${tip_dryrun}"
	fi
	[ "${force}" == 1 ] && cmd_rx+=' --force'
	
	# run the transition
	# set-identity is run after ln here because it can potentionally fail
	# and trigger the validator restart with the staked identity, and for
	# this reason, FS trim should also be disabled for a quick catch-up
	${sudo} touch ${trimmed}
	
	local remote="${bindip}:${ssh_tower}"
	local res str status=0 slots=${tower_slot_delay} delay=${tower_delay}
	[ -z "${now}" ] && info ${msg_restart_window}
	wait4r ${min_idle_time} \
	&& log "${msg_log_start//CLIENT/${client}}${tip}" && local started=`date +%s` \
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
	if fd_enabled && [ -f "${fdctl}" ]; then # firedancer
		local cmd_id="${cmd_fd//CMD/set-identity ${staked}} --force"
		# [ "${force}" == 1 ] && cmd_id+=' --force'
	else
		local cmd_id="${cmd_exec} ${env_keep} ${validator} -l ${ledger} set-identity --require-tower ${staked}"
	fi
	[ "${staked%/*}" == "${keypair%/*}" ] && local staked=${staked##*/} # make it relative
	local cmd_ln="${sudo} ln -sfv ${staked} ${keypair}"
	if is_dryrun; then
		cmd_ln="echo '${staked}' -> '${keypair}'"
		local tip=" ${tip_dryrun}"
	fi
	
	# check if the tower file exists and isn't outdated
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
	
	# run the transition
	# set-identity is run after ln here because it can potentionally fail
	# and trigger the validator restart with the unstaked identity, and for
	# this reason, FS trim should also be disabled for a quick catch-up
	${sudo} touch ${trimmed}
	
	local res status=0
	log "${msg_log_start//CLIENT/${client}}${tip}" && SECONDS=0 \
	&& { res=`${cmd_rm} 2>&1` || status=1; log "${res}"; } && [ ${status} -eq 0 ] \
	&& { res=`${cmd_ln} 2>&1` || status=1; log "${res}"; } && [ ${status} -eq 0 ] \
	&& { res=`${cmd_id} 2>&1` || status=1; log "$(fd_sanitize ${res})"; }
	local err=$(fd_sanitize $(echo "${res}" | grep -E -i 'err|failed'))
	log "${msg_log_stop//TIME/$(elapsed $SECONDS)}" && [ ${status} -eq 0 ] && ok || error ${err}
}

# simplified version of txtower() without the tower file transfer
vote_off(){
	is_dryrun || is_linux || { warn ${err_unsupported_os}; return; }
	# ssh_host is not required to stop voting
	[ -n "${auth_voter}" ] || error ${err_auth_voter}
	[ -s "${auth_voter}" ] || error ${err_file_read//FILE/${auth_voter}}
	[ -s "${unstaked}" ]   || error ${err_file_read//FILE/${unstaked}}
	
	# make up commands
	if fd_enabled && [ -f "${fdctl}" ]; then # firedancer
		local cmd_id="${cmd_fd//CMD/set-identity ${unstaked}} --force"
		# [ "${force}" == 1 ] && cmd_id+=' --force'
	else
		local cmd_id="${cmd_exec} ${env_keep} ${validator} -l ${ledger} set-identity ${unstaked}"
	fi
	[ "${unstaked%/*}" == "${keypair%/*}" ] && local unstaked=${unstaked##*/} # make it relative
	local cmd_ln="${sudo} ln -sfv ${unstaked} ${keypair}"
	if is_dryrun; then
		cmd_ln="echo '${unstaked}' -> '${keypair}'"
		local tip=" ${tip_dryrun}"
	fi
	
	# run the transition
	# set-identity is run after ln here because it can potentionally fail
	# and trigger the validator restart with the staked identity, and for
	# this reason, FS trim should also be disabled for a quick catch-up
	${sudo} touch ${trimmed}
	
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
	SENDER=$(mkalias $(${keygen} pubkey ${unstaked}))
	
	# get the latest failover state
	local stamp stake event times ready
	init_wd(){ stamp=; stake=; event=; times=0; ready=N; }; init_wd
	save_wd(){ echo "${stamp}:${stake}:${event}:${times}:${1:-${ready}}" | ${sudo} tee ${wd_data} >/dev/null; }
	# read_wd() is below
	if [ -f "${wd_data}" ]; then
		local str=$(<${wd_data})
		IFS=':'; local arr=(${str}); unset IFS
		if [ ${#arr[@]} -eq 5 ]; then
			stamp=${arr[0]} # [0-9] last seen unix timestamp
			stake=${arr[1]} # staked,unstaked
			event=${arr[2]} # bindip,delinq,norpc,offline,reboot,restart
			times=${arr[3]} # [0-9] the number of consecutive failures
			ready=${arr[4]} # D=disabled,N=no,R=readycheck,Y=yes,[0-9]=cooldown
		fi 
	fi
	
	# process the subcommand
	local rpc_host=localhost
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
		*) is_num "${ready}" && info ${msg_wd_disabled_cooldown} || info ${msg_wd_enabled};;
		esac
		return 0;;
	*)
		if [ -n "$1" ]; then
			is_ip "$1" && rpc_host=$1 || error ${err_arg}
		fi;;
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
			local res=$(json_rpc ${rpc_host} 'getHealth')
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
			if json_fetch 'validators' ${rpc_url} 30; then
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
				local prev_ready=${ready}
				case ${ready} in
				D) # disabled
					info ${msg_wd_disabled};;
				N) # not ready: `wd_data` init, or attended restart
					info ${msg_wd_enabled}
					ready=Y;;
				R) # readycheck
					unset SMS; info ${msg_wd_enabled_recheck}
					ready=Y;;
				*) # cooldown
					if [ "${ready}" -eq 1 ]; then
						info ${msg_wd_enabled_cooldown}
						ready=Y
					elif is_num "${ready}"; then
						ready=$(($ready-1))
					fi;;
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
		ready=Y; SMS=y # enable processing of 2a: reboot
	fi
	
	# NOTE: shouldn't we automatically switch back from the remote
	# now staked validator to the local unstaked (current one) for
	# any reason, other than that the now staked validator triggers
	# a failover (back_force_limit)? In the current design, none of
	# the validators can determine its superior status.
	
	# Part 3: run the failover action based on the collected data
	local failed res= status=0
	
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
		# 2. SELF-DETECTED
		failed=N
		tip_seen=${tip_seen//LIMIT/${failures}}
		# 2a: reboot (while staked)
		if [ -f "${wd_boot}" ]; then
			set_event $E_REBOOT
			warn ${err_rebooted}
			if [ -n "${ssh_host}" ]; then
				res=$(vote_off) || status=1 # allowed to fail
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
				is_ok && ok ${msg_vote_off} || warn ${msg_vote_off} ${tip_errors}
			else
				log "${err_bind}"
			fi
		# 2c: network outage
		elif is_offline; then
			unset SMS # no SMS can be sent while offline
			set_event $E_OFFLINE
			warn ${err_network} ${tip_seen//TIMES/${times}}
			if [ "${times}" -ge "${failures}" ]; then
				if [ -n "${ssh_host}" ]; then
					res=$(vote_off) || status=1 # may but shouldn't fail
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
			warn ${err_rpc} ${tip_seen//TIMES/${times}}
			if [ "${times}" -ge "${failures}" ]; then
				if [ -n "${ssh_host}" ]; then
					SMS=y
					now=1 # no slots can be processed while the RPC is down
					res=$(txtower ${bindip}) || status=1 # no failures accepted
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
				warn ${str//SLOTS/${rpc}} ${tip_seen//TIMES/${times}}
			else
				[ "${times}" -gt "${failures}" ] && unset SMS # don't spam
				warn ${err_rpc} ${tip_seen//TIMES/${times}}
			fi
			if [ "${times}" -ge "${failures}" ]; then
				if [ -n "${ssh_host}" ]; then
					SMS=y
					now=1 # no slots can be processed while the RPC is down
					res=$(txtower ${bindip}) || status=1 # no failures accepted
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
			warn ${err_delinquent} ${tip_seen//TIMES/${times}}
			if [ "${times}" -ge "${failures}" ]; then
				if [ -n "${ssh_host}" ]; then
					SMS=y
					now=1 # no slots can be processed while delinquent
#					res=$(txtower ${bindip}) || status=1 # no failures accepted
					res=$(vote_off) || status=1 # may but shouldn't fail
					is_ok && ok ${msg_tower_tx} || warn ${msg_tower_tx} ${tip_errors}
				else
					log "${err_bind}"
				fi
			fi
			SMS=y
		# 2f: no bind IP (monitoring only)
		elif [ "${bindip}" == N ] || is_num ${bindip}; then
			# `bindip` is set => `ssh_host` is configured
			set_event $E_BINDIP
			local alias=$(mkalias ${ssh_bind})
			# reporting `behind` here is disabled, since it's now reported by
			# the unstaked validator itself while caching up with the cluster
			if false && is_num ${bindip}; then
				local str=${err_rpc_behind//PUBKEY/${alias}}
				warn ${str//SLOTS/${bindip}}
			elif [ "${times}" == 1 ]; then # once per event
				warn ${err_rpc_health//PUBKEY/${alias}}
			fi
		fi
	elif [ "${ready}" == Y ]; then
		# 3. REMOTELY-DETECTED
		failed=N
		failures=$(($failures+$failures_offset))
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
			warn ${err_delinquent} ${tip_seen//TIMES/${times}}
			if [ "${times}" -ge "${failures}" ]; then
				SMS=y
				res=$(vote_on) || status=1 # may but shouldn't fail
				is_ok && ok ${msg_vote_on} || warn ${msg_vote_on} ${tip_errors}
			fi
			SMS=y
		fi
	fi
	
	# check if we failed over
	if [ "${failed}" == Y -a -n "${res}" ]; then
		ready=R # do a ready check
		unset SMS; info ${msg_wd_disabled_recheck}; SMS=y
	fi
	
	# save the failover state
	if [ "${failed}" == Y -a "${times}" -eq 1 ]; then stamp=`date +%s`; fi
	if [ "${failed}" == N -a "${times}" -gt 0 ]; then
		# OK now, but FAILED the last time we checked
		
		local str=${msg_all_clear}
		
		# we can also track network status changes by touching a file
		# on going offline for the 1st time, and deleting it when we're
		# back online again, with a subsequent notification sent by SMS
		[ "${event}" == $E_OFFLINE ] && str=${msg_network}
		
		local ctime=${stamp} # last seen
		local cdiff=$(($(date +%s)-$ctime))
		ok ${str//TIME/$(elapsed $cdiff)}
		
		times=0 # all clear
		if [ "${prev_ready}" == R -a "${cooldown}" -gt 0 ]; then
			ready=${cooldown}
			unset SMS; info ${msg_wd_disabled_cooldown}; SMS=y
		fi
	fi
	save_wd
	
	unset LOG SMS
}
# END watchdog

# BEGIN validator
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
vm.max_map_count = ${nofile}

# Increase number of allowed open file descriptors
fs.nr_open = ${nofile}

# Adjust the swap settings
vm.swappiness = ${swappiness}
vm.vfs_cache_pressure = ${cache_pressure}
EOF"
	sudo sysctl -p /etc/sysctl.d/21-solana-validator.conf
	
	# Increase systemd and session file limits
	sudo bash -c "cat >/etc/security/limits.d/90-solana-nofiles.conf <<EOF
# Increase process file descriptor count limit
* - nofile ${nofile}
# Increase memory locked limit (kB)
* - memlock ${memlock}
EOF"
	
	# set the maximum number of open file descriptors for the shell
	ulimit -n ${nofile}
	
	ok ${msg_sys_tuned}
}

add_account_index(){ in_array $1 "${args[@]}" || args+=("--account-index $1"); }
add_account_index_key(){ in_array $1 "${args[@]}" || args+=("--account-index-include-key $1"); }
validator(){
	is_linux || { warn ${err_unsupported_os}; return; }
	
	if [ "$1" == 'status' ]; then
		${cmd_status}
		return 0
	fi
	
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
	
	# add args from the CLI: flags, options, jito, rakurai
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
		if [ "${full_snapshot_interval_slots}" -gt 0 ]; then
			if [ -z "${no_incremental_snapshots}" ]; then
				# only used when incremental snapshots are enabled
				args+=("--full-snapshot-interval-slots ${full_snapshot_interval_slots}")
			else
				snapshot_interval_slots=${full_snapshot_interval_slots}
			fi
		fi
		if [ "${snapshot_interval_slots}" -gt 0 ]; then
			args+=("--snapshot-interval-slots ${snapshot_interval_slots}")
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
	
	# jito-solana
	if jito_enabled; then
		[ -n "${commission_bps}" ]        && args+=("--commission-bps ${commission_bps}")
		empty "${block_engine_url}"       || args+=("--block-engine-url ${block_engine_url}")
		empty "${relayer_url}"            || args+=("--relayer-url ${relayer_url}")
		empty "${bam_url}"                || args+=("--bam-url ${bam_url}")
		empty "${shred_receiver_address}" || args+=("--shred-receiver-address ${shred_receiver_address}")
	fi
	
	# jito-relayer
	# check if relayer is enabled and required by the systemd unit file
	if [ -f "${relayer}" ] && relayer_required; then
		add_account_index 'program-id'
		add_account_index_key 'AddressLookupTab1e1111111111111111111111111'
		[ -n "${trust_relayer_packets}" ] && args+=("--trust-relayer-packets")
	fi
	
	# doublezero
	if dz_enabled; then
		[ -n "${dz_shred_receiver_address}" ] && args+=("--shred-receiver-address ${dz_shred_receiver_address}")
	fi
	
	# rakurai
	if rakurai_enabled; then
		[ -n "${rewards_merkle_root_authority}" ]  && args+=("--rewards-merkle-root-authority ${rewards_merkle_root_authority}")
		[ -n "${rakurai_activation_program_id}" ]  && args+=("--rakurai-activation-program-id ${rakurai_activation_program_id}")
		[ -n "${reward_distribution_program_id}" ] && args+=("--reward-distribution-program-id ${reward_distribution_program_id}")
		[ -n "${banking_packet_delay_ms}" ]        && args+=("--banking-packet-delay-ms ${banking_packet_delay_ms}")
		[ -n "${target_slot_adjustment_ms}" ]      && args+=("--target-slot-adjustment-ms ${target_slot_adjustment_ms}")
		[ -n "${client_mode}" ]                    && args+=("--client-mode ${client_mode}")
	fi
	
	# fixed a bug: The validator's identity pubkey cannot be a --known-validator
	local pub=`${keygen} pubkey ${staked}` v
	for v in "${known_id[@]}"; do
		[ "${v}" != "${pub}" ] && args+=("--known-validator ${v}")
	done
	
	# run the validator
	[ -n "${env_keep}" ] && log "${env_keep}"
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
# END validator

# main
[ -z "${action}" ] && action=help
pid_lock ${PIDFILE//ACTION/${action}} $PIDWAIT
${action} "$@"
pid_unlock $PIDFILE
# EOF
