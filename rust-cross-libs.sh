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
export PATH=${RUST_PREFIX}/bin:${PATH}
export LD_LIBRARY_PATH=${RUST_PREFIX}/lib
export RUSTLIB=${RUST_PREFIX}/lib/rustlib
export RUSTC=${RUST_PREFIX}/bin/rustc
export RUST_TARGET_PATH=$(dirname ${TARGET_JSON})

export FILENAME_EXTRA=$(${RUSTC} --version | cut -d' ' -f 2 | tr -d $'\n' | md5sum | cut -c 1-8)
export BUILD=${TOPDIR}/build

export TARGET_JSON=$TARGET_JSON
export TARGET=$(basename $TARGET_JSON .json)

export OPT_LEVEL=${OPT_LEVEL:-"2"}

rm -rf ${BUILD}
mkdir -p ${BUILD}

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
cat > "${BUILD}/rt.mk" <<'EOF'
# GENERIC_SOURCES in CMakeLists.txt
COMPRT_OBJS := \
  absvdi2.o \
  absvsi2.o \
  adddf3.o \
  addsf3.o \
  addvdi3.o \
  addvsi3.o \
  apple_versioning.o \
  ashldi3.o \
  ashrdi3.o \
  clear_cache.o \
  clzdi2.o \
  clzsi2.o \
  cmpdi2.o \
  comparedf2.o \
  comparesf2.o \
  ctzdi2.o \
  ctzsi2.o \
  divdc3.o \
  divdf3.o \
  divdi3.o \
  divmoddi4.o \
  divmodsi4.o \
  divsc3.o \
  divsf3.o \
  divsi3.o \
  divxc3.o \
  extendsfdf2.o \
  extendhfsf2.o \
  ffsdi2.o \
  fixdfdi.o \
  fixdfsi.o \
  fixsfdi.o \
  fixsfsi.o \
  fixunsdfdi.o \
  fixunsdfsi.o \
  fixunssfdi.o \
  fixunssfsi.o \
  fixunsxfdi.o \
  fixunsxfsi.o \
  fixxfdi.o \
  floatdidf.o \
  floatdisf.o \
  floatdixf.o \
  floatsidf.o \
  floatsisf.o \
  floatundidf.o \
  floatundisf.o \
  floatundixf.o \
  floatunsidf.o \
  floatunsisf.o \
  int_util.o \
  lshrdi3.o \
  moddi3.o \
  modsi3.o \
  muldc3.o \
  muldf3.o \
  muldi3.o \
  mulodi4.o \
  mulosi4.o \
  muloti4.o \
  mulsc3.o \
  mulsf3.o \
  mulvdi3.o \
  mulvsi3.o \
  mulxc3.o \
  negdf2.o \
  negdi2.o \
  negsf2.o \
  negvdi2.o \
  negvsi2.o \
  paritydi2.o \
  paritysi2.o \
  popcountdi2.o \
  popcountsi2.o \
  powidf2.o \
  powisf2.o \
  powixf2.o \
  subdf3.o \
  subsf3.o \
  subvdi3.o \
  subvsi3.o \
  truncdfhf2.o \
  truncdfsf2.o \
  truncsfhf2.o \
  ucmpdi2.o \
  udivdi3.o \
  udivmoddi4.o \
  udivmodsi4.o \
  udivsi3.o \
  umoddi3.o \
  umodsi3.o

ifeq ($$(findstring ios,$(TARGET)),)
COMPRT_OBJS += \
  absvti2.o \
  addtf3.o \
  addvti3.o \
  ashlti3.o \
  ashrti3.o \
  clzti2.o \
  cmpti2.o \
  ctzti2.o \
  divtf3.o \
  divti3.o \
  ffsti2.o \
  fixdfti.o \
  fixsfti.o \
  fixunsdfti.o \
  fixunssfti.o \
  fixunsxfti.o \
  fixxfti.o \
  floattidf.o \
  floattisf.o \
  floattixf.o \
  floatuntidf.o \
  floatuntisf.o \
  floatuntixf.o \
  lshrti3.o \
  modti3.o \
  multf3.o \
  multi3.o \
  mulvti3.o \
  negti2.o \
  negvti2.o \
  parityti2.o \
  popcountti2.o \
  powitf2.o \
  subtf3.o \
  subvti3.o \
  trampoline_setup.o \
  ucmpti2.o \
  udivmodti4.o \
  udivti3.o \
  umodti3.o
