FROM --platform=linux/amd64 node:20-alpine

WORKDIR /usr/src/app

COPY package*.json ./

RUN npm install

COPY . .

EXPOSE 8080


CMD ["node", "server.js"]
