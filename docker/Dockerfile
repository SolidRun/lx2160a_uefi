# use debian base
FROM debian:buster-slim

# update
RUN set -e; \
	apt-get update; \
	apt-get -y upgrade; \
	:

RUN apt-get update ; apt-get -y --no-install-recommends install \
	wget make acpica-tools device-tree-compiler xz-utils \
	sudo git gettext-base uuid-dev bc gcc g++ python3 \ 
	libc6-dev libssl-dev python3-distutils ca-certificates

RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.7 1

# build environment
ARG ddr=2400
ENV DDR_SPEED=$ddr
ARG soc=2000
ENV SOC_SPEED=$soc
ARG bus=700
ENV BUS_SPEED=$bus
ARG serdes=8_5_2
ENV SERDES=$serdes
ARG release=RELEASE
ENV UEFI_RELEASE=$release
ARG boot=sd
ENV BOOT_MODE=$boot
ARG xmp_profile=
ENV XMP_PROFILE=$xmp_profile
ARG x86emu=
ENV X86EMU=$x86emu
ARG amdgop=
ENV AMDGOP=$amdgop
ARG clean=
ENV CLEAN=$clean

WORKDIR /work
COPY entry.sh /
ENTRYPOINT ["/bin/sh", "/entry.sh"]
