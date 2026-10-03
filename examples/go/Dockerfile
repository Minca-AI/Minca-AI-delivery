# Fixture image: static binary on distroless, numeric non-root user.
# GREETING_NAME has no default on purpose: the self-test passes it through
# image.yml's build-args input, so a build that does not forward it fails here.
FROM golang:1.24-bookworm AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
ARG GREETING_NAME
RUN test -n "${GREETING_NAME}" || { echo "GREETING_NAME build-arg is required" >&2; exit 1; }
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X main.defaultName=${GREETING_NAME}" -o /out/example-service .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/example-service /example-service
USER 65532:65532
ENTRYPOINT ["/example-service"]
