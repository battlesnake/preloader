# Preloader

Use `profile.sh [-u user] program [args...]` to profile an application and
record which files are accessed when the application starts.

Use `preload.sh [dry]` to invoke the preloader.  Specifying `dry` will cause the
script to measure the total payload to preload, but without invoking the
preloader.

Configure an init-script or systemd service to run the `preload.sh` script on
boot.  The preloader is run with `nice`, `ionice`, and a big fat target for the
kernel's OOM killer, so shouldn't cause any issues besides slowing the boot time
somewhat.

If the included `do_preload` binary is not actually included, or if you are not
running on an x64 processor, call `./do_preload.c` to compile the preloader
binary.
