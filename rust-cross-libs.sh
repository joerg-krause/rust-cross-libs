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
	--panic=*)
	PANIC_STRATEGY="${i#*=}"
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

if [ -z "${HOST}" ]; then
	echo Need to set HOST! Exit.
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

export BUILD=${TOPDIR}/build

export TARGET_JSON=$TARGET_JSON
export TARGET=$(basename $TARGET_JSON .json)

export OPT_LEVEL=${OPT_LEVEL:-"2"}
export PANIC_STRATEGY=${PANIC_STRATEGY:-"abort"}

# Get the number of CPUs, default to 1
N=`getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1`

# Make sure the Rust binary and Rust from git are the same version
RUST_VERSION=$($RUSTC --version | cut -f2 -d'(' | cut -f1 -d' ')
cd ${RUST_GIT}
git checkout ${RUST_VERSION} || (git fetch; git checkout ${RUST_VERSION})
git submodule update --init src/jemalloc \
			    src/libcompiler_builtins \
			    src/liblibc \
			    src/tools/cargo \
			    src/tools/clippy \
			    src/tools/rls \
			    src/tools/rust-installer \
			    src/tools/rustfmt

# Fetch compiler-rt
(cd ${RUST_GIT}/src/libcompiler_builtins &&
	git submodule update --init compiler-rt
)

# Patch libc
(cd ${RUST_GIT}/src/liblibc &&
	git am ${TOPDIR}/patch/liblibc/*
)
# Patch libunwind
(cd ${RUST_GIT}/src/libunwind &&
	git am ${TOPDIR}/patch/libunwind/*
)

# Build libbacktrace
rm -rf ${BUILD}/libbacktrace
mkdir -p $BUILD/libbacktrace
(cd ${BUILD}/libbacktrace &&
	CC="${CC}" \
	AR="${AR}" \
	RANLIB="${AR} s" \
	CFLAGS="${CFLAGS} -fno-stack-protector" \
	"${RUST_GIT}/src/libbacktrace/configure" \
		--build=${TARGET} \
		--host=${HOST}
	make -j${N} INCDIR=${RUST_GIT}/src/libbacktrace
)
mv ${BUILD}/libbacktrace/.libs/libbacktrace.a ${BUILD}

if [ "$PANIC_STRATEGY" = "unwind" ]; then
	export FEATURES="jemalloc backtrace panic_unwind"
else
	export FEATURES="jemalloc"
fi

(cd ${RUST_GIT}/src/libstd &&
	$CARGO clean
	$CARGO build -j${N} --target=${TARGET} --release --features "${FEATURES}"
)

# Install to destination
TARGET_LIB_DIR=${RUSTLIB}/${TARGET}/lib
rm -rf ${TARGET_LIB_DIR}
mkdir -p ${TARGET_LIB_DIR}

cp ${RUST_GIT}/src/target/${TARGET}/release/deps/* ${TARGET_LIB_DIR}

echo "Libraries are in ${TARGET_LIB_DIR}"
