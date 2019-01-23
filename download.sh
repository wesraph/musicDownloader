#!/bin/sh
set -e

UPDATE_YOUTUBEDL=${UPDATE_YOUTUBEDL:-1}
export CONFIG_FILE="./config.json"
export LIBRARY_FOLDER="./test/"
export ALLOW_OVERWRITE=0
export TMP_FOLDER="/tmp"

ACTUAL_PATH="$(pwd)"
export ACTUAL_PATH


_required_tool() {
	if ! type "$1" >/dev/null 2>/dev/null; then
		echo "Please install $1"
		exit 1
	fi
}
_required_tool parallel
_required_tool ffmpeg
_required_tool nproc

_print_err_and_exit() {
    echo "$1"
	exit 1
}

LIBRARY_FOLDER=$(jq -r .libraryFolder config.json)
[ "$LIBRARY_FOLDER" ] || _print_err_and_exit "libraryFolder is undefined in config.json"

LIBRARY_FOLDER=$(readlink -f "$LIBRARY_FOLDER")
[ -d "$LIBRARY_FOLDER" ] || _print_err_and_exit "Library folder does not exist"

if [ "$UPDATE_YOUTUBEDL" = 1 ] || [ ! -f "youtube-dl" ]; then
    echo "Updating youtube-dl"
    curl -L https://yt-dl.org/downloads/latest/youtube-dl -o ./youtube-dl
    chmod +x ./youtube-dl
fi

TMP_FOLDER=$(mktemp -d)

touch sound.downloaded sound.failed

todoSoundUrl=$(mktemp)
todoOutputFolder=$(mktemp)

jq -r '.playlistToSync[] | .url + "\t" + .folder' "$CONFIG_FILE" | \
while read -r url outputFolder; do
    echo "Downloading tracklist for $url"

    if [ "$outputFolder" = "null" ]; then
        echo "Output folder for $url is undefined"
        continue
    fi

    if [ ! -d "$LIBRARY_FOLDER/$outputFolder" ]; then
        echo "Creating $outputFolder"
        mkdir -p "$LIBRARY_FOLDER/$outputFolder"
    fi

    tracklist=$(./youtube-dl "$url" --flat-playlist -J)
    if [ -z "$tracklist" ]; then
        echo "Cannot download tracklist $tracklist, please check the url"
        continue
    fi

    echo "$tracklist" | jq -r '.entries[].url' | \
    while read -r soundUrl; do

        echo "Processing $soundUrl"

        type=$(echo "$tracklist" | jq -r ".entries[$u].ie_key")

        #Add the correct soundUrl
        if  echo "$tracklist" | grep "youtube" > /dev/null; then
            url="https://www.youtube.com/watch?v=$soundUrl"
        elif  echo "$tracklist" | grep "soundcloud" > /dev/null; then
            url="$soundUrl"
        else
            echo "$type is not supported, skipping"
            continue
        fi

        echo "$url" >> $todoSoundUrl
        echo "$outputFolder" >> $todoOutputFolder

        #TODO: Add username/password for youtube/souncloud
        #--username \"$Playlist::config->{'username'}\" \
        #--password \"$Playlist::config->{'password'}\"  \
    done

done

parallel --link -a "$todoSoundUrl" -a "$todoOutputFolder" ./worker.sh "{1}" "{2}"

rm -rf "$TMP_FOLDER"
rm -rf "$todoOutputFolder"
rm -rf "$todoSoundUrl"
