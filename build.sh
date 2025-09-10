#!/bin/bash

X_MAGIC="\x9b\xaa\x31\xe1\x96\x41\x43\xa7\x05\x4a\x0e\x90\xc4\x40\x3d\x36\x6c\x87\x37\x41\x28\x2b\xa2\x7b\x73\xe3\x48\xcc\x4c\x0e\xa7\x72"
X_KEY="\x13\x64\x18\xe4\x3f\x2e\xda\x62\x5a\xf3\x91\x7e\xb2\x1c\x82\xe0"
X_IV="\x3f\x8e\x52\x4d\x48\x26\xf2\x93\x27\x38\x7c\x6a\x81\x85\x05\x42"

MODE_ENCRYPT="false"
OS_TYPE=`uname`
if [ x"${OS_TYPE}" == x"Darwin" ];then
    DIR_ROOT=`pwd`
else
    DIR_ROOT=`realpath $(dirname "$0")`
fi

show_usage()
{
    echo "Usage:  -e encrypt c file"
    echo "        -d dir for encryption"
    echo "        -f file for encryption"
    echo "        -c clear build env"
    echo ""
    exit -1
}

while getopts 'ef:d:hc' OPT; do
    case $OPT in
    e)
        MODE_ENCRYPT="true";;
    d)
        DIR_ENCRYPT=$OPTARG;;
    f)
        FILE_ENCRYPT=$OPTARG;;
    c)
        MODE_CLEAR="true";;
    ?)
        show_usage
    esac
done
shift $(($OPTIND - 1))

if [ x"$MODE_CLEAR" == x'true' ];then
    rm -rf build > /dev/null 2>&1
    rm -rf openssl/build > /dev/null 2>&1
    rm -rf libiconv/build > /dev/null 2>&1
    rm -rf zlib/build > /dev/null 2>&1
    exit 0
fi

if [ x"$MODE_ENCRYPT" == x'true' ];then
    if [ -f "$FILE_ENCRYPT" ];then
        echo -n -e ${X_MAGIC} | cmp -n 32 $FILE_ENCRYPT > /dev/null 2>&1
        if [ $? == 0 ];then
            echo "Failed: file already encrypted:${FILE_ENCRYPT}"
        else
            KEY=`echo -e -n $X_KEY | xxd -p -l 16 -c 16`
            IV=`echo -e -n $X_IV | xxd -p -l 16 -c 16`
            echo KEY=$KEY
            echo IV=$IV
            openssl enc -sm4-cbc -v -nosalt -K ${KEY} -iv ${IV} -in ${FILE_ENCRYPT} -out ${FILE_ENCRYPT}.enc  2>&1
            echo -n -e ${X_MAGIC} > $FILE_ENCRYPT
            cat ${FILE_ENCRYPT}.enc >> $FILE_ENCRYPT
            rm ${FILE_ENCRYPT}.enc
            echo "Succeed: file encrypted:${FILE_ENCRYPT}"
        fi
    fi
  
    if [ -d "$DIR_ENCRYPT" ];then
        for file in $(find $DIR_ENCRYPT -type f -name *.c -o -name *.h);do
            echo -n -e ${X_MAGIC} | cmp -n 32 $file > /dev/null 2>&1
            if [ $? == 0 ];then
                echo "Ignore: file already encrypted:${file}"
                continue
            fi
            KEY=`echo -e -n $X_KEY | xxd -p -l 16 -c 16`
            IV=`echo -e -n $X_IV | xxd -p -l 16 -c 16`
            openssl enc -sm4-cbc -v -nosalt -K ${KEY} -iv ${IV} -in ${file} -out ${file}.enc > /dev/null  2>&1
            echo -n -e ${X_MAGIC} > $file
            cat ${file}.enc >> $file
            rm ${file}.enc
            echo "Succeed: file encrypted:${file}"
        done
    fi
