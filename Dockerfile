FROM nginx:alpine

COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html alternatives.json manifest.json service-worker.js icon.svg plan.schema.json /usr/share/nginx/html/

EXPOSE 80
