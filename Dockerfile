# Build stage
FROM golang:1.25-alpine AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build for ARM64 (Graviton)
RUN CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -a -installsuffix cgo -o app app.go

# Runtime stage
FROM alpine:latest

WORKDIR /app

# Install ca-certificates for HTTPS
RUN apk --no-cache add ca-certificates dumb-init

# Copy binary and static files
COPY --from=builder /app/app .
COPY --from=builder /app/static ./static
COPY --from=builder /app/views ./views
COPY --from=builder /app/docs ./docs

# Make binary executable
RUN chmod +x /app/app

# Expose port
EXPOSE 3000

# Use dumb-init to handle signals properly
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["./app", "-prod"]
