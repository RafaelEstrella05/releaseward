FROM node:20-alpine AS dependencies

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

FROM node:20-alpine AS runtime

WORKDIR /app

RUN apk upgrade --no-cache \
    && rm -rf /usr/local/lib/node_modules/npm \
    && rm -f /usr/local/bin/npm /usr/local/bin/npx

COPY --from=dependencies /app/node_modules ./node_modules
COPY package.json ./
COPY server.js classifier.js ./
COPY public ./public

RUN addgroup -g 10001 -S appgroup \
    && adduser -u 10001 -S appuser -G appgroup
USER 10001:10001

EXPOSE 3000
ENV PORT=3000

CMD ["node", "server.js"]
