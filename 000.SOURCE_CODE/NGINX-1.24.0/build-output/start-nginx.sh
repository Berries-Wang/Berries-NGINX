#!/bin/bash
CUR_DIR=`pwd`
cd "${CUR_DIR}/../objs"

echo "$1"

if [[ ${1} == "stop" ]]; then 
   ./nginx -s stop -c "${CUR_DIR}/nginx.conf"
elif [[ ${1} == "start" ]]; then 
   ./nginx -c "${CUR_DIR}/nginx.conf"
elif [[ ${1} == "reload" ]]; then
   ./nginx -s reload -c "${CUR_DIR}/nginx.conf"
else
   echo "无效选项"
fi

ps axu | grep 'nginx'

