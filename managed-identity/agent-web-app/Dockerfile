FROM node:22-alpine

ENV NODE_ENV=production
WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY public ./public
COPY client ./client
COPY src ./src
RUN npm run build

USER node
EXPOSE 3000

CMD ["npm", "start"]
