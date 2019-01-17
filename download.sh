#!/bin/sh
set -e

#UPDATE_YOUTUBEDL=${UPDATE_YOUTUBEDL:-1}
UPDATE_YOUTUBEDL=0
export CONFIG_FILE="./config.json"
export LIBRARY_FOLDER="./test/"
export ALLOW_OVERWRITE=0
export TMP_FOLDER="/tmp"
MAX_CONCURRENT_DOWNLOAD=3

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
mkdir -p  $TMP_FOLDER

todoSoundUrl=$(mktemp)
todoOutputFolder=$(mktemp)

# TODO: tmp -> $(mktemp) ?
i=0
url=$(jq -r ".playlistToSync[$i].url" "$CONFIG_FILE")
while [ "$url" != "null" ]; do
    echo "Downloading tracklist for $url"
    outputFolder=$(jq -r ".playlistToSync[$i].folder" "$CONFIG_FILE")

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

    u=0
    soundUrl=$(echo "$tracklist" | jq -r ".entries[$u].url")
    while [ "$soundUrl" != "null" ]; do

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

        #Get the next url
        u=$((u + 1))
        soundUrl=$(echo "$tracklist" | jq -r ".entries[$u].url")
    done

    #Next turn
    i=$((i + 1))
    url=$(jq -r ".playlistToSync[$i].url" "$CONFIG_FILE")
done

if [ "$MAX_CONCURRENT_DOWNLOAD" -gt "$(nproc)" ]; then
    MAX_CONCURRENT_DOWNLOAD=$(nproc)
fi

echo "Launching downloads using $MAX_CONCURRENT_DOWNLOAD max concurrent downloads"
parallel --link -a "$todoSoundUrl" -a "$todoOutputFolder" ./worker.sh "{1}" "{2}"
#find tmp -type f -iname "worker.sh" | parallel -j "$MAX_CONCURRENT_DOWNLOAD" sh

rm -rf "$TMP_FOLDER"
rm -rf "$todoOutputFolder"
rm -rf "$todoSoundUrl"
