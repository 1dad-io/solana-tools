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

# read config
tool=$HOME/solana-tools/solana.sh
ledger=`${tool} export ledger`
# snapshots=`${tool} export snapshots`
snapshots_inc=`${tool} export snapshots_inc`

# move old snapshots out of --incremental-snapshot-archive-path
tmp=${snapshots_inc}/tmp
sudo mkdir -p "${tmp}"
sudo mv "${snapshots_inc}"/incremental-* "${tmp}" 2>/dev/null || echo "No file(s) to move"

# make a new snapshot <SLOT>
${tool} make-snapshot $1 \
	--incremental \
	--deactivate-feature-gate \
	htsptAwi2yRoZH83SKaUXykeZGtZHgxkS2QwW1pssR8 \
	turbnbNRp22nwZCmgVVXFSshz7H7V23zMzQgA46YpmQ \
	--enable-capitalization-change

# if the new incremental snapshot created in --ledger instead of
# --incremental-snapshot-archive-path, move it to the right place
su_find(){ sudo find "$1" -maxdepth 1 -type f -name "$2" -print -quit | grep -q .; }
if [ "${snapshots_inc}" != "${ledger}" ] && su_find "${ledger}" 'incremental-*'; then
	sudo mv "${ledger}"/incremental-* "${snapshots_inc}"
fi

# clean up tmp
su_find "${snapshots_inc}" 'incremental-*' && sudo rm -rf "${tmp}"
