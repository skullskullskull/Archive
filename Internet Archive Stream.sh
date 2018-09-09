#!/bin/bash

# Systems to on white list. Games that are small (<10 Mb), don't require a bios, and have emulators in default RetroPie build (sorry Super A'can!)
system_List=("Atari 2600" "Atari 7800" "SG-1000" "Master System" "Game Gear" "Mega Drive/Genesis" "Neo Geo pocket/color")
IA_Collection=(atari_2600_library atari_7800_library sg_1000_library sega_sms_library gamegear_library sega_genesis_library ngp_library )
IA_Ext=(bin a78 bin bin bin bin bin)

# Arrays to read Internet Archives's metadata and translate to Raspberry Pi calls
# IA_ prefix is for dealing with IA xml data, RPi_ prefix is for parameters & extensions on Pi.

RPi_Run_Pram=(atari2600 atari7800 sg-1000 mastersystem gamegear megadrive ngpc )
RPi_Ext=(a26 a78 sg sms gg md ngc )

PS3="Input number: "
sysNumber=-1
function IASplash {
	if [[ ! -e ../IA.png ]]; then
		wget -O ../IA.png --user-agent=$APIKey "https://archive.org/images/notfound.png" -q
	fi
	fbi -1 -t 2 -noverbose -a "../IA.png" </dev/tty &>/dev/null
clear
}

function fetchXML {
	# fetches 'search.xml' for MAIN to parse for games. 

	# '.lastA' is a text file holding the title and command used to launch the last game. It gets generated right before the game is launched.
	if [[ -e .lastA ]]; then
		source <(grep = .lastA)
		Display_system_List=("${system_List[@]}" "Continue: ${LGname}")
	else
		Display_system_List=("${system_List[@]}")
	fi
clear
	echo "Select system"
	select xmlchoice in "${Display_system_List[@]}" "EXIT                                     "
		do
		if [[ ${xmlchoice// } == "EXIT" ]]; then exit; fi
		if [[ $xmlchoice == "Continue"* ]]; then cd ~/.InternetArchive/Loaned/; IASplash; $LGcommand; exit; fi
		if [[ ! -z $xmlchoice ]]; then break; fi
	done
	# have a string, really want position
	for i in "${!system_List[@]}"; do
		if [[ "${system_List[$i]}" = "${xmlchoice}" ]]; then
			sysNumber=$i
			break
		fi
	done
	echo -e " Enter Search string (or leave blank)"
	read choiceSearch
	sortMethod="-downloads"
	# Adds 'lol, randomness' to empty searches by changing sort methods. 
	if [[ -z $choieSearch ]]; then
		display_array=(publicdate -publicdate date -date reviewdate -reviewdate)
		# returns an element of the array that is randomly picked with random range [0, array size]
		sortMethod=${display_array[((RANDOM % ${#display_array[@]}))]}
	fi
	wget -O search.xml --user-agent=$APIKey "https://archive.org/advancedsearch.php?q=collection%3A${IA_Collection[$sysNumber]}+$choiceSearch&fl%5B%5D=identifier&fl%5B%5D=title&sort%5B%5D=$sortMethod&rows=9999&page=1&callback=callback&save=yes&output=xml" -q
}

function run_game {
	# gets passed an IA identifier. Parses meta.xml and files.xml to stream the right file.
	clear
	url=$( cut -d "/" -f 5 <<< "$1" )
	wget -O meta.xml --user-agent=$APIKey https://cors.archive.org/cors/${url}/${url}_meta.xml -q
	wget -O files.xml --user-agent=$APIKey https://cors.archive.org/cors/${url}/${url}_files.xml -q
	title=$(grep "<title>" meta.xml | cut -c10- | sed -e 's/<\/.*//')
	Ext=$(grep "<emulator_ext>" meta.xml | sed 's|</.*>||' | sed 's/.*>//')
	if [[ -z $Ext ]]; then 
		#Error handling. Part 1: Guess
		Ext="${IA_Ext[$sysNumber]}"
	fi
	Fil=$(grep $Ext files.xml | sed 's/.*name="//' | sed 's/" source.*//')
	if [[ -z $Fil ]]; then
		#Error handling. Part 2: Give up
		echo "Miscatorgized game: non-streaming title"
		sleep 3
		exit
	fi
	rm meta.xml files.xml

	echo "Loading "$title" ..."

	# Explanation of variables:
	# archive.org/details/sg_Out_Run_1991_Sega
	# URL= sg_Out_Run_1991_Sega (IA's 'identifier')
	# title= Out Run
	# Ext= bin 
	# Fil= Out_Run_1991_Sega.bin

	mkdir -p "Loaned" && cd "$_"
	wget -O game.${RPi_Ext[$sysNumber]} --user-agent=$APIKey https://cors.archive.org/cors/${url}/${Fil} -q --show-progress

	IASplash
	echo "LGname=\"$title\""> ../.lastA
	echo "LGcommand=\"/opt/retropie/supplementary/runcommand/runcommand.sh 0 _SYS_ ${RPi_Run_Pram[$sysNumber]} game.${RPi_Ext[$sysNumber]}\"" >> ../.lastA
	/opt/retropie/supplementary/runcommand/runcommand.sh 0 _SYS_ ${RPi_Run_Pram[$sysNumber]} game.${RPi_Ext[$sysNumber]}
}

#MAIN
mkdir -p ".InternetArchive" && cd "$_"
APIKey='RetroPie_IA_Streaming_Project'
PS3="Choice number: "
fetchXML
IFS=$'\n'
all_done=0
start=0
while (( !all_done )); do
clear
gamelist=$(tail -n +${start} search.xml | grep 'title' | cut -c23- | sed 's/<.*//' | head -n 20)
echo "Pick a game:"
	# 'search again' has trailing whitespace to force SELECT to show 1 line per row
	select gamexml in ${gamelist[@]} "NEXT" "SEARCH AGAIN                                           "
		do
		if [[ "${gamexml// }" == "SEARCHAGAIN" ]]; then fetchXML; break; fi
		if [[ "${gamexml}" == "NEXT" ]]; then
			# A single game in xml uses 4 lines; 20 titles x 4 lines/title = 80 lines 
			start=$((start + 80))
			gamelist=$(tail -n +${start} search.xml | grep 'title' | cut -c23- | sed 's/<.*//' | head -n 20)
		else
			all_done=1
			# if gamexml contains [words], grep sees it as a pattern not a string, so we escape "[" here ( '[' -> '\[' )
			gamexml=$(echo "${gamexml}" |sed 's/\[/\\[/g')
			run_game $( grep -B 1 "${gamexml}</str>" search.xml| head -n 1 | cut -c28- | sed 's#</str>##')
		fi
		break
	done
done
clear
