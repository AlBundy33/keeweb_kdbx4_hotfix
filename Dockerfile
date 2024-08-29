# multistage build
# create image from builder stage
# docker build --target builder -t keeweb_builder .
# start container
# docker run --rm -p 8085:8085 -it keeweb_builder bash

FROM node:18 as builder

# Error: error:0308010C:digital envelope routines::unsupported
# https://stackoverflow.com/questions/69692842/error-message-error0308010cdigital-envelope-routinesunsupported
ENV NODE_OPTIONS=--openssl-legacy-provider

WORKDIR /build

RUN --mount=type=cache,target=/var/cache/apt \
 apt update \
 && apt install -y --no-install-recommends \
        less \
        nsis \
        vim \
        wine

RUN npm install -g grunt npm-check-updates \
 && mkdir -p ~/.ssh \
 && ssh-keyscan -H github.com >> ~/.ssh/known_hosts \
 && git config --global user.email docker@local 

# clone all needed repos
RUN git clone --branch 2.0.4 https://github.com/keeweb/kdbxweb.git \
 && git clone --branch v1.18.7 https://github.com/keeweb/keeweb.git \
 && git clone https://github.com/keeweb/keeweb-plugins.git

# patch and build kdbxweb
RUN --mount=type=cache,target=/root/.npm \
 cd kdbxweb \
 && git fetch origin refs/pull/50/head \
 && git cherry-pick -n FETCH_HEAD \
 && npm install \
 && npm run build \
 && npm link

# build keeweb with the modified kdbxweb module
# on kdbxweb master-branch add this commands before install 
# because xmldom was replaced in kdbxweb after 2.0.4
# && npm uninstall xmldom \
# && npm install @xmldom/xmldom \
# to build the windows app add this after the grunt command
# && grunt desktop-win32 --skip-sign
# npm run dev does not work current - if you want to give it a try add this line to the commands
# && sed "s/port: 8085\$/port: 8085,\n                host: '0.0.0.0',\n                disableHostCheck: true/g" -i Gruntfile.js \
RUN --mount=type=cache,target=/root/.npm \
 cd keeweb \
 && git fetch origin refs/pull/2030/head \
 && git cherry-pick -n FETCH_HEAD \
 && npm install \
 && npm link kdbxweb \
 && grunt

# increase DH_SIZE - otherwise newer nginx will not start
RUN sed -i 's/DH_SIZE="512"/DH_SIZE="2048"/g' keeweb/package/docker/entrypoint.sh

# https://github.com/keeweb/keeweb/blob/master/package/docker/Dockerfile
FROM nginx:stable-alpine as dist

# openssl is needed to create missing dh.pem
RUN apk add --no-cache openssl

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

ENTRYPOINT ["/bin/sh", "/opt/entrypoint.sh"]
CMD ["nginx"]

EXPOSE 443
EXPOSE 80
