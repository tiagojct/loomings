FROM node:20-alpine AS build
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci
COPY vite.config.js ./
COPY src ./src
COPY examples ./examples
COPY lessons ./lessons
# vite.config.js sets base to /app/, matching nginx.conf's /app mount.
RUN npm run build

FROM nginx:alpine
# Landing page (docs/) owns the root; the editor app lives at /app.
COPY docs /usr/share/nginx/html
COPY --from=build /src/dist /usr/share/nginx/html/app
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:80/ >/dev/null || exit 1