endif

ifeq ($$(findstring apple,$(TARGET)),apple)
COMPRT_OBJS +=  \
	    atomic_flag_clear.o \
	    atomic_flag_clear_explicit.o \
	    atomic_flag_test_and_set.o \
	    atomic_flag_test_and_set_explicit.o \
	    atomic_signal_fence.o \
	    atomic_thread_fence.o
endif


ifeq ($$(findstring windows,$(TARGET)),)
COMPRT_OBJS += emutls.o
endif

ifeq ($$(findstring msvc,$(TARGET)),)

ifeq ($$(findstring freebsd,$(TARGET)),)
COMPRT_OBJS += gcc_personality_v0.o
endif

COMPRT_OBJS += emutls.o

ifeq ($$(findstring x86_64,$(TARGET)),x86_64)
COMPRT_OBJS += \
      x86_64/chkstk.o \
      x86_64/chkstk2.o \
      x86_64/floatdidf.o \
      x86_64/floatdisf.o \
      x86_64/floatdixf.o \
      x86_64/floatundidf.o \
      x86_64/floatundisf.o \
      x86_64/floatundixf.o
endif

ifeq ($$(findstring i686,$$(patsubts i%86,i686,$(TARGET))),i686)
COMPRT_OBJS += \
      i386/ashldi3.o \
      i386/ashrdi3.o \
      i386/chkstk.o \
      i386/chkstk2.o \
      i386/divdi3.o \
      i386/floatdidf.o \
      i386/floatdisf.o \
      i386/floatdixf.o \
      i386/floatundidf.o \
      i386/floatundisf.o \
      i386/floatundixf.o \
      i386/lshrdi3.o \
      i386/moddi3.o \
      i386/muldi3.o \
      i386/udivdi3.o \
      i386/umoddi3.o
endif

else

ifeq ($$(findstring x86_64,$(TARGET)),x86_64)
COMPRT_OBJS += \
      x86_64/floatdidf.o \
      x86_64/floatdisf.o \
      x86_64/floatdixf.o
endif

endif

# Generic ARM sources, nothing compiles on iOS though
ifeq ($$(findstring arm,$(TARGET)),arm)
ifeq ($$(findstring ios,$(TARGET)),)
COMPRT_OBJS += \
  arm/aeabi_cdcmp.o \
  arm/aeabi_cdcmpeq_check_nan.o \
  arm/aeabi_cfcmp.o \
  arm/aeabi_cfcmpeq_check_nan.o \
  arm/aeabi_dcmp.o \
  arm/aeabi_div0.o \
  arm/aeabi_drsub.o \
  arm/aeabi_fcmp.o \
  arm/aeabi_frsub.o \
  arm/aeabi_idivmod.o \
  arm/aeabi_ldivmod.o \
  arm/aeabi_memcmp.o \
  arm/aeabi_memcpy.o \
  arm/aeabi_memmove.o \
  arm/aeabi_memset.o \
  arm/aeabi_uidivmod.o \
  arm/aeabi_uldivmod.o \
  arm/bswapdi2.o \
  arm/bswapsi2.o \
  arm/clzdi2.o \
  arm/clzsi2.o \
  arm/comparesf2.o \
  arm/divmodsi4.o \
  arm/divsi3.o \
  arm/modsi3.o \
  arm/switch16.o \
  arm/switch32.o \
  arm/switch8.o \
  arm/switchu8.o \
  arm/sync_synchronize.o \
  arm/udivmodsi4.o \
  arm/udivsi3.o \
  arm/umodsi3.o
endif
endif

# Thumb sources
ifeq ($$(findstring armv7,$(TARGET)),armv7)
COMPRT_OBJS += \
  arm/sync_fetch_and_add_4.o \
  arm/sync_fetch_and_add_8.o \
  arm/sync_fetch_and_and_4.o \
  arm/sync_fetch_and_and_8.o \
  arm/sync_fetch_and_max_4.o \
  arm/sync_fetch_and_max_8.o \
  arm/sync_fetch_and_min_4.o \
  arm/sync_fetch_and_min_8.o \
  arm/sync_fetch_and_nand_4.o \
  arm/sync_fetch_and_nand_8.o \
  arm/sync_fetch_and_or_4.o \
  arm/sync_fetch_and_or_8.o \
  arm/sync_fetch_and_sub_4.o \
  arm/sync_fetch_and_sub_8.o \
  arm/sync_fetch_and_umax_4.o \
  arm/sync_fetch_and_umax_8.o \
  arm/sync_fetch_and_umin_4.o \
  arm/sync_fetch_and_umin_8.o \
  arm/sync_fetch_and_xor_4.o \
  arm/sync_fetch_and_xor_8.o