else
    mkdir ${DIR_ROOT}/build > /dev/null 2>&1
    
    #download prerequired files
    ${DIR_ROOT}/contrib/download_prerequisites
    if [ $? != 0 ];then
        echo "failed to download prerequisites"
        exit -1
    fi
    
    if [ ! -d ${DIR_ROOT}/openssl ];then
        if [ ! -f ${DIR_ROOT}/openssl-3.5.2.tar.gz ];then
            wget https://github.com/openssl/openssl/releases/download/openssl-3.5.2/openssl-3.5.2.tar.gz
            if [ $? != 0 ]; then
                echo "failed to download openssl"
                exit -1
            fi
        fi
        mkdir ${DIR_ROOT}/openssl > /dev/null 2>&1
        tar -xvf openssl-3.5.2.tar.gz -C ${DIR_ROOT}/openssl --strip-components=1 || {rm -rf openssl-3.5.2.tar.gz;rm -rf ${DIR_ROOT}/openssl}
    fi
    if [ ! -d ${DIR_ROOT}/libiconv ];then
        if [ ! -f ${DIR_ROOT}/libiconv-1.18.tar.gz ];then
            wget https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.18.tar.gz
            if [ $? != 0 ]; then
                echo "failed to download iconv"
                exit -1
            fi
        fi
        mkdir ${DIR_ROOT}/libiconv > /dev/null 2>&1
        tar -xvf libiconv-1.18.tar.gz -C ${DIR_ROOT}/libiconv --strip-components=1|| {rm -rf libiconv-1.18.tar.gz;rm -rf ${DIR_ROOT}/libiconv}
    fi
    
    #compile openssl
    if [ ! -f ${DIR_ROOT}/build/out/lib/libcrypto.a ];then
        mkdir ${DIR_ROOT}/openssl/build > /dev/null 2>&1
        pushd ${DIR_ROOT}/openssl/build
        ../config no-asm no-tests no-shared no-module enable-weak-ssl-ciphers --libdir=lib --prefix=${DIR_ROOT}/build/out
        make -j$(nproc) && make install_sw
        if [ $? != 0 ]; then
            echo "failed to make openssl"
            popd
            exit -1
        fi
        popd
    fi
    
    #compile libiconv
    if [ ! -f ${DIR_ROOT}/build/out/lib/libiconv.a ];then
        mkdir ${DIR_ROOT}/libiconv/build > /dev/null 2>&1
        pushd ${DIR_ROOT}/libiconv/build
        ../configure --with-pic=yes --enable-extra-encodings --enable-static=yes --enable-shared=no --prefix=${DIR_ROOT}/build/out
        make -j$(nproc) && make install
        if [ $? != 0 ]; then
            echo "failed to make libiconv"
            popd
            exit -1
        fi
        popd
    fi
    
    #compile zlib
    if [ ! -f ${DIR_ROOT}/build/out/lib/libz.a ];then
        mkdir ${DIR_ROOT}/zlib/build > /dev/null 2>&1
        pushd ${DIR_ROOT}/zlib/build
        cmake -DCMAKE_POSITION_INDEPENDENT_CODE=1 -DCMAKE_INSTALL_PREFIX=${DIR_ROOT}/build/out ../
        make -j$(nproc) && make install
        if [ $? != 0 ]; then
            echo "failed to make zlib"
            popd
            exit -1
        fi
        rm ${DIR_ROOT}/build/out/lib/libz.so*
        popd
    fi

    #compile gcc
    export OPENSSL_LIB_DIR=${DIR_ROOT}/build/out/lib 
    export OPENSSL_INCLUDE_DIR=${DIR_ROOT}/build/out/include
    pushd ${DIR_ROOT}/build
    MAGIC=`echo -e -n $X_MAGIC | xxd -i`
    KEY=`echo -e -n $X_KEY | xxd -i`
    IV=`echo -e -n $X_IV | xxd -i`
    
    echo "#ifndef __FILES_ENCRYPT_H__" > ${DIR_ROOT}/libcpp/files_encrypt.h
    echo "static unsigned char x_magic[]={${MAGIC}};" >> ${DIR_ROOT}/libcpp/files_encrypt.h
    echo "static unsigned char x_key[]={${KEY}};" >> ${DIR_ROOT}/libcpp/files_encrypt.h
    echo "static unsigned char x_iv[]={${IV}};" >> ${DIR_ROOT}/libcpp/files_encrypt.h
    echo "#endif /* __FILES_ENCRYPT_H__ */" >> ${DIR_ROOT}/libcpp/files_encrypt.h
    
    ../configure --prefix=${DIR_ROOT}/build/out --enable-languages=c --enable-stage1-languages=c --disable-multilib --disable-debug --disable-profiling --disable-doc --disable-plugins --disable-libitm --disable-libsanitizer --disable-libquadmath --disable-libgomp --disable-plugins --disable-lto --enable-static --disable-shared --without-isl --without-cloog --without-c++tools CFLAGS="-O2 -fPIC" CXXFLAGS="-O2 -fPIC"
    if [ $? != 0 ]; then
        echo "failed to config gcc"
        popd
        exit -1
    fi
    make -j$(nproc) && make install
    if [ $? != 0 ]; then
        echo "failed to make gcc"
        popd
        exit -1
    fi
    mkdir -pv ${DIR_ROOT}/build/gcc-12.4/ > /dev/null 2>&1
    cp -r ${DIR_ROOT}/build/out/* ${DIR_ROOT}/build/gcc-12.4/
    find ${DIR_ROOT}/build/gcc-12.4/bin/ -type f -not -name gcc | xargs rm
    rm -rf ${DIR_ROOT}/build/gcc-12.4/share
    rm -rf ${DIR_ROOT}/build/gcc-12.4/include
    rm -rf ${DIR_ROOT}/build/gcc-12.4/lib/cmake
    rm -rf ${DIR_ROOT}/build/gcc-12.4/lib/engines-3
    rm -rf ${DIR_ROOT}/build/gcc-12.4/lib/lib*
    rm -rf ${DIR_ROOT}/build/gcc-12.4/lib/ossl-modules
    rm -rf ${DIR_ROOT}/build/gcc-12.4/lib/pkgconfig
    rm -rf ${DIR_ROOT}/build/gcc-12.4/lib64/libstdc++*
    rm -rf ${DIR_ROOT}/build/gcc-12.4/lib64/libsupc++*
    find ${DIR_ROOT}/build/gcc-12.4/libexec/gcc/ -name cc1plus | xargs rm
    find ${DIR_ROOT}/build/gcc-12.4/libexec/gcc/ -name g++-mapper-server | xargs rm
    
    find ${DIR_ROOT}/build/gcc-12.4/bin -type f | xargs strip > /dev/null 2>&1
    find ${DIR_ROOT}/build/gcc-12.4/libexec -type f | xargs strip > /dev/null 2>&1
    
    echo "create package ..."
    tar -cf - -C ${DIR_ROOT}/build/ gcc-12.4 | xz -9 -c > gcc-12.4-lite-$(uname -m).tar.xz
    echo "create package ... done"
    
    popd
fi
