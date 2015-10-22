#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/config"

declare run_as_user=

while true; do
	case "$1" in
	-u) shift; run_as_user="$1"; shift;;
	--) shift; break;;
	*) break;;
	esac
done

declare -r tmpfile="$(mktemp)"
declare -r tmpfile2="$(mktemp)"
function clean_tmp {
	rm -f -- "${tmpfile}" "${tmpfile2}"
}
trap clean_tmp EXIT

if [ "${run_as_user}" ]; then
	echo "Running as user \"${run_as_user}\"..."
	strace -f -e trace=open,access sudo sudo -u "${run_as_user}" "$@" 2> "${tmpfile}" &
else
	strace -f -e trace=open,access "$@" 2> "${tmpfile}" &
fi
declare -ri strace_pid=$!

echo "Press [ENTER] when done"
read
kill "${strace_pid}" &>/dev/null || true

perl <(glue_prog) "${tmpfile}" \
| xargs -I{} readlink -m {} \
| sort -u \
> "${tmpfile2}"

declare base="$(basename "$1")"

declare -i total=0
declare -i count=0
while read file; do
	if [ -d "${file}" ]; then
#		printf >&2 -- "Excluding directory %s\n" "${file}"
		continue
	fi
	if ! [ -e "${file}" ]; then
#		printf >&2 -- "Excluding transient file %s\n" "${file}"
		continue
	fi
	declare -i size="$(stat -c%s "${file}" 2>/dev/null)"
	if (( size > max_file_size )); then
		printf >&2 -- "Excluding large file %s\n" "${file}"
		continue
	fi
	total+=size
	count+=1
done < "${tmpfile2}"

if (( count > 0 )); then
	mv -- "${tmpfile2}" "${base_dir}/lists/${base}.list"
fi
printf >&2 -- "%d files, %dMB total\n" "${count}" "$((total / 1048576))"