endif

# VFP sources
ifeq ($$(findstring eabihf,$(TARGET)),eabihf)
COMPRT_OBJS += \
  arm/adddf3vfp.o \
  arm/addsf3vfp.o \
  arm/divdf3vfp.o \
  arm/divsf3vfp.o \
  arm/eqdf2vfp.o \
  arm/eqsf2vfp.o \
  arm/extendsfdf2vfp.o \
  arm/fixdfsivfp.o \
  arm/fixsfsivfp.o \
  arm/fixunsdfsivfp.o \
  arm/fixunssfsivfp.o \
  arm/floatsidfvfp.o \
  arm/floatsisfvfp.o \
  arm/floatunssidfvfp.o \
  arm/floatunssisfvfp.o \
  arm/gedf2vfp.o \
  arm/gesf2vfp.o \
  arm/gtdf2vfp.o \
  arm/gtsf2vfp.o \
  arm/ledf2vfp.o \
  arm/lesf2vfp.o \
  arm/ltdf2vfp.o \
  arm/ltsf2vfp.o \
  arm/muldf3vfp.o \
  arm/mulsf3vfp.o \
  arm/negdf2vfp.o \
  arm/negsf2vfp.o \
  arm/nedf2vfp.o \
  arm/nesf2vfp.o \
  arm/restore_vfp_d8_d15_regs.o \
  arm/save_vfp_d8_d15_regs.o \
  arm/subdf3vfp.o \
  arm/subsf3vfp.o \
  arm/truncdfsf2vfp.o \
  arm/unorddf2vfp.o \
  arm/unordsf2vfp.o
endif

ifeq ($$(findstring aarch64,$(TARGET)),aarch64)
COMPRT_OBJS += \
  comparetf2.o \
  extenddftf2.o \
  extendsftf2.o \
  fixtfdi.o \
  fixtfsi.o \
  fixtfti.o \
  fixunstfdi.o \
  fixunstfsi.o \
  fixunstfti.o \
  floatditf.o \
  floatsitf.o \
  floatunditf.o \
  floatunsitf.o \
  multc3.o \
  trunctfdf2.o \
  trunctfsf2.o
endif

CFLAGS += -fno-builtin -fvisibility=hidden -fomit-frame-pointer -ffreestanding

RT_OUTPUT_DIR := $(BUILD)/rt
COMPRT_BUILD_DIR := $(RT_OUTPUT_DIR)/compiler-rt
COMPRT_OBJS := $(COMPRT_OBJS:%=$(COMPRT_BUILD_DIR)/%)

$(COMPRT_BUILD_DIR)/%.o: $(RUST_GIT)/src/compiler-rt/lib/builtins/%.c
	@mkdir -p $(@D)
	@$(call E, compile: $@)
	$(CC) $(CFLAGS) $< -c -o $@

$(COMPRT_BUILD_DIR)/%.o: $(RUST_GIT)/src/compiler-rt/lib/builtins/%.S
	@mkdir -p $(@D)
	@$(call E, compile: $@)
	$(CC) $(CFLAGS) $< -c -o $@

compiler-rt: $(COMPRT_OBJS)
	@$(call E, link: $@)
	$(AR) crus $(BUILD)/libcompiler-rt.a $(COMPRT_OBJS)

.PHONY: compiler-rt

EOF

make -j${N} -f mk/util.mk -f "${BUILD}/rt.mk" compiler-rt

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
RUSTC_OPTS = -C opt-level=$(OPT_LEVEL) --target=$(TARGET) \
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

TARGET_LIB_DIR=${RUSTLIB}/${TARGET}/lib
rm -rf ${TARGET_LIB_DIR}
mkdir -p ${TARGET_LIB_DIR}

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
mv ${BUILD}/*.rlib ${BUILD}/*.a ${TARGET_LIB_DIR}

echo "Libraries are in ${TARGET_LIB_DIR}"
