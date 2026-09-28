# Fixture image: static binary on distroless, numeric non-root user.
FROM golang:1.24-bookworm AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/example-service .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/example-service /example-service
USER 65532:65532
ENTRYPOINT ["/example-service"]
