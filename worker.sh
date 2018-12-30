
count=0
MAX_COUNT=3

while [ $count -lt $MAX_COUNT ];do

    #Escape title
    title="$(echo "$title" | sed -E "s/\"|'|\\|//g")"

    if [ -f "$LIBRARY_FOLDER/$outputFolder/$title.mp3" -a "$ALLOW_OVERWRITE" = "0" ]; then
        echo "Skipping $title"
        exit 0
    fi

    echo "Downloading $title"

    "$ACTUAL_PATH"/youtube-dl  \
        -o "$ACTUAL_PATH/tmp/$uuid/%(title)s.%(ext)s" \
        -f 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best' \
        -x --audio-format mp3 --audio-quality 0 \
        --add-metadata \
        --metadata-from-title  "%(artist)s  -  %(title)s" \
        --embed-thumbnail --add-metadata -c  -i "$URL"

    if [ $? != 0 ]; then
        echo "Failed to download $title, retrying"
        count=$((count + 1))
        sleep 10
    else
        break
    fi
done

if [ "$count" = "$MAX_COUNT" ]; then
    echo "Failed to download $title"
    echo "$URL" > "$ACTUAL_PATH/failed_downloads.log"
    exit 1
fi

toMove=$(find "$ACTUAL_PATH/tmp/$uuid/" -iname "*.mp3")
echo "Moving $title"
mv "$toMove" "$LIBRARY_FOLDER/$outputFolder/$title.mp3"

