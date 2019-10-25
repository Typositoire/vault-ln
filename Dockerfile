FROM openresty/openresty:alpine-fat

RUN /usr/local/openresty/luajit/bin/luarocks install lua-resty-http ;\
    /usr/local/openresty/luajit/bin/luarocks install lua-resty-libcjson

COPY conf.d /etc/nginx/conf.d
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf