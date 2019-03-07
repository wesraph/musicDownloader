set -e

 if [ -z "$1" ] || [ -z "$2" ]; then
     echo "Usage : worker.sh link outputFolder"
     exit 1
 fi

soundUrl="$1"
outputFolder="$2"

if grep sound.downloaded -e "$soundUrl" > /dev/null ; then
    echo "Already downloaded: $soundUrl"
    exit 0
fi

if grep sound.failed -e "$soundUrl" > /dev/null ; then
    echo "Already failed: $soundUrl"
    exit 0
fi

uuid=$(base32 /dev/urandom | head -c 15)
mkdir -p "$TMP_FOLDER/$uuid"
cd "$TMP_FOLDER/$uuid"  || exit

count=0
MAX_COUNT=3


# TODO: Get the title
title="$("$ACTUAL_PATH/youtube-dl" -e "$soundUrl" | sed "s/\"|'|\\|\///g")"

if [ -f "$LIBRARY_FOLDER/$outputFolder/$title.mp3" ] && [ "$ALLOW_OVERWRITE" = "0" ]; then
    echo "Already in library: $title"
    echo "$soundUrl" >> "$ACTUAL_PATH/sound.downloaded"
    exit 0
fi

while [ $count -lt $MAX_COUNT ]; do

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
    echo "$soundUrl" >> "$ACTUAL_PATH/sound.failed"
    exit 1
fi

echo "$soundUrl" >> "$ACTUAL_PATH/sound.downloaded"

# TODO: Change this
toMove=$(find "$TMP_FOLDER/$uuid/" -iname "*.mp3")

# Force creation/modify date
touch "$toMove"

mv "$toMove" "$LIBRARY_FOLDER/$outputFolder/$title.mp3"

# Add song to the beginning of its corresponding playlist
tmp_playlist="$(mktemp)"
echo "../$outputFolder/$title.mp3" | cat - "$LIBRARY_FOLDER/Playlists/$outputFolder.m3u" > "$tmp_playlist"
mv "$tmp_playlist" "$LIBRARY_FOLDER/Playlists/$outputFolder.m3u"

echo "Ok: $title"
