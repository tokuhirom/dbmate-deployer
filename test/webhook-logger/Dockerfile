FROM golang:alpine AS builder
WORKDIR /build
COPY main.go .
RUN CGO_ENABLED=0 go build -o webhook-logger main.go

FROM alpine:3.21
COPY --from=builder /build/webhook-logger /usr/local/bin/webhook-logger
WORKDIR /tmp
CMD ["webhook-logger"]
