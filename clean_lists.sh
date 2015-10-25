#!/bin/bash

set -euo pipefail

declare -r tmp="$(mktemp)"

cd "$(dirname "$0")"

source "config"

declare -i count=0

function clean_list {
	while read line; do
		if [ "${line:0:1}" == '#' ] || [ -z "${line}" ] || [ -e "${line}" ]; then
			printf -- "%s\n" "${line}"
		else
			printf >&2 -- " * %s\n" "${line}"
			count+=1
		fi
	done
}

for list in "${list_dir}"/*.list; do
	clean_list < "${list}" > "${tmp}"
	cat "${tmp}" > "${list}"
done

printf -- "%d missing files removed from preload lists\n" "${count}"

rm -f -- "${tmp}"
