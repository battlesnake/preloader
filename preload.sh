#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")"

source "config"

if uname -r | grep -qE '-server$'; then
	printf >&2 -- "Not preloading as we're running the server kernel\n"
	exit
fi

function get_payload {
	cat -- "${list_dir}"/*.list | grep -vE '^#' | sort -u
}

function calc_size {
	local -i total_size=0
	local -i count=0
	while read path; do
		if [ -e "${path}" ]; then
			local -i size="$(stat -c%s "${path}")"
			total_size+=size
			count+=1
		fi
	done < "${full_list}"
	printf -- "%d files, %dMB\n" "${count}" "$((total_size / 1048576))"
}

declare -r mode="${1:-}"

function rm_full_list {
	rm -f -- "${full_list}"
}
declare -r full_list="$(mktemp)"
trap rm_full_list EXIT
get_payload > "${full_list}"

if [ "${mode}" == "debug" ] || [ "${mode}" == "dry" ]; then
	calc_size
fi

if [ "${mode}" != "dry" ]; then
	printf -- "Preloading\n"
	declare -r arch="$(uname -m)"
	killall -q do_preload || true

	ionice -c 3 \
	nice -n 20 \
	./do_preload < "${full_list}" &
	declare -ri pid="$!"

	echo '1000' > "/proc/${pid}/oom_score_adj"
	wait "${pid}"
fi
