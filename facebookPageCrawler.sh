#!/bin/sh

#TODO: Reenable set -e after curl mystery
#set -e

 _panic () {
     echo "$1" >&2
     exit
 }

 _curl () {
     [ -z "$1" ] && _panic "No url to fetch"

     URL="$(echo "$1" | sed -E 's/\&amp;/\&/g')"

     sleep "$(shuf -i 5-10 -n 1)"
     curl "$URL" -# -H 'authority: mbasic.facebook.com' -H 'cache-control: max-age=0'\
         -H 'upgrade-insecure-requests: 1' \
         -H 'user-agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/73.0.3683.86 Safari/537.36' \
         -H 'accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8' \
         -H 'referer: https://mbasic.facebook.com/search/top/?q=techno+flex+&refid=7&ref=wizard&_rdr'  \
         -H 'accept-language: en-US,en;q=0.9,fr;q=0.8' \
         --cookie cookie.txt
 }

_find_all_pages_links () {
    echo "Grabbing pages link"

    next_url="$BASE_URL/groups/$GROUP_ID"

    pages_urls="$1"
    threads_urls="$2"

    [ -z "$pages_urls" ] || [ -z "$threads_urls" ] && {
        _panic "Missing pages_urls or threads_urls"
    }

    touch "$pages_urls" "$threads_urls"

    for p in $(seq 1 "$MAX_PAGES"); do
        echo "Grabbing $p/$MAX_PAGES: $next_url"

        content=$(_curl "$next_url")
        next_url="$(echo "$content" | grep -Po '\/groups\/\d*?\?bacr=.*?\&' | tail -n 1)"

        grep "$next_url" "$pages_urls" || echo "$next_url" >> "$pages_urls"

        echo "$content" |\
        grep -Po '\/groups\/\d*?\?view=permalink\&amp;id=\d*?&' | uniq |\
        while read -r thread_url; do
            grep "$thread_url" "$threads_urls" || echo "$thread_url" >> "$threads_urls"
        done

        next_url="https://mbasic.facebook.com$next_url"

        echo "Ok"
    done
}

_match_page () {
    [ -z "$1" ] && _panic "There is no page content to match"
    echo "$1" | grep -Po '\/groups\/\d*?\?view=permalink\&amp;id=\d*?&amp;p=\d*&'
}

_url_decode () {
    [ -z "$1" ] && _panic "There is no url to decode"
    echo "$1" | awk '
    {
        for (i = 0x20; i < 0x40; ++i) {
            repl = sprintf("%c", i);
            if ((repl == "&") || (repl == "\\"))
                repl = "\\" repl;
                gsub(sprintf("%%%02X", i), repl);
                gsub(sprintf("%%%02x", i), repl);
            }
        print
    }'
}

_find_all_sounds_links () {
    threads_urls="$1"
    sounds_urls="$2"

    [ -z "$sounds_urls" ] || [ -z "$threads_urls" ] && {
        echo "Missing sounds_urls or threads_urls"
        exit 1
    }

    [ ! -f "$threads_urls" ] && _panic "There is no threads_urls"

    touch "$sounds_urls"

    len="$(wc -l "$threads_urls" | cut -d" " -f1)"
    i=1

    while read -r thread_url; do
        echo "Grabbing all links from $thread_url"
        next_url="$thread_url"
        old_url=
        while true; do
            echo "Grabbing page ($i / $len) $BASE_URL$next_url"

                content="$(_curl "$BASE_URL$next_url")"

                echo "$content"  | sed 's/>/\n/g' |\

                grep -Po 'https.*?(youtu.be|soundcloud|youtube).*?" ' |\
                sed 's/https:\/\/lm.facebook.com\/l.php?u=//g' | sed 's/" $//g' |\
                while read -r sound_url; do
                    sound_url="$(_url_decode "$sound_url" | sed 's/fbclid=.*$//g')"
                    if ! grep "$sound_url" "$sounds_urls"; then
                        echo "Checking if $sound_url is a playlist or a single song"
                        type="$(youtube-dl -J --flat-playlist "$sound_url" |\
                            jq .extractor | grep -E "playlist|set")"
                        if [ -z "$type" ]; then
                            echo "$sound_url" >> "$sounds_urls"
                            echo "Found a new song : $sound_url"
                        fi
                    fi
                done

                #TODO: Find why set -e crash here ?
                next_urls="$(_match_page "$content")"

                if [ -z "$next_urls" ]; then
                    echo "End of thread"
                    break
                fi

                if [ "$(echo "$next_urls" | wc -l)" = "1" ] && [ -n "$old_url" ]; then
                    echo "End of thread"
                    break
                fi

                next_url="$(echo "$next_urls" | head -n 1)"

                if [ "$next_url" = "$old_url" ]; then
                    echo "This is a one comment page, going to next thread"
                    break
                fi
                old_url="$next_url"
        done
        i="$((i + 1))"
    done < "$threads_urls"

    echo "Finish grabbing sounds"
}

_find_latest_sounds_links() {
    sounds_urls="$1"
    group_id="$2"

    [ -z "$sounds_urls" ] && {
        _panic "No output playlist has been specified"
    }

    [ -z "$group_id" ] && {
        _panic "No group id has been specified"
    }

    threads_urls="$(mktemp)"
    pages_urls="$(mktemp)"

    _find_all_pages_links "$pages_urls" "$threads_urls"
    _find_all_sounds_links "$threads_urls" "$sounds_urls"

    rm "$threads_urls"
    rm "$pages_urls"
}


BASE_URL="https://mbasic.facebook.com"

GROUP_ID=
MAX_PAGES=

[ ! -f cookie.txt ] && _panic "cookie.txt is not found"

mkdir -p "$(pwd)/data"

if [ -n "$3" ]; then
    MAX_PAGES="$3"
else
    MAX_PAGES="10"
fi

case "$1" in
    find_latest_sounds_links)
        GROUP_ID="$2"
        MAX_PAGES="$3"
        output_playlist_path="$4"

        [ -z "$GROUP_ID" ] && _panic "Missing group id"
        [ -z "$output_playlist_path" ] && _panic "Missing output_playlist_path"

        _find_latest_sounds_links "$output_playlist_path" "$GROUP_ID"
        ;;

    find_all_sounds_links)
        _find_all_sounds_links data/threads_urls data/sounds_urls
        ;;

    find_all_pages_links)
        if [ -z "$2" ]; then
            echo "You must specify group id"
            exit 1
        else
            GROUP_ID="$2"
        fi
        _find_all_pages_links data/page_urls data/threads_urls
        ;;

    *)
        echo "Usage: download.sh [find_all_sounds_links | find_all_pages_links | find_latest_sounds_links  ] [group_id] [max_pages] [output_playlist_path]"
        exit 1
esac
