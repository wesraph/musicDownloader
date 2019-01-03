#!/bin/sh
set -e

UPDATE_YOUTUBEDL=${UPDATE_YOUTUBEDL:-1}
export CONFIG_FILE="./config.json"
export LIBRARY_FOLDER="./test/"
MAX_CONCURRENT_DOWNLOAD=3

ACTUAL_PATH="$(pwd)"
export ACTUAL_PATH

export ALLOW_OVERWRITE=1

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

if [ "$UPDATE_YOUTUBEDL" = 1 ]; then
    echo "Updating youtube-dl"
    curl -L https://yt-dl.org/downloads/latest/youtube-dl -o ./youtube-dl
    chmod +x ./youtube-dl
fi

# TODO: check that the binary exists

rm -rf tmp || true
mkdir tmp || true

# TODO: tmp -> $(mktemp) ?

#Convert to absolute path to keep consistency

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

        uuid=$(base32 /dev/urandom | head -c 15)
        mkdir -p "tmp/$uuid"
        echo "uuid=\"$uuid\"" >> "tmp/$uuid/worker.sh"

        type=$(echo "$tracklist" | jq -r ".entries[$u].ie_key")

        #Add the outputFolder to the configuration of the worker
        echo "outputFolder=\"$outputFolder\"" >> "tmp/$uuid/worker.sh"


        # Add the title
        if [ "$type" = "Soundcloud" ]; then
            echo "title=\$(\"$ACTUAL_PATH/youtube-dl\" -e \"$soundUrl\")" >> "tmp/$uuid/worker.sh"

            echo "Processing $soundUrl"

        elif [ "$type" = "Youtube" ]; then
            title=$(echo "$tracklist" | jq -r ".entries[$u].title")
            echo "title=\"$title\"" >> "tmp/$uuid/worker.sh"

            echo "Processing $title"

        else
            echo "$type is not supported, skipping"
            continue
        fi

        #Add the correct soundUrl
        if [ "$type" = "Youtube" ]; then
            echo "URL=\"https://www.youtube.com/watch?v=$soundUrl\"" >> "tmp/$uuid/worker.sh"
        elif [ "$type" = "Soundcloud" ]; then
            echo "URL=\"$soundUrl\"" >> "tmp/$uuid/worker.sh"
        else
            echo "$type is not supported, skipping"
            continue
        fi

        #TODO: Add username/password for youtube/souncloud
        #--username \"$Playlist::config->{'username'}\" \
        #--password \"$Playlist::config->{'password'}\"  \

        # Add the rest of the worker
        cat worker.sh >> "tmp/$uuid/worker.sh"
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

find tmp -type f -iname "worker.sh" | parallel -j "$MAX_CONCURRENT_DOWNLOAD" sh
