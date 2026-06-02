FROM nginx:alpine

RUN rm -rf /usr/share/nginx/html/*

COPY index.html app.js /usr/share/nginx/html/
COPY default.conf.template /etc/nginx/templates/default.conf.template

EXPOSE 80