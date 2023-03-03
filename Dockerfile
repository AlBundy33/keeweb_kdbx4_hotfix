# multistage build
# create dbg image from builder
# docker build --target builder -t dbg .
# start dbg container
# docker run --rm -it dbg bah

FROM node:18 as builder

# Error: error:0308010C:digital envelope routines::unsupported
# https://stackoverflow.com/questions/69692842/error-message-error0308010cdigital-envelope-routinesunsupported
ENV NODE_OPTIONS=--openssl-legacy-provider

WORKDIR /build

# clone, patch and build kdbxweb
RUN git clone --branch 2.0.4 https://github.com/keeweb/kdbxweb.git \
    && cd kdbxweb \
    && sed 's/item\.lastModified$/item.lastModified, true/g' -i lib/format/kdbx-custom-data.ts \
    && npm install \
    && npm run build \
    && npm link

# build keeweb with the modified kdbxweb module
RUN git clone --branch v1.18.7 https://github.com/keeweb/keeweb.git \
    && cd keeweb \
    && npm install \
    && npm link kdbxweb \
    && npm install -g grunt \
    && grunt

# needed for keeweb
RUN git clone https://github.com/keeweb/keeweb-plugins.git
 
# build windows app
#RUN cd keeweb \
#    && apt update \
#    && apt install nsis wine64 -y --no-install-recommends \
#    && ln -s /usr/bin/wine64-stable /usr/bin/wine64 \
#    && grunt desktop-win32 --skip-sign

# https://github.com/keeweb/keeweb/blob/master/package/docker/Dockerfile
FROM nginx:stable-alpine as dist

# openssl is needed to create missing dh.pem
RUN apk add --no-cache openssl bash 

RUN rm -rf /etc/nginx/conf.d/* \
    && mkdir -p /etc/nginx/external

RUN sed -i 's/access_log.*/access_log \/dev\/stdout;/g' /etc/nginx/nginx.conf \
    && sed -i 's/error_log.*/error_log \/dev\/stdout info;/g' /etc/nginx/nginx.conf \
    && sed -i 's/^pid/daemon off;\npid/g' /etc/nginx/nginx.conf

# now copy all needed files from build-stage
COPY --from=builder /build/keeweb/package/docker/keeweb.conf /etc/nginx/conf.d/keeweb.conf
COPY --from=builder /build/keeweb/package/docker/entrypoint.sh /opt/entrypoint.sh
COPY --from=builder /build/keeweb/dist keeweb
COPY --from=builder /build/keeweb-plugins/docs keeweb/plugins

# increase DH_SIZE from 512 to 2048 - otherwise nginx will not start
# and switch to sh instead of bash to be able to use different images
RUN sed -i 's/DH_SIZE="512"/DH_SIZE="2048"/g' /opt/entrypoint.sh \
    && sed -i 's/\/bin\/bash/\/bin\/sh/g' /opt/entrypoint.sh \
    && chmod a+x /opt/entrypoint.sh

ENTRYPOINT ["/opt/entrypoint.sh"]
CMD ["nginx"]

EXPOSE 443
EXPOSE 80
