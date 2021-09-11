# SolidRun's LX2160A COM express type 7 UEFI build

## Build with host tools
Simply running `INITIALIZE=1 ./runme.sh` then `./runme.sh` will check for required tools, clone and build images and place results in images/ directory.

## Build with docker or podman
```
docker build -t lx2160a_uefi docker/
docker run -v "$PWD":/work:Z --rm -i -t lx2160a_uefi build
```

You can specify build variables with the -e option
```
docker run -e SOC_SPEED=2200 -e BUS_SPEED=800 -e DDR_SPEED=3000 -e XMP_PROFILE=1 -v "$PWD":/work:Z --rm -i -t lx2160a_uefi build
```
