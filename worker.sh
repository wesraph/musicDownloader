set -e 

 if [ -z "$1" ] || [ -z "$2" ]; then
     echo "Usage : worker.sh link outputFolder"
     exit 1
 fi

soundUrl="$1"
outputFolder="$2"

uuid=$(base32 /dev/urandom | head -c 15)
mkdir -p "$TMP_FOLDER/$uuid"
cd "$TMP_FOLDER/$uuid"  || exit

count=0
MAX_COUNT=3

#TODO: Get the title 
title="$("$ACTUAL_PATH/youtube-dl" -e "$soundUrl" | sed "s/\"|'|\\|\///g")"

if [ -f "$LIBRARY_FOLDER/$outputFolder/$title.mp3" ] && [ "$ALLOW_OVERWRITE" = "0" ]; then
    echo "Skipping $title"
    exit 0
fi

while [ $count -lt $MAX_COUNT ]; do

    echo "Downloading $title $count/$MAX_COUNT"

    if "$ACTUAL_PATH"/youtube-dl  \
        -o "$TMP_FOLDER/$uuid/%(title)s.%(ext)s" \
        -f 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best' \
        -x --audio-format mp3 --audio-quality 0 \
        --add-metadata \
        --metadata-from-title  "%(artist)s  -  %(title)s" \
        --embed-thumbnail --add-metadata -c -i "$soundUrl" > /dev/null
    then
        break
    else
        count=$((count + 1))
        sleep 2
    fi
done

if [ "$count" = "$MAX_COUNT" ]; then
    echo "Failed to download $title"
    echo "$soundUrl" > "$ACTUAL_PATH/failed_downloads.log"
    exit 1
fi

#TODO: Change this
toMove=$(find "$TMP_FOLDER/$uuid/" -iname "*.mp3")
echo "Moving $title"
mv "$toMove" "$LIBRARY_FOLDER/$outputFolder/$title.mp3"

