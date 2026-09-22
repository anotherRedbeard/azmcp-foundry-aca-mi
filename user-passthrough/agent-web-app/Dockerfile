FROM node:22-alpine AS client-build

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY client ./client
COPY public ./public
RUN npm run build

FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
WORKDIR /app

RUN addgroup --system app && adduser --system --ingroup app app

COPY requirements.txt ./
ARG PIP_INDEX_URL
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY --from=client-build /app/public ./public

USER app
EXPOSE 3000

CMD ["python", "-m", "app.main"]
