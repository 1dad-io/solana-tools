#!/bin/bash -e
# Copyright (c) 2025 1Dad <dad@1dad.io>
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# reset format
NC=$(tput sgr0) # No Color

# base characters
CN=${NC} # Normal
CB=$(tput setaf 0) # Black
CR=$(tput setaf 1) # Red
CG=$(tput setaf 2) # Green
CY=$(tput setaf 3) # Yellow
CM=$(tput setaf 4) # Marine Blue
CP=$(tput setaf 5) # Purple
CC=$(tput setaf 6) # Cyan
CW=$(tput setaf 7) # White

# light characters
LN=$(tput bold) # Normal
LB=$(tput bold; tput setaf 0) # Black
LR=$(tput bold; tput setaf 1) # Red
LG=$(tput bold; tput setaf 2) # Green
LY=$(tput bold; tput setaf 3) # Yellow
LM=$(tput bold; tput setaf 4) # Marine Blue
LP=$(tput bold; tput setaf 5) # Purple
LC=$(tput bold; tput setaf 6) # Cyan
LW=$(tput bold; tput setaf 7) # White

# dark characters
[[ "$OSTYPE" == 'linux-gnu'* ]] && DN=$(tput dim) || DN=\\033[2m # Normal
DB=$DN$(tput setaf 0) # Black
DR=$DN$(tput setaf 1) # Red
DG=$DN$(tput setaf 2) # Green
DY=$DN$(tput setaf 3) # Yellow
DM=$DN$(tput setaf 4) # Marine Blue
DP=$DN$(tput setaf 5) # Purple
DC=$DN$(tput setaf 6) # Cyan
DW=$DN$(tput setaf 7) # White

# underline characters
UN=$(tput smul) # Normal
UB=$(tput smul; tput setaf 0) # Black
UR=$(tput smul; tput setaf 1) # Red
UG=$(tput smul; tput setaf 2) # Green
UY=$(tput smul; tput setaf 3) # Yellow
UM=$(tput smul; tput setaf 4) # Marine Blue
UP=$(tput smul; tput setaf 5) # Purple
UC=$(tput smul; tput setaf 6) # Cyan
UW=$(tput smul; tput setaf 7) # White

# blinking characters
BN=$(tput blink) # Normal
BB=$(tput blink; tput setaf 0) # Black
BR=$(tput blink; tput setaf 1) # Red
BG=$(tput blink; tput setaf 2) # Green
BY=$(tput blink; tput setaf 3) # Yellow
BM=$(tput blink; tput setaf 4) # Marine Blue
BP=$(tput blink; tput setaf 5) # Purple
BC=$(tput blink; tput setaf 6) # Cyan
BW=$(tput blink; tput setaf 7) # White

# background
BGB=$(tput setab 0) # Black
BGR=$(tput setab 1) # Red
BGG=$(tput setab 2) # Green
BGY=$(tput setab 3) # Yellow
BGM=$(tput setab 4) # Marine Blue
BGP=$(tput setab 5) # Purple
BGC=$(tput setab 6) # Cyan
BGW=$(tput setab 7) # White

term_usage() {
	echo -e "Reset format (No Color): \${NC}"
	echo -e "┌────────────────────────────┐ ┌────────────────────────────┐"
	echo -e "│      Base Characters       │ │      Light Characters      │"
	echo -e "├────────┬────────┬──────────┤ ├────────┬────────┬──────────┤"
	echo -e "│ Color  │ Output │ Variable │ │ Color  │ Output │ Variable │"
	echo -e "├────────┼────────┼──────────┤ ├────────┼────────┼──────────┤"
	echo -e "│ Normal │ ${CN}Output${NC} │ \${CN}    │ │ Normal │ ${LN}Output${NC} │ \${LN}    │"
	echo -e "│ Black  │ ${CB}Output${NC} │ \${CB}    │ │ Black  │ ${LB}Output${NC} │ \${LB}    │"
	echo -e "│ Red    │ ${CR}Output${NC} │ \${CR}    │ │ Red    │ ${LR}Output${NC} │ \${LR}    │"
	echo -e "│ Green  │ ${CG}Output${NC} │ \${CG}    │ │ Green  │ ${LG}Output${NC} │ \${LG}    │"
	echo -e "│ Yellow │ ${CY}Output${NC} │ \${CY}    │ │ Yellow │ ${LY}Output${NC} │ \${LY}    │"
	echo -e "│ Marine │ ${CM}Output${NC} │ \${CM}    │ │ Marine │ ${LM}Output${NC} │ \${LM}    │"
	echo -e "│ Purple │ ${CP}Output${NC} │ \${CP}    │ │ Purple │ ${LP}Output${NC} │ \${LP}    │"
	echo -e "│ Cyan   │ ${CC}Output${NC} │ \${CC}    │ │ Cyan   │ ${LC}Output${NC} │ \${LC}    │"
	echo -e "│ White  │ ${CW}Output${NC} │ \${CW}    │ │ White  │ ${LW}Output${NC} │ \${LW}    │"
	echo -e "└────────┴────────┴──────────┘ └────────┴────────┴──────────┘"
	echo -e "┌────────────────────────────┐ ┌────────────────────────────┐"
	echo -e "│      Dark Characters       │ │    Underline Characters    │"
	echo -e "├────────┬────────┬──────────┤ ├────────┬────────┬──────────┤"
	echo -e "│ Color  │ Output │ Variable │ │ Color  │ Output │ Variable │"
	echo -e "├────────┼────────┼──────────┤ ├────────┼────────┼──────────┤"
	echo -e "│ Normal │ ${DN}Output${NC} │ \${DN}    │ │ Normal │ ${UN}Output${NC} │ \${UN}    │"
	echo -e "│ Black  │ ${DB}Output${NC} │ \${DB}    │ │ Black  │ ${UB}Output${NC} │ \${UB}    │"
	echo -e "│ Red    │ ${DR}Output${NC} │ \${DR}    │ │ Red    │ ${UR}Output${NC} │ \${UR}    │"
	echo -e "│ Green  │ ${DG}Output${NC} │ \${DG}    │ │ Green  │ ${UG}Output${NC} │ \${UG}    │"
	echo -e "│ Yellow │ ${DY}Output${NC} │ \${DY}    │ │ Yellow │ ${UY}Output${NC} │ \${UY}    │"
	echo -e "│ Marine │ ${DM}Output${NC} │ \${DM}    │ │ Marine │ ${UM}Output${NC} │ \${UM}    │"
	echo -e "│ Purple │ ${DP}Output${NC} │ \${DP}    │ │ Purple │ ${UP}Output${NC} │ \${UP}    │"
	echo -e "│ Cyan   │ ${DC}Output${NC} │ \${DC}    │ │ Cyan   │ ${UC}Output${NC} │ \${UC}    │"
	echo -e "│ White  │ ${DW}Output${NC} │ \${DW}    │ │ White  │ ${UW}Output${NC} │ \${UW}    │"
	echo -e "└────────┴────────┴──────────┘ └────────┴────────┴──────────┘"
	echo -e "┌────────────────────────────┐ ┌────────────────────────────┐"
	echo -e "│     Blinking Characters    │ │        Background          │"
	echo -e "├────────┬────────┬──────────┤ ├────────┬────────┬──────────┤"
	echo -e "│ Color  │ Output │ Variable │ │ Color  │ Output │ Variable │"
	echo -e "├────────┼────────┼──────────┤ ├────────┼────────┼──────────┤"
	echo -e "│ Normal │ ${BN}Output${NC} │ \${BN}    │ │        │        │          │"
	echo -e "│ Black  │ ${BB}Output${NC} │ \${BB}    │ │ Black  │ ${BGB}Output${NC} │ \${BGB}   │"
	echo -e "│ Red    │ ${BR}Output${NC} │ \${BR}    │ │ Red    │ ${BGR}Output${NC} │ \${BGR}   │"
	echo -e "│ Green  │ ${BG}Output${NC} │ \${BG}    │ │ Green  │ ${BGG}Output${NC} │ \${BGG}   │"
	echo -e "│ Yellow │ ${BY}Output${NC} │ \${BY}    │ │ Yellow │ ${BGY}Output${NC} │ \${BGY}   │"
	echo -e "│ Marine │ ${BM}Output${NC} │ \${BM}    │ │ Marine │ ${BGM}Output${NC} │ \${BGM}   │"
	echo -e "│ Purple │ ${BP}Output${NC} │ \${BP}    │ │ Purple │ ${BGP}Output${NC} │ \${BGP}   │"
	echo -e "│ Cyan   │ ${BC}Output${NC} │ \${BC}    │ │ Cyan   │ ${BGC}Output${NC} │ \${BGC}   │"
	echo -e "│ White  │ ${BW}Output${NC} │ \${BW}    │ │ White  │ ${BGW}Output${NC} │ \${BGW}   │"
	echo -e "└────────┴────────┴──────────┘ └────────┴────────┴──────────┘"
	return 0 2>/dev/null; exit 0
}

# get options from the CLI
while test $# -gt 0; do
	case "$1" in
	-h|--help)
		term_usage
		break;;
	*|--)
		break;;
	esac
done
