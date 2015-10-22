#if 0
set -euo pipefail
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
#include <signal.h>

struct t_mapping
{
	int fd;
	void *ptr;
	size_t size;
};
typedef struct t_mapping mapping;

mapping *ptrs = 0;
size_t n_ptrs = 0;
size_t c_ptrs = 0;

void push_ptr(int fd, void *ptr, size_t size)
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
	this->fd = fd;
	this->ptr = ptr;
	this->size = size;
}

int preload(char *path)
{
	int file = open(path, O_RDONLY);
	struct stat statrec;
	if (file < 0) {
		return 1;
	}
	if (fstat(file, &statrec)) {
		close(file);
		return 2;
	}
	void *map = mmap(NULL, statrec.st_size, PROT_READ | PROT_EXEC,
		MAP_SHARED | MAP_LOCKED | MAP_POPULATE, file, 0);
	if (map == MAP_FAILED) {
		close(file);
		return 3;
	}
	push_ptr(file, map, statrec.st_size);
	return 0;
}

void unload()
{
	for (size_t i = 0; i < n_ptrs; i++) {
		munmap(ptrs[i].ptr, ptrs[i].size);
		close(ptrs[i].fd);
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

	char line[linebuf];
	while (!end && fgets(line, linebuf, stdin)) {
		/* \n -> 0 */
		line[strlen(line) - 1] = 0;
		if (preload(line)) {
			fprintf(stderr, "Failed to preload '%s'\n", line);
		} else {
			fprintf(stderr, "Preloaded '%s'\n", line);
		}
	}

	fprintf(stderr, "Done\n");

	while (!end) {
		sleep(86400);
	}

	return 0;
}
