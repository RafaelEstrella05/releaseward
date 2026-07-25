FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

COPY server.js classifier.js ./
COPY public ./public

RUN addgroup -g 10001 -S appgroup \
    && adduser -u 10001 -S appuser -G appgroup
USER 10001:10001

EXPOSE 3000
ENV PORT=3000

CMD ["node", "server.js"]
