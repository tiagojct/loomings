FROM node:20-alpine AS build
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci
COPY vite.config.js ./
COPY vendor ./vendor
COPY src ./src
COPY public ./public
COPY examples ./examples
COPY lessons ./lessons
# vite.config.js sets base to /app/, matching nginx.conf's /app mount.
RUN npm run build

FROM nginx:alpine
# Landing page (docs/) owns the root; the editor app lives at /app.
# The landing imports the shared design from /vendor.
COPY docs /usr/share/nginx/html
COPY vendor /usr/share/nginx/html/vendor
COPY --from=build /src/dist /usr/share/nginx/html/app
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:80/ >/dev/null || exit 1
