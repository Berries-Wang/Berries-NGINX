#!/bin/bash 
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