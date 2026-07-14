FROM node:20-alpine AS build
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci
COPY vite.config.js ./
COPY src ./src
COPY examples ./examples
# --base overrides vite.config.js's default ('/') for this build only — the
# Tauri desktop build (tauri.conf.json's frontendDist) still needs the
# default, so this stays a CLI flag here rather than a config change.
RUN npm run vite:build -- --base /app/

FROM nginx:alpine
# Landing page (docs/) owns the root; the editor app lives at /app.
COPY docs /usr/share/nginx/html
COPY --from=build /src/dist /usr/share/nginx/html/app
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:80/ >/dev/null || exit 1
