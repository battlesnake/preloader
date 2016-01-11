# Preloader

Use `profile.sh [-n name] [-f] [-u user] program [args...]` to profile an application and record which files are accessed when the application starts.

The `-f` option runs the program synchronously, necessary for interactive programs (e.g. vim).  The `-u` option specifies which user to run the program as.  The `-n` option allows one to specify the name of the profile, instead of the default which is `basename` of `program`.

Use `preload.sh [dry]` to invoke the preloader.  Specifying `dry` will cause the script to measure the total payload to preload, but without invoking the preloader.

Configure an init-script or systemd service to run the `preload.sh` script on boot.  The preloader is run with `nice`, `ionice`, and a big fat target for the kernel's OOM killer, so shouldn't cause any issues besides slowing the boot time somewhat.

If the included `do_preload` binary is not actually included, or if you are not running on an x64 processor, call `./do_preload.c` to compile the preloader binary.

Note that if you want to profile Chromium, you must disable the setuid-sandbox like so:

	./profile.sh -f -n chromium chromium --disable-setuid-sandbox
