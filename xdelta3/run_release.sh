#!/bin/bash

# Run from the source dir.
SRCDIR=${PWD}

# TODO replace w/ wget
LZMA="xz-5.2.1"
LZMA_FILE="${SRCDIR}/../${LZMA}.tar.xz"

MAKEFLAGS="-j 10"

BUILDDIR=${SRCDIR}/build
LZMASRC=${BUILDDIR}/${LZMA}

MINGW_CFLAGS="-DEXTERNAL_COMPRESSION=0 -DVCDIFF_TOOLS=0"
MINGW_CFLAGS="${MINGW_CFLAGS} -DXD3_WIN32=1 -DSHELL_TESTS=0"

MYOS=`uname`
DATE=`date`

CLEAN=""

LINUXTGTS=""
LINUXTEST1=""
LINUXTEST2=""

WINTGTS=""
WINTEST1=""
WINTEST2=""

OSXTGTS=""
OSXTEST1=""
OSXTEST2=""

TMP="${TMP}"
if [ "${TMP}" == "" ]; then
    TMP="${TMPDIR}"
fi

find build -type f 2> /dev/null | xargs rm

function setup {
    aclocal -I m4
    automake
    automake --add-missing
    autoconf
}

function try {
    local w=$1
    shift
    local dir=$1
    shift
    echo -n "	${w} ..."
    (cd "${dir}" && "$@" >${w}.stdout 2>${w}.stderr)
    local s=$?
    if [ ${s} -eq 0 ]; then
	echo " success"
    else
	echo " failed!"
	echo "Error $1 in ${dir}" >&2
    fi
    return ${s}
}

function buildlzma {
    host=$1
    march=$2
    local target="${BUILDDIR}/lib-${host}${march}"

    echo "	... liblzma"
    
    mkdir -p ${target}

    try configure-lzma ${target} ${LZMASRC}/configure \
	--host=${host} \
	--prefix=${target} \
	--disable-shared \
	"CFLAGS=${march}" \
	"CXXFLAGS=${march}" \
	"LDFLAGS=${march}"
    if [ $? -ne 0 ]; then
	return
    fi

    try build-lzma ${target} make ${MAKEFLAGS}
    if [ $? -ne 0 ]; then
	return
    fi
    try install-lzma ${target} make install
    if [ $? -ne 0 ]; then
	return
    fi
}

function buildit {
    local host=$1
    local march=$2
    local offsetbits=$3
    local cargs=$4
    local largs=$5
    local BM="${host}${march}"
    local D="build/${BM}/xoff${offsetbits}"
    local BMD="${BM}-${offsetbits}"
    local FULLD="${SRCDIR}/${D}"
    local CFLAGS="${march} ${cargs} -g -I${SRCDIR}/build/lib-${BM}/include"
    local CXXFLAGS="${march} ${cargs} -g -I${SRCDIR}/build/lib-${BM}/include"
    local LDFLAGS="${largs} ${march} -L${SRCDIR}/build/lib-${BM}/lib"
    mkdir -p ${D}

    echo "	... ${BMD}"
    
    cat >> Makefile.test <<EOF

# ${BMD}
# ${CFLAGS}
.PHONY: build-${BMD}
build-${BMD}:
	(cd ${D} && make all)

.PHONY: clean-${BMD}
clean-${BMD}:
	(cd ${D} && make clean)

.PHONY: regtest-${BMD}
regtest-${BMD}:
	(cd ${D} && ./xdelta3regtest 1> \${TMP}/regtest.${BMD}.stdout 2> \${TMP}/regtest.${BMD}.stderr)

.PHONY: selftest-${BMD}
selftest-${BMD}:
	(cd ${D} && ./bin/xdelta3 test 1> \${TMP}/selftest.${BMD}.stdout 2> \${TMP}/selftest.${BMD}.stderr)


EOF

    case ${host} in
	*linux*)
	    LINUXTGTS="${LINUXTGTS} build-${BMD}"
	    LINUXTEST1="${LINUXTEST1} selftest-${BMD}"
	    LINUXTEST2="${LINUXTEST2} regtest-${BMD}"
	    ;;
	*mingw*)
	    WINTGTS="${WINTGTS} build-${BMD}"
	    WINTEST1="${WINTEST1} selftest-${BMD}"
	    WINTEST2="${WINTEST2} regtest-${BMD}"
	    ;;
	*apple*)
	    OSXTGTS="${OSXTGTS} build-${BMD}"
	    OSXTEST1="${OSXTEST1} selftest-${BMD}"
	    OSXTEST2="${OSXTEST2} regtest-${BMD}"
	    ;;
    esac
    CLEAN="${CLEAN} clean-${BMD}"

    try configure-xdelta ${FULLD} ${SRCDIR}/configure \
    		  --host=${host} \
    		  --prefix=${FULLD} \
    		  --enable-static \
    		  --disable-shared \
    		  --enable-debug-symbols \
		  "CFLAGS=${CFLAGS}" \
		  "CXXFLAGS=${CXXFLAGS}" \
		  "LDFLAGS=${LDFLAGS}"
    if [ $? -ne 0 ]; then
	return
    fi

    try build-xdelta ${FULLD} make ${MAKEFLAGS} all
    if [ $? -ne 0 ]; then
	return
    fi

    try install-xdelta ${FULLD} make install
}

function buildall {
    echo ""
    echo "Host $1$2"
    echo ""

    buildlzma "$1" "$2"
    buildit "$1" "$2" 32 "-DXD3_USE_LARGEFILE64=0 $3" "$4"
    buildit "$1" "$2" 64 "-DXD3_USE_LARGEFILE64=1 $3" "$4"
}

setup

try untar-lzma ${BUILDDIR} tar -xvf "${LZMA_FILE}"
if [ $? -ne 0 ]; then
    exit $?
fi

cat > Makefile.test <<EOF
# Auto-generated ${DATE} -*- Mode: Makefile -*-
TMP = ${TMP}

EOF

# Native compiles
if [ "${MYOS}" == "Linux" ]; then
    # Linux
    buildall x86_64-pc-linux-gnu -m32
    buildall x86_64-pc-linux-gnu -m64
fi

if [ "${MYOS}" == "Darwin" ]; then
    # OS X
    buildall x86_64-apple-darwin -m32
    buildall x86_64-apple-darwin -m64
fi

# Cross compile
buildall i686-w64-mingw32 -mconsole "${MINGW_CFLAGS}"
buildall x86_64-w64-mingw32 -mconsole "${MINGW_CFLAGS}"

cat >> Makefile.test <<EOF

all: linux windows apple

clean: ${CLEAN}

linux: linux-build linux-selftest linux-regtest
windows: windows-build windows-selftest windows-regtest
apple: apple-build apple-selftest apple-regtest

linux-build: ${LINUXTGTS}
linux-selftest: ${LINUXTEST1}
linux-regtest: ${LINUXTEST2}

windows-build: ${WINTGTS}
windows-selftest: ${WINTEST1}
windows-regtest: ${WINTEST2}

apple-build: ${OSXTGTS}
apple-selftest: ${OSXTEST1}
apple-regtest: ${OSXTEST2}

EOF
