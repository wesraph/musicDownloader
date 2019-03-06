#!/bin/sh

set -e

export CONFIG_FILE="config.json"
export LIBRARY_FOLDER="./test/"
ACTUAL_PATH="$(pwd)"
export ACTUAL_PATH

LIBRARY_FOLDER=$(jq -r .libraryFolder config.json)
[ "$LIBRARY_FOLDER" ] || _print_err_and_exit "libraryFolder is undefined in config.json"

mkdir -p "$LIBRARY_FOLDER/Playlists"
cd "$LIBRARY_FOLDER/Playlists"

jq -r '.playlistToSync[] | .folder' "$ACTUAL_PATH/$CONFIG_FILE" | \
    while read -r playlist_folder; do
        stat -c "%Y %n" ../"$playlist_folder/"*  | sort -r | cut -d" " -f2-100 > "$playlist_folder".m3u
    done
