#if 0
set -euo pipefail
rm -f do_preload
gcc -O0 -g -mtune=generic -Wall -fstack-protector-all "$0" -o do_preload
echo 'Compiled!'
exit
#endif

#include <stdlib.h>
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/errno.h>
#include <signal.h>

struct t_mapping
{
	void *ptr;
	size_t size;
};
typedef struct t_mapping mapping;

mapping *ptrs = 0;
size_t n_ptrs = 0;
size_t c_ptrs = 0;

void push_ptr(void *ptr, size_t size)
{
	size_t alloc_by = 256;
	if (ptrs == 0) {
		ptrs = (mapping *) malloc(sizeof(mapping) * alloc_by);
		c_ptrs = alloc_by;
	} else if (n_ptrs == c_ptrs) {
		ptrs = (mapping *) realloc(ptrs, sizeof(mapping) * (c_ptrs + alloc_by));
		c_ptrs += alloc_by;
	}
	mapping *this = &ptrs[n_ptrs++];
	this->ptr = ptr;
	this->size = size;
}

void print_mlock_error(char *path, int code)
{
	char *error;
	switch (code) {
	case ENOMEM:
		error = "Cannot lock more pages, limit reached";
		break;
	case EPERM:
		error = "Required permission missing";
		break;
	case EAGAIN:
		error = "Failed to lock entire range";
		break;
	case EINVAL:
		error = "Invalid parameter to mlock";
		break;
	default:
		error = "Unknown error";
		break;
	}
	fprintf(stderr, "Failed to lock \"%s\": %s (%d)\n", path, error, code);
}

int preload(char *path, size_t *size)
{
	int file = open(path, O_RDONLY);
	struct stat statrec;
	if (file < 0) {
		fprintf(stderr, "Failed to open file \"%s\" (%d)\n", path, errno);
		return 1;
	}
	if (fstat(file, &statrec) != 0) {
		close(file);
		fprintf(stderr, "Failed to stat file \"%s\" (%d)\n", path, errno);
		return 2;
	}
	size_t length = statrec.st_size;
	if (length == 0) {
		close(file);
		fprintf(stderr, "Skipping empty file \"%s\"\n", path);
		return 0;
	}
	void *map = mmap(NULL, length, PROT_READ | PROT_EXEC,
		MAP_SHARED, file, 0);
	if (map == MAP_FAILED) {
		close(file);
		fprintf(stderr, "Failed to map file \"%s\" (%d)\n", path, errno);
		return 3;
	}
	int mlock_error = mlock(map, length);
	if (mlock_error != 0) {
		close(file);
		print_mlock_error(path, errno);
		return 4;
	}
	close(file);
	push_ptr(map, length);
	*size = length;
	return 0;
}

void unload()
{
	for (size_t i = 0; i < n_ptrs; i++) {
		munmap(ptrs[i].ptr, ptrs[i].size);
	}
}

#define linebuf 4096

volatile sig_atomic_t end = 0;

void sigterm(int signum)
{
	end = 1;
}

int main(int argc, char *argv[])
{
	struct sigaction action;
	memset(&action, 0, sizeof(action));
	action.sa_handler = sigterm;
	sigaction(SIGTERM, &action, NULL);
	sigaction(SIGINT, &action, NULL);

	int verbose = 0;
	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "-v") == 0) {
			verbose = 1;
		}
	}

	size_t total = 0;
	unsigned long attempted = 0;
	unsigned long loaded = 0;

	char line[linebuf];
	while (!end && fgets(line, linebuf, stdin)) {
		/* \n -> 0 */
		line[strlen(line) - 1] = 0;
		size_t size;
		if (preload(line, &size) == 0) {
			if (verbose) {
				fprintf(stderr, "Preloaded '%s'\n", line);
			}
			total += size;
			loaded++;
		}
		attempted++;
		/*
		 * In case the active IO scheduler doesn't already make us yield
		 * to other processes
		 */
		usleep(1000);
	}

	fprintf(stderr, "Done, preloaded %lu/%lu files (%lluMB)\n", loaded, attempted, (long long unsigned int) (total >> 20));

	while (!end) {
		sleep(-1);
	}

	fprintf(stderr, "Unloading\n");
	unload();
	fprintf(stderr, "Unloaded\n");

	return 0;
}
