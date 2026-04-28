# Nginx + Lua
## 软件包安装
|顺序|软件名|说明|备注|
|-|-|-|-|
|1|- [000.SOURCE_CODE/NGINX-LUA/lua-nginx-module-0.10.29]|- 安装:[000.SOURCE_CODE/NGINX-LUA/lua-nginx-module-0.10.29/README-INSTALL.md]|- |
|-|-|-|-|
|2|- [000.SOURCE_CODE/NGINX-LUA/lua-resty-core-0.1.32]|- 安装:[000.SOURCE_CODE/NGINX-LUA/lua-resty-core-0.1.32/README-INSTALL.md]|-|
|-|-|-|-|
|3|- [000.SOURCE_CODE/NGINX-LUA/lua-resty-lrucache-nginx-1.29.2]|- 安装:[000.SOURCE_CODE/NGINX-LUA/lua-resty-lrucache-nginx-1.29.2/README.markdown]#Installation|-|
|-|-|-|-|
|4|- [000.SOURCE_CODE/NGINX-LUA/luajit2-2.1-20250826]|- 安装:[000.SOURCE_CODE/NGINX-LUA/luajit2-2.1-20250826/README-INSTALL.md]|-|
|-|-|-|-|
|5|- [000.SOURCE_CODE/NGINX-LUA/ngx_devel_kit-0.2.19]|- 安装:[000.SOURCE_CODE/NGINX-LUA/ngx_devel_kit-0.2.19/README-INSTALL.md]|- 可以考虑更高级版本: 0.3.3 |
|-|-|-|-|
|6|- [000.SOURCE_CODE/NGINX-1.30.0]|- 编译:[000.SOURCE_CODE/NGINX-1.30.0/Nginx-Build.sh]|-|



---

## 完成标识
```nginx
// 在 nginx.conf 中配置： 
location /hello_lua {
      default_type 'text/plain';
      content_by_lua 'ngx.say("hello, lua")';
}

访问localhost/hello_lua会出现”hello, lua”表示安装成功
hello, lua
```