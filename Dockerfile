FROM node:16

WORKDIR /usr/src/app
COPY package*.json ./
RUN npm install

COPY . .
RUN npm run build
CMD [ "node", "dist/index.js" ]

LABEL org.opencontainers.image.source="https://github.com/jsh32/mineboy"