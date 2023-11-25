#!/bin/bash 
# OS: Linux Wang 5.15.0-89-generic #99~20.04.1-Ubuntu SMP Thu Nov 2 15:16:47 UTC 2023 x86_64 x86_64 x86_64 GNU/Linux
# 依赖安装
sudo apt-get -y install build-essential libpcre3 libpcre3-dev zlib1g zlib1g-dev libssl-dev libgd-dev libxml2 libxml2-dev uuid-dev
CURPATH=`pwd`
BUILDOUTPUT="${CURPATH}/build-output"
# 防止执行目录错误
if [[ ! -f "${CURPATH}/Nginx-Build.sh" ]];then
    echo 'Nginx-Build.sh 文件不存在，执行目录错误';
    exit;
fi

# 创建目录
if [ -d "${BUILDOUTPUT}/nginx" ]; then 
   echo "/nginx目录存在，删除目录文件"
   rm -rf ${BUILDOUTPUT}/nginx
fi
echo "正在创建目录: ${BUILDOUTPUT}/nginx"
mkdir -p ${BUILDOUTPUT}/nginx
touch "${BUILDOUTPUT}/nginx/nginx.lock" "${BUILDOUTPUT}/nginx/access.log" "${BUILDOUTPUT}/nginx/error.log"
# 安装依赖
 ./configure \
     --prefix=${BUILDOUTPUT}/nginx \
     --pid-path=${BUILDOUTPUT}/nginx/nginx.pid
     --lock-path=${BUILDOUTPUT}/nginx/nginx.lock
     --error-log-path=${BUILDOUTPUT}/nginx/error.log \
     --http-log-path=${BUILDOUTPUT}/nginx/access.log \
     --with-http_gzip_static_module \
     --http-client-body-temp-path=${BUILDOUTPUT}/nginx/client \
     --http-proxy-temp-path=${BUILDOUTPUT}/nginx/proxy \
     --http-fastcgi-temp-path=${BUILDOUTPUT}/nginx/fastcgi \
     --http-uwsgi-temp-path=${BUILDOUTPUT}/nginx/uwsgi \
     --http-scgi-temp-path=${BUILDOUTPUT}/nginx/scgi
 make