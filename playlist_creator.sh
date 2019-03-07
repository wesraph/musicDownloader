#!/bin/sh
set -e

export CONFIG_FILE="./config.json"
ACTUAL_PATH="$(pwd)"

LIBRARY_FOLDER=$(jq -r .libraryFolder config.json)
[ "$LIBRARY_FOLDER" ] || _print_err_and_exit "libraryFolder is undefined in config.json"

mkdir -p "$LIBRARY_FOLDER/Playlists"
cd "$LIBRARY_FOLDER/Playlists"

jq -r '.playlistToSync[] | .folder' "$ACTUAL_PATH/$CONFIG_FILE" | uniq |   \
while read -r playlist_folder; do
    echo "Creating playlist for $playlist_folder"
    stat -c "%Y %n" ../"$playlist_folder/"*  | sort -r | cut -d" " -f2- > "$playlist_folder".m3u
done

echo "Creating global playlist"
find ../ -path ../Playlists -prune -o -type f -exec stat -c "%Y %n" {} \; | sort -r | cut -d" " -f2- > Library.m3u

echo "OK"
