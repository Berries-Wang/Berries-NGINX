#!/bin/bash
# OS: Linux Wang 5.15.0-89-generic #99~20.04.1-Ubuntu SMP Thu Nov 2 15:16:47 UTC 2023 x86_64 x86_64 x86_64 GNU/Linux
# 依赖安装

export LUAJIT_LIB=/usr/local/luajit2/lib
export LUAJIT_INC=/usr/local/luajit2/include/luajit-2.1

#sudo apt-get -y install build-essential libpcre3 libpcre3-dev zlib1g zlib1g-dev libgd-dev libxml2 libxml2-dev uuid-dev
CURPATH=`pwd`
BUILDOUTPUT="${CURPATH}/build-output"
# 防止执行目录错误
if [[ ! -f "${CURPATH}/Nginx-Build.sh" ]];then
    echo 'Nginx-Build.sh 文件不存在，执行目录错误';
    exit;
fi


# ========== 下载编译 OpenSSL (支持 QUIC, 供 HTTP/3 使用) ==========
OPENSSL_VERSION="3.4.1"
OPENSSL_SRC="${CURPATH}/openssl-${OPENSSL_VERSION}"
OPENSSL_PREFIX="${BUILDOUTPUT}/openssl"

if [ ! -d "${OPENSSL_PREFIX}" ]; then
    if [ ! -f "${OPENSSL_SRC}.tar.gz" ]; then
        echo "正在下载 OpenSSL ${OPENSSL_VERSION} ..."
        wget -q --show-progress https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz
        if [ $? -ne 0 ]; then
            echo "GitHub 下载失败, 尝试官方源..."
            wget -q --show-progress https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
        fi
    fi

    if [ ! -d "${OPENSSL_SRC}" ]; then
        echo "正在解压 OpenSSL ..."
        tar -xzf openssl-${OPENSSL_VERSION}.tar.gz
    fi

    echo "正在编译 OpenSSL (enable-quic) ..."
    cd ${OPENSSL_SRC}
    ./Configure --prefix=${OPENSSL_PREFIX} --openssldir=${OPENSSL_PREFIX} enable-quic
    make -j$(nproc)
    make install_sw
    cd ${CURPATH}
    echo "OpenSSL 编译完成: ${OPENSSL_PREFIX}"
else
    echo "OpenSSL 已存在, 跳过编译: ${OPENSSL_PREFIX}"
fi


# 创建目录
if [ -d "${BUILDOUTPUT}/nginx" ]; then
   echo "/nginx目录存在,删除目录文件"
   rm -rf ${BUILDOUTPUT}/nginx
fi
echo "正在创建目录: ${BUILDOUTPUT}/nginx"
mkdir -p ${BUILDOUTPUT}/nginx
mkdir -p ${BUILDOUTPUT}/nginx/logs
cp ${CURPATH}/conf/mime.types ${CURPATH}/build-output/nginx/mime.types
touch "${BUILDOUTPUT}/nginx/nginx.lock" "${BUILDOUTPUT}/nginx/access.log" "${BUILDOUTPUT}/nginx/error.log"

# 安装依赖
 ./configure \
     --prefix=${BUILDOUTPUT}/nginx \
     --pid-path=${BUILDOUTPUT}/nginx/nginx.pid \
     --lock-path=${BUILDOUTPUT}/nginx/nginx.lock \
     --error-log-path=${BUILDOUTPUT}/nginx/error.log \
     --http-log-path=${BUILDOUTPUT}/nginx/access.log \
     --with-http_gzip_static_module \
     --http-client-body-temp-path=${BUILDOUTPUT}/nginx/client \
     --http-proxy-temp-path=${BUILDOUTPUT}/nginx/proxy \
     --http-fastcgi-temp-path=${BUILDOUTPUT}/nginx/fastcgi \
     --http-uwsgi-temp-path=${BUILDOUTPUT}/nginx/uwsgi \
     --http-scgi-temp-path=${BUILDOUTPUT}/nginx/scgi \
     --with-http_ssl_module \
     --with-http_stub_status_module \
     --with-http_v2_module \
     --with-http_v3_module \
     --with-openssl=${OPENSSL_SRC} \
     --with-cc-opt="-I${OPENSSL_PREFIX}/include" \
     --with-ld-opt="-Wl,-rpath,/usr/local/luajit2/lib -L${OPENSSL_PREFIX}/lib64 -Wl,-rpath,${OPENSSL_PREFIX}/lib64" \
     --with-pcre \
     --add-module=/home/wei/OPEN_SOURCE/Berries-NGINX/000.SOURCE_CODE/NGINX-LUA/ngx_devel_kit-0.2.19 \
     --add-module=/home/wei/OPEN_SOURCE/Berries-NGINX/000.SOURCE_CODE/NGINX-LUA/lua-nginx-module-0.10.30rc2
 make
