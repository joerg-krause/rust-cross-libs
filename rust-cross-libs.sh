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
    RUST_GIT=$(readlink -f "${i#*=}")
    shift
    ;;
    --target=*)
    export TARGET_JSON=$(readlink -f "${i#*=}")
    shift
    ;;
    *)
        # unknown option
    ;;
esac
done

# Sanity-check args
if [ ! -f ${RUST_PREFIX}/bin/rustc ]; then
    echo ${RUST_PREFIX}/bin/rustc not found! Exit.
    exit 1
fi

if [ ! -d ${RUST_GIT}/.git ]; then
    echo No Rust git repository found! Exit.
    exit 1
fi

export TOPDIR=${PWD}
export PATH=${RUST_PREFIX}/bin:${PATH}
export LD_LIBRARY_PATH=${RUST_PREFIX}/lib
export RUSTLIB=${RUST_PREFIX}/lib/rustlib
export RUSTC=${RUST_PREFIX}/bin/rustc
export RUST_TARGET_PATH=$(dirname ${TARGET_JSON})

export FILENAME_EXTRA=$(${RUSTC} --version | cut -d' ' -f 2 | tr -d $'\n' | md5sum | cut -c 1-8)
export BUILD=${TOPDIR}/build

export TARGET_JSON=$TARGET_JSON
export TARGET=$(basename $TARGET_JSON .json)

# Make sure the Rust binary and Rust from git are the same version
RUST_VERSION=$($RUSTC --version | cut -f2 -d'(' | cut -f1 -d' ')
cd ${RUST_GIT}
git checkout ${RUST_VERSION} || (git fetch; git checkout ${RUST_VERSION})
git submodule update --init src/compiler-rt src/liblibc

# Patch libc
(cd src/liblibc &&
	git am ${TOPDIR}/patch/*
)

# Get the number of CPUs, default to 1
N=`getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1`

# Build compiler-rt
rm -rf ${BUILD}/comprt
mkdir -p ${BUILD}/comprt
(cd ${BUILD}/comprt &&
	cmake ${RUST_GIT}/src/compiler-rt \
		-DCMAKE_BUILD_TYPE=Release \
		-DCOMPILER_RT_DEFAULT_TARGET_TRIPLE=${TARGET} \
		-DCOMPILER_RT_BUILD_SANITIZERS=OFF \
		-DCOMPILER_RT_BUILD_EMUTLS=OFF \
		-DCMAKE_C_COMPILER="${CC}" \
		-G"Unix Makefiles"
	cmake --build "${BUILD}/comprt" \
		--target clang_rt.builtins-arm \
		--config Release
)
mv ${BUILD}/comprt/lib/linux/libclang_rt.builtins-arm.a ${BUILD}/libcompiler-rt.a

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

# Build crates
# Use the rust build system to obtain the target crates in dependency order.
# TODO: use the makefile to build the C libs above

cat > "${BUILD}/hack.mk" <<'EOF'
RUSTC_OPTS = -C opt-level=2 --target=$(TARGET) \
      -L $(BUILD) --out-dir=$(BUILD) -C extra-filename=-$(FILENAME_EXTRA)

define RUST_CRATE_DEPS
RUST_DEPS_$(1) := $$(filter-out native:%,$$(DEPS_$(1)))
endef

define BUILD_CRATE
$(1): $(RUST_DEPS_$(1))
	$(RUSTC) $(CRATEFILE_$(1)) $(RUSTC_OPTS) $(RUSTFLAGS_$(1))

.PHONY: $(1)
endef

$(foreach crate,$(CRATES),$(eval $(call RUST_CRATE_DEPS,$(crate))))
$(foreach crate,$(CRATES),$(eval $(call BUILD_CRATE,$(crate))))

EOF

DEPS_core=
DEPS_alloc="core libc alloc_system"
DEPS_alloc_system="core libc"
DEPS_collections="core alloc rustc_unicode"
DEPS_libc="core"
DEPS_rand="core"
DEPS_rustc_bitflags="core"
DEPS_rustc_unicode="core"
DEPS_panic_abort="libc alloc"
DEPS_panic_unwind="libc alloc unwind"
DEPS_unwind="libc"

DEPS_std="core libc rand alloc collections rustc_unicode alloc_system panic_abort panic_unwind unwind"

make -j${N} -f mk/util.mk -f mk/crates.mk -f "${BUILD}/hack.mk" std CFG_DISABLE_JEMALLOC=1

# Install to destination
TARGET_LIB_DIR=${RUSTLIB}/${TARGET}/lib
rm -rf ${TARGET_LIB_DIR}
mkdir -p ${TARGET_LIB_DIR}
mv ${BUILD}/*.rlib ${BUILD}/*.a ${TARGET_LIB_DIR}

echo "Libraries are in ${TARGET_LIB_DIR}"
