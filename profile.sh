#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/config"

declare run_as_user=
declare profile_name=
declare -i run_in_foreground=0

while true; do
	case "$1" in
	-u) shift; run_as_user="$1";;
	-n) shift; profile_name="$1";;
	-f) run_in_foreground=1;;
	--) shift; break;;
	*) break;;
	esac
	shift
done

if [ -z "${profile_name}" ]; then
	profile_name="$(basename "$1")"
fi

declare -r list_file="${base_dir}/lists/${profile_name}.list"

declare -r tmpfile="$(mktemp)"
declare -r tmpfile2="$(mktemp)"
function clean_tmp {
	rm -f -- "${tmpfile}" "${tmpfile2}"
}
trap clean_tmp EXIT

declare -ra args=( "$@" )

# Run the program with strace
if (( run_in_foreground )); then
	echo "Running in foreground"
	if [ "${run_as_user}" ]; then
		echo "Running as user \"${run_as_user}\"..."
		strace -f -e trace=open,access sudo sudo -u "${run_as_user}" "${args[@]}" 2> "${tmpfile}" || true
	else
		strace -f -e trace=open,access "${args[@]}" 2> "${tmpfile}" || true
	fi
else
	echo "Running in background"
	if [ "${run_as_user}" ]; then
		echo "Running as user \"${run_as_user}\"..."
		strace -f -e trace=open,access sudo sudo -u "${run_as_user}" "${args[@]}" 2> "${tmpfile}" &
	else
		strace -f -e trace=open,access "${args[@]}" 2> "${tmpfile}" &
	fi
	declare -ri strace_pid=$!
	echo "Press <ENTER> when program has loaded (program will be killed)"
	read
	kill "${strace_pid}" &>/dev/null || true
fi

{
# Store command line in a comment
	printf -- "#"
	for arg in "${args[@]}"; do
		printf -- " '"
		printf -- "%s" "${arg}" | sed -e "s/'/'\\''/g"
		printf -- "'"
	done
	printf -- "\n"
# Build file list from strace output, storing symlinks and their target, in case the target changes (e.g. libs)
	perl <(glue_prog) "${tmpfile}" | xargs -I{} sh -c 'echo {}; readlink -m {}' | sort -u
} > "${tmpfile2}"

# Filter list
while read file; do
	if [ "${file:0:1}" == "#" ]; then
		true
	elif [ -d "${file}" ]; then
#		printf >&2 -- "Excluding directory %s\n" "${file}"
		continue
	elif ! [ -e "${file}" ]; then
#		printf >&2 -- "Excluding transient file %s\n" "${file}"
		continue
	fi
	declare -i size="$(stat -c%s "${file}" 2>/dev/null)"
	if (( size > max_file_size )); then
		printf >&2 -- "Excluding large file %s\n" "${file}"
		printf -- "# %s\n" "${file}"
		continue
	fi
	printf -- "%s\n" "${file}"
done < "${tmpfile2}" > "${tmpfile}"

# Calculate payload size, avoiding duplicates caused by symlinks
declare -i total=0
declare -i count=0
while read file; do
	if [ "${file:0:1}" == "#" ]; then
		continue
	fi
	declare -i size="$(stat -c%s "${file}" 2>/dev/null)"
	total+=size
	count+=1
done < <(<"${tmpfile}" xargs -I{} readlink -m {} | sort -u)

# Don't bother storing list if the payload is empty
if (( count > 0 )); then
	mv -- "${tmpfile}" "${list_file}"
	chmod 644 "${list_file}"
else
	rm -f -- "${list_file}"
fi

printf >&2 -- "%d files, %dMB total\n" "${count}" "$((total / 1048576))"
