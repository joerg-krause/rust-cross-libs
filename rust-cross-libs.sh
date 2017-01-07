#!/bin/bash

set -e

# Parse args
for i in "$@"
do
case $i in
	--rust-prefix=*)
	RUST_PREFIX=$(readlink -f "${i#*=}")
	shift
	;;
	--rust-git=*)
	export RUST_GIT=$(readlink -f "${i#*=}")
	shift
	;;
	--target=*)
	export TARGET_JSON=$(readlink -f "${i#*=}")
	shift
	;;
	--opt-level=*)
	OPT_LEVEL="${i#*=}"
	shift
	;;
	*)
	# unknown option
	;;
esac
done

# Sanity-check args
if [ ! -f "${RUST_PREFIX}"/bin/rustc ]; then
	echo "${RUST_PREFIX}"/bin/rustc not found! Exit.
	exit 1
fi

if [ ! -d "${RUST_GIT}"/.git ]; then
	echo No Rust git repository found! Exit.
	exit 1
fi

if [ -z "${TARGET}" ]; then
	echo Need to set TARGET! Exit.
	exit 1
fi

if [ -z "${CC}" ]; then
	echo Need to set CC! Exit.
	exit 1
fi

if [ -z "${AR}" ]; then
	echo Need to set AR! Exit.
	exit 1
fi

if [ -z "${CFLAGS}" ]; then
	echo Need to set CFLAGS! Exit.
	exit 1
fi

export TOPDIR=${PWD}
export RUSTLIB=${RUST_PREFIX}/lib/rustlib
export RUSTC=${RUST_PREFIX}/bin/rustc
export CARGO=${RUST_PREFIX}/bin/cargo

export TARGET_JSON=$TARGET_JSON
export TARGET=$(basename $TARGET_JSON .json)

export OPT_LEVEL=${OPT_LEVEL:-"2"}

# Get the number of CPUs, default to 1
N=`getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1`

# Make sure the Rust binary and Rust from git are the same version
RUST_VERSION=$($RUSTC --version | cut -f2 -d'(' | cut -f1 -d' ')
cd ${RUST_GIT}
git checkout ${RUST_VERSION} || (git fetch; git checkout ${RUST_VERSION})
git submodule update --init src/compiler-rt \
			    src/jemalloc \
			    src/liblibc

# Patch libc
(cd ${RUST_GIT}/src/liblibc &&
	git am ${TOPDIR}/patch/*
)

(cd ${RUST_GIT}/src/libpanic_unwind &&
	$CARGO build -j${N} --target=${TARGET} --release
)

(cd ${RUST_GIT}/src/libstd &&
	$CARGO build -j${N} --target=${TARGET} --release
)

# Install to destination
TARGET_LIB_DIR=${RUSTLIB}/${TARGET}/lib
rm -rf ${TARGET_LIB_DIR}
mkdir -p ${TARGET_LIB_DIR}

cp ${RUST_GIT}/src/target/${TARGET}/release/deps/* ${TARGET_LIB_DIR}

echo "Libraries are in ${TARGET_LIB_DIR}"
