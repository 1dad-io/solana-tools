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
# shellcheck disable=SC2004,SC2006,SC2155,SC2166

# path/to/binary
crank=$HOME/marinade-crank/target/debug/marinade-crank

# read config
tool=$HOME/solana-tools/solana.sh
rpc_url=http://localhost:8899
rpc_retry=`${tool} export rpc_retry`
solana=`${tool} export solana`
keygen=`${tool} export keygen`
keypair=`${tool} export keypair`
vote_acc=`${tool} export vote_acc`
vote_pub=$(${keygen} pubkey "${vote_acc}")

# simulate
${crank} --vote-account "${vote_pub}" --keypair "${keypair}" --cluster "${rpc_url}" --simulate

if [ -z "$1" ]; then
	echo "Usage: $0 <slot>"
	echo "Waits until the specified slot, then runs."
	exit 0
fi

slot=$1
c=0
while true; do
	curr_slot=$(${solana} -ul slot --commitment confirmed)
	echo "Waiting until slot ${slot}. Current slot: ${curr_slot}"
	if [ "${curr_slot}" -ge "${slot}" ]; then
		c=$(($c+1))
		echo "${curr_slot} >= ${slot}. Running #${c}."
		${crank} --vote-account "${vote_pub}" --keypair "${keypair}" --cluster "${rpc_url}"
	fi
	
	if (( $c >= $rpc_retry )); then
		echo "Max number of retries reached. Bailing out."
		break
	fi
	
	sleep 1 # poll every second
done
