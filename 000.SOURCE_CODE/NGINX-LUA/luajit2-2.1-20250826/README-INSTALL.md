# 安装
```txt
sudo make install PREFIX=/usr/local/luajit2

后续使用需要： 可以加入到环境变量中 , 即 在执行 000.SOURCE_CODE/NGINX-1.30.0/Nginx-Build.sh 脚本之前，需要将这些添加到当前session的环境变量中
export export LUAJIT_LIB=/usr/local/luajit2/lib
export export LUAJIT_INC=/usr/local/luajit2/include/luajit-2.1
```