# Exjobb 2022 av Magnus Passi och Andreas Granbäck
# Skriptets funktion är att fånga upp information
# om tv-kanalers kvalité och formatera den data
# för att senare överföra till en databas.
# Den formaterade data som ligger i databasen
# används sedan för att presentera informationen
# i form av grafer i ett webbgränssnitt.
while true
do

pcrcount=0
jitterTotal=0
drops=0
es=()

# Omdöpning av argument

STREAM=$1
PROVIDER=$2
CHANNEL=$3
JITTER=$4

OLDIFS=$IFS
IFS=$’\n’

metrics=( $(tsp \
-I ip --timestamp-priority kernel-rtp-tsp \
--receive-timeout 5000 $STREAM \
-P continuity \
-P pcrverify -j 0 --input-synchronous \
-P bitrate_monitor -t 1 -p 9 \
-P until -s 10 -O drop 2>&1 | \
awk ’{
if($6 == "PCR")
{
	gsub(/,/, "", $10); \
	print "PCR " strftime("%S ", systime()) $10
}
else if($8 == "missing")
{
	print "DROPS ", strftime("%S ", systime()) $9
}
else if($2 == "bitrate_monitor:")
{
	gsub(/,/, "", $7); print "Bitrate " $7
}
}’) )
for packet in "${metrics[@]}"
do
	IFS=’ ’
	read -a splitString <<< "$packet"
	if [ ${splitString[0]} == "PCR" ]
	then
		if [[ ${splitString[2]} -gt $JITTER ]] && \
			[[ ! " ${es[*]} " =~ " ${splitString[1]} " ]]
		then
			es+=(${splitString[1]})
		fi
		((pcrcount+=1))
		((jitterTotal+=${splitString[2]}))
	elif [ ${splitString[0]} == "DROPS" ]
	then
		((drops+=${splitString[2]}))
		if [[ ! " ${es[*]} " =~ " ${splitString[1]} " ]]
		then
			es+=(${splitString[1]})
		fi
	else
		bitrate=$(echo "scale=2; \
			${splitString[1]}/1000000" | bc)
	fi
done
avgJitter=$(echo "scale=2;($jitterTotal/$pcrcount)/1000" | bc)
dropsPerSec=$((drops/10))
esProcent=$((${#es[@]}*10))
mysql -u USERNAME -p PASSWORD -h x.x.x.x << EOF
use IPTV;
INSERT INTO $PROVIDER\_$CHANNEL values (
now(),
$esProcent,
$dropsPerSec,
$avgJitter,
2$bitrate);
EOF
IFS=$OLDIFS
done
