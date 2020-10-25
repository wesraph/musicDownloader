#!/bin/sh
set -e

UPDATE_YOUTUBEDL=${UPDATE_YOUTUBEDL:-1}
export CONFIG_FILE="./config.json"
export LIBRARY_FOLDER="./test/"
export ALLOW_OVERWRITE=${ALLOW_OVERWRITE:-0}
export TMP_FOLDER="/tmp"

ACTUAL_PATH="$(pwd)"
export ACTUAL_PATH

_required_tool() {
	if ! type "$1" >/dev/null 2>/dev/null; then
		echo "Please install $1"
		exit 1
	fi
}

_rewrite_urls() {
        awk \
        -v todoSoundUrl="$todoSoundUrl" \
        -v todoOutputFolder="$todoOutputFolder" \
        -v tracklistUrl="$tracklistUrl" \
        -v outputFolder="$outputFolder" \
        '{
            if (match(tracklistUrl, /youtube/))
            {
                print "https://www.youtube.com/watch?v="$1 >> todoSoundUrl
            } else if(match(tracklistUrl, /soundcloud/))
            {
                print $1 >> todoSoundUrl
            } else if(match(tracklistUrl, /filelist\:\/\//))
            {
                print $1 >> todoSoundUrl
            }

            print outputFolder >> todoOutputFolder
        }'
}

_prepare_downloads() {
    while read -r playlistJson; do
        tracklistUrl="$(awk 'NR==1' "$playlistJson")"
        outputFolder="$(awk 'NR==2' "$playlistJson")"

        echo "Treating $tracklistUrl"

        if [ "$outputFolder" = "null" ]; then
            echo "Output folder for $tracklistUrl is undefined"
            continue
        fi

        if [ ! -d "$LIBRARY_FOLDER/$outputFolder" ]; then
            echo "Creating $outputFolder"
            mkdir -p "$LIBRARY_FOLDER/$outputFolder"
        fi

        if echo "$tracklistUrl" | grep -E '^filelist\:\/\/' > /dev/null; then
            filePath="$(echo "$tracklistUrl" | sed -E 's/^filelist\:\/\///g')"
            [ ! -f "$filePath" ] && {
                echo "$filePath does not exist" >&2
                continue
            }
            cat "$filePath" | _rewrite_urls
        else
            tail -n+3 "$playlistJson" | jq -r '.entries[].url' | _rewrite_urls
        fi

        rm "$playlistJson"
    done
}

_install_parallel() {
    rm parallel* -rf
    curl -L http://ftp.gnu.org/gnu/parallel/parallel-latest.tar.bz2 -o parallel.tar.bz2
    tar xvf parallel.tar.bz2
    rm parallel.tar.bz2
    cd parallel-*
    ./configure
    make
    cp src/parallel ../parallel
    cd ../
    rm parallel-* -rf
}

_required_tool ffmpeg

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

if [ ! -f "parallel" ]; then
    echo "Parallel is missing, compiling from source"
    _install_parallel
fi

TMP_FOLDER=$(mktemp -d)

touch sound.downloaded sound.failed

todoSoundUrl=$(mktemp)
todoOutputFolder=$(mktemp)

echo "Extracting tracklists"

jq -r '.playlistToSync[] | .url + "\t" + .folder' "$CONFIG_FILE" |\
./parallel  --colsep '\t' --files   'echo {1} && echo {2} && ./youtube-dl {1} --flat-playlist -J' | \
_prepare_downloads

./parallel --eta --progress --link -a "$todoSoundUrl" -a "$todoOutputFolder" ./worker.sh "{1}" "{2}"

rm -rf "$TMP_FOLDER"
rm -rf "$todoOutputFolder"
rm -rf "$todoSoundUrl"
