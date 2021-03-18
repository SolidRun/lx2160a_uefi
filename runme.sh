#!/bin/bash
set -e

# DDR_SPEED=2400,2600,2900,3000,3200
# SERDES=8_5_2, 13_5_2, 20_5_2

LINARO_GCC_VERSION="gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu"
IFS='-' read SP1 SP2 SP3 SP4 SP5 <<< ${LINARO_GCC_VERSION}
LINARO_GCC_SV="${SP3::-2}-${SP4}"
GIT_HASH=`git rev-parse --short HEAD`

###############################################################################
# General configurations
###############################################################################

#UEFI_RELEASE=DEBUG
#DDR_SPEED=3200
#SERDES=8_5_2 # 8x10g
#SERDES=13_5_2 # dual 100g
#SERDES=20_5_2 # dual 40g
###############################################################################
# Misc
###############################################################################
if [ "x$DDR_SPEED" == "x" ]; then
	DDR_SPEED=2400
fi
if [ "x$SOC_SPEED" == "x" ]; then
	SOC_SPEED=2000
fi
if [ "x$BUS_SPEED" == "x" ]; then
	BUS_SPEED=700
fi
if [ "x$SERDES" == "x" ]; then
	SERDES=8_5_2
fi
if [ "x$UEFI_RELEASE" == "x" ]; then
	UEFI_RELEASE=RELEASE
fi
if [ "x$BOOT_MODE" == "x" ]; then
	BOOT_MODE=sd
fi
if [ "x$XMP_PROFILE" != "x" ]; then
	XMP_PROFILE="XMP_PROFILE=${XMP_PROFILE}"
fi
if [ "x$X86EMU" != "x" ]; then
	X86EMU="-D X64EMU_ENABLE=TRUE"
fi
if [ "x$AMDGOP" == "x" ]; then
	AMDGOP="-D AARCH64_GOP_ENABLE=TRUE"
fi

ROOTDIR=`pwd`
PARALLEL=$(getconf _NPROCESSORS_ONLN) # Amount of parallel jobs for the builds
SPEED=${SOC_SPEED}_${BUS_SPEED}_${DDR_SPEED}

TOOLS="wget tar git make dd envsubst dtc iasl"

HOST_ARCH=`arch`
if [ "$HOST_ARCH" == "x86_64" ]; then 
export CROSS_COMPILE=$ROOTDIR/build/toolchain/${LINARO_GCC_VERSION}/bin/aarch64-linux-gnu-
export CROSS_COMPILE64=$ROOTDIR/build/toolchain/${LINARO_GCC_VERSION}/bin/aarch64-linux-gnu-
fi
export ARCH=arm64

if [ "x$SERDES" == "x" ]; then
	echo "Please define SERDES configuration"
	exit -1
fi
if [ "x${SERDES:0:3}" == "x13_" ]; then
	DPC=dpc-dual-100g.dtb
	DPL=dpl-eth.dual-100g.19.dtb
fi
if [ "x${SERDES:0:2}" == "x8_" ]; then
	DPC=dpc-8_x_usxgmii.dtb 
	DPL=dpl-eth.8x10g.19.dtb
fi
if [ "x${SERDES:0:2}" == "x4_" ]; then
	DPC=dpc-8_x_usxgmii.dtb
	DPL=dpl-eth.8x10g.19.dtb
fi
if [ "x${SERDES:0:3}" == "x20_" ]; then
	DPC=dpc-dual-40g.dtb
	DPL=dpl-eth.dual-40g.19.dtb
fi

echo "Checking all required tools are installed"

set +e
for i in $TOOLS; do
	TOOL_PATH=`which $i`
	if [ "x$TOOL_PATH" == "x" ]; then
		echo "Tool $i is not installed"
		exit -1
	fi
done
set -e

if [[ ! -d $ROOTDIR/images ]]; then
	mkdir $ROOTDIR/images
fi

if [[ ! -d $ROOTDIR/build/toolchain/${LINARO_GCC_VERSION} && "$HOST_ARCH" == "x86_64" ]]; then
	mkdir -p $ROOTDIR/build/toolchain
	cd $ROOTDIR/build/toolchain
	wget https://releases.linaro.org/components/toolchain/binaries/${LINARO_GCC_SV}/aarch64-linux-gnu/${LINARO_GCC_VERSION}.tar.xz
	tar -xf ${LINARO_GCC_VERSION}.tar.xz --no-same-owner
	rm -f ${LINARO_GCC_VERSION}.tar.xz
fi

echo "Building boot loader"
cd $ROOTDIR

###############################################################################
# submodule init
###############################################################################
if [ "x$INITIALIZE" != "x" ]; then
	git submodule update --init --recursive
	exit
fi

###############################################################################
# clean 
###############################################################################
if [ "x$CLEAN" != "x" ]; then
	rm -rf $ROOTDIR/build/arm-trusted-firmware/build
	rm -rf $ROOTDIR/build/optee_os/out
	rm -rf $ROOTDIR/tianocore/Build
	rm -rf $ROOTDIR/tianocore/Build
	PYTHON_COMMAND=/usr/bin/python3 make -C $ROOTDIR/build/tianocore/edk2/BaseTools
fi

###############################################################################
# building sources
###############################################################################
echo "Building RCW"
cd $ROOTDIR/build/rcw/lx2160acex7
export SP1 SP2 SP3
IFS=_ read SP1 SP2 SP3 <<< $SERDES
if [ "x$SP1" == "4" ]; then
	export SRC1="0"
	export SCL1="0"
	export SPD1="1"
else
	export SRC1="1"
	export SCL1="2"
	export SPD1="1"
fi

