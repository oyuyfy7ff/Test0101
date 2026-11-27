# หน้าเว็บสำหรับดูหน้าจอและควบคุมโทรศัพท์ (ws-scrcpy)
FROM node:18-bookworm AS build
RUN apt-get update && apt-get install -y --no-install-recommends git python3 make g++ \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
ARG WS_SCRCPY_REF=master
RUN git clone --depth 1 --branch ${WS_SCRCPY_REF} https://github.com/NetrisTV/ws-scrcpy.git . \
    && npm install && npm run dist \
    && cd dist && npm install --omit=dev

FROM node:18-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends adb \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/dist /app
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
WORKDIR /app
EXPOSE 8000
ENTRYPOINT ["/entrypoint.sh"]
