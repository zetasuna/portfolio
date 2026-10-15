# syntax=docker/dockerfile:1

FROM golang:1.26-alpine AS builder

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY cmd/ ./cmd/
COPY internal/ ./internal/

RUN CGO_ENABLED=0 GOOS=linux \
  go build -trimpath -ldflags="-s -w" \
  -o /out/portfolio ./cmd/web 

FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /

COPY --from=builder /out/portfolio /portfolio
# COPY --from=builder /out/healthcheck /healthcheck

EXPOSE 8080

USER nonroot:nonroot

ENTRYPOINT ["/portfolio"]