envsubst < configs/lx2160a_serdes.def > configs/lx2160a_serdes.rcwi

IFS=_ read CPU SYS MEM <<< $SPEED
export CPU=${CPU::2}
export SYS=$(( 2*${SYS::2} ))
export SYS=${SYS::-1}
export MEM=${MEM::2}

envsubst < configs/lx2160a_timings.def > configs/lx2160a_timings.rcwi

# Always rebuild the rcws to catch timing changes
rm -f rcws/*.bin
make -j${PARALLEL}

echo "Build UEFI"
cd $ROOTDIR/build/tianocore
# set the aarch64-linux-gnu cross compiler to the oldie 4.9 linaro toolchain (UEFI build requirement)
PYTHON_COMMAND=/usr/bin/python3 make -C $ROOTDIR/build/tianocore/edk2/BaseTools
export ARCH=arm
export GCC5_AARCH64_PREFIX=$CROSS_COMPILE
export WORKSPACE=$ROOTDIR/build/tianocore
export PACKAGES_PATH=$WORKSPACE/edk2:$WORKSPACE/edk2-platforms:$WORKSPACE/edk2-non-osi
source  edk2/edksetup.sh

if [ "x$SECURE_BOOT" != "x" ]; then
build -p "edk2-platforms/Platform/SolidRun/LX2160aCex7/LX2160aCex7.dsc" -a AARCH64 -t GCC5 -b ${UEFI_RELEASE} -y build.log -D SECURE_BOOT ${X86EMU} ${AMDGOP} 
export BL33=$ROOTDIR/build/tianocore/Build/LX2160aCex7/${UEFI_RELEASE}_GCC5/FV/LX2160ACEX7_EFI.fd
build -p "edk2-platforms/Platform/SolidRun/StandAloneMm/StandaloneMm.dsc" -a AARCH64 -t GCC5 -b ${UEFI_RELEASE} -y build-mm.log ${X86EMU} ${AMDGOP}
export CFG_STMM_PATH=$ROOTDIR/build/tianocore/Build/NXPMmStandalone/${UEFI_RELEASE}_GCC5/FV/BL32_AP_MM.fd

echo "Build optee_os"
cd $ROOTDIR/build/optee_os
make -j${PARALLEL} CFG_ARM64_core=y PLATFORM=ls-lx2160ardb CFG_SCTLR_ALIGNMENT_CHECK=n CFG_TEE_TA_LOG_LEVEL=0 CFG_WITH_STMM_SP=y
${CROSS_COMPILE}objcopy -v -O binary out/arm-plat-ls/core/tee.elf out/arm-plat-ls/core/tee.bin 
export BL32=$ROOTDIR/build/optee_os/out/arm-plat-ls/core/tee.bin
else
build -p "edk2-platforms/Platform/SolidRun/LX2160aCex7/LX2160aCex7.dsc" -a AARCH64 -t GCC5 -b ${UEFI_RELEASE} -y build.log ${X86EMU} ${AMDGOP}
export BL33=$ROOTDIR/build/tianocore/Build/LX2160aCex7/${UEFI_RELEASE}_GCC5/FV/LX2160ACEX7_EFI.fd

fi

export ARCH=arm64 # While building UEFI ARCH is unset

echo "Building trusted-firmware-a"
cd $ROOTDIR/build/arm-trusted-firmware/

# TF-A is very picky about changing the boot mode and other settings
# and it isn't very big so just remove the build directory regardless
# and rebuild clean each time
rm -rf build

if [ "x$SECURE_BOOT" != "x" ]; then
make PLAT=lx2160acex7 all fip pbl RCW=$ROOTDIR/build/rcw/lx2160acex7/rcws/rcw_lx2160acex7.bin BOOT_MODE=${BOOT_MODE} SPD=opteed ${XMP_PROFILE}
else
make PLAT=lx2160acex7 all fip pbl RCW=$ROOTDIR/build/rcw/lx2160acex7/rcws/rcw_lx2160acex7.bin TRUSTED_BOARD_BOOT=0 GENERATE_COT=0 BOOT_MODE=${BOOT_MODE} SECURE_BOOT=false ${XMP_PROFILE}
fi

cd $ROOTDIR/
if [ "x$SECURE_BOOT" != "x" ]; then
IMG=lx2160acex7_${SPEED}_${SERDES}_${BOOT_MODE}_secure_${GIT_HASH}.img
else
IMG=lx2160acex7_${SPEED}_${SERDES}_${BOOT_MODE}_${GIT_HASH}.img
fi
truncate -s 8M $ROOTDIR/images/${IMG}

# RCW+PBI+BL2 at block 8
if [ "x$BOOT_MODE" == "xflexspi_nor" ]; then
dd if=$ROOTDIR/build/arm-trusted-firmware/build/lx2160acex7/release/bl2_flexspi_nor.pbl of=images/${IMG} bs=512 conv=notrunc
elif [ "x$BOOT_MODE" == "xsd" ]; then
dd if=$ROOTDIR/build/arm-trusted-firmware/build/lx2160acex7/release/bl2_sd.pbl of=images/${IMG} bs=512 seek=8 conv=sparse
fi

# DDR PHY FIP at 0x100
dd if=$ROOTDIR/build/ddr-phy-binary/lx2160a/fip_ddr.bin of=images/${IMG} bs=512 seek=256 conv=notrunc

# FIP (BL31+BL32+BL33) at 0x800
dd if=$ROOTDIR/build/arm-trusted-firmware/build/lx2160acex7/release/fip.bin of=images/${IMG} bs=512 seek=2048 conv=notrunc

echo -e "\r\n\r\nBuilt: images/${IMG}"
