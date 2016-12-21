# rust-cross-libs

Cross-compile the Rust standard library for unsupported targets without a
full bootstrap build.

Latest build:

```
$ rustc -V
rustc 1.15.0-nightly (1c448574b 2016-11-28)
```

Thanks to Kevin Mehall: https://gist.github.com/kevinmehall/16e8b3ea7266b048369d

## Introduction

This guide assumes you are using an x64_86 host to cross-compile the Rust
`std` library to an unsupported target, e.g. ARMv5.

### Using custom targets

While it is not possible to cross-compile Rust for an unsupported target, unless
you hack it, it offers the possibility to use custom targets with `rustc`:

From the [Rust docs](http://doc.rust-lang.org/1.1.0/rustc_back/target/index.html#using-custom-targets):

>
A target triple, as passed via `rustc --target=TRIPLE`, will first be
compared against the list of built-in targets. This is to ease distributing
rustc (no need for configuration files) and also to hold these built-in
targets as immutable and sacred. If `TRIPLE` is not one of the built-in
targets, rustc will check if a file named `TRIPLE` exists. If it does, it
will be loaded as the target configuration. If the file does not exist,
rustc will search each directory in the environment variable
`RUST_TARGET_PATH` for a file named `TRIPLE.json`. The first one found will
be loaded. If no file is found in any of those directories, a fatal error
will be given. `RUST_TARGET_PATH` includes `/etc/rustc` as its last entry,
to be searched by default.

>
Projects defining their own targets should use
`--target=path/to/my-awesome-platform.json` instead of adding to
`RUST_TARGET_PATH`.

Unfortunately, passing the JSON file path to `rustc` instead of using
`RUST_TARGET_PATH` does not work, so the script internally uses
`RUST_TARGET_PATH` to define the target specification.

## Preparation

### Define your custom target

I will use a custom target `armv5te-unknown-linux-musleabi` to build a
cross-compiled *"Hello, World!"* for an ARMv5TE soft-float target. Note that
the provided JSON file defines every possible value you can with the current
Rust nightly version.

### Get Rust sources and binaries

We fetch the Rust sources from github and get the binaries from the latest
snapshot to run on the host, e.g. for x86_64-unknown-linux-gnu:

    $ git clone https://github.com/joerg-krause/rust-cross-libs.git
    $ cd rust-cross-libs
    $ git clone https://github.com/rust-lang/rust rust-git
    $ wget https://static.rust-lang.org/dist/rust-nightly-x86_64-unknown-linux-gnu.tar.gz
    $ tar xf rust-nightly-x86_64-unknown-linux-gnu.tar.gz
    $ rust-nightly-x86_64-unknown-linux-gnu/install.sh --prefix=$PWD/rust

### Define the cross toolchain environment

Define your host triple, e.g.:

    $ export HOST=x86_64-unknown-linux-gnu

Define your target triple, e.g.:

    $ export TARGET=armv5te-unknown-linux-musleabi

Define your cross compiler and linker:

    $ export CC=/usr/local/bin/arm-linux-gcc
    $ export AR=/usr/local/bin/arm-linux-ar

Define the `CFLAGS` to build the compiler-rt and libbacktrace libraries with:

    $ export CFLAGS="-Wall -Os -fPIC -D__arm__ -mfloat-abi=soft"

Adjust these flags depending on your target.

### Run the script

    $ ./rust-cross-libs.sh --rust-prefix=$PWD/rust --rust-git=$PWD/rust-git --target=$PWD/cfg/$TARGET.json
    [..]
    Libraries are in /home/joerg/rust-cross-libs/rust/lib/rustlib/armv5te-unknown-linux-musleabi/lib

Optionally, you can set the optimization level by adding the command line option
`--opt-level` or by setting the environment variable `OPT_LEVEL`, e.g.:

    $ ./rust-cross-libs.sh --rust-prefix=$PWD/rust --rust-git=$PWD/rust-git --target=$PWD/cfg/$TARGET.json --opt-level=s

If not set, the optimization defaults to `2`.

## Cross-compile with Cargo

For cross-compiling with Cargo we need to make sure to link with the target
libraries and not with the host ones. [Buildroot](https://buildroot.org/) is a
great tool for generating embedded Linux system. The `sysroot` directory
from the Buildroot output directory is used for linking with the target
libraries.

To allow using a sysroot directory with Cargo lets create an executable shell
script.

Example for musl based toolchain:

```
$ cat $HOME/arm-unknown-linux-musl-sysroot
#!/bin/bash

SYSROOT=$HOME/buildroot/output/host/usr/arm-buildroot-linux-musleabi/sysroot

/usr/local/bin/arm-linux-gcc --sysroot=$SYSROOT $(echo "$@" | sed 's/-L \/usr\/lib //g')

$ chmod +x $HOME/arm-unknown-linux-musl-sysroot
```

Now we can tell Cargo to use this shell script when linking:

```
$ cat ~/.cargo/config
[target.armv5te-unknown-linux-gnueabi]
linker = "$HOME/arm-unknown-linux-gnueabi-sysroot"
ar = "/usr/local/bin/arm-linux-ar"

[target.armv5te-unknown-linux-musleabi]
linker = "$HOME/arm-unknown-linux-musl-sysroot"
ar = "/usr/local/bin/arm-linux-ar"
```

## Hello, world!

Export the path to your host Rust binaries and libraries as well as the path to
your custom target JSON file:

    $ export PATH=$PWD/rust/bin:$PATH
    $ export LD_LIBRARY_PATH=$PWD/rust/lib
    $ export RUST_TARGET_PATH=$PWD/cfg

Cargo the hello example app:

    $ cargo new --bin hello
    $ cd hello
    $ cargo build --target=$TARGET --release

Check:

    $ file target/$TARGET/release/hello
    target/armv5te-unknown-linux-musleabi/release/hello: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-musl-arm.so.1, not stripped

    $ arm-linux-size target/$TARGET/release/hello
       text	   data	    bss	    dec	    hex	filename
      94629	   3732	    204	  98565	  18105	target/armv5te-unknown-linux-musleabi/release/hello
