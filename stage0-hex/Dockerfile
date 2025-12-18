# Test environment for Stage 0 (Linux i386)
FROM i386/alpine:latest

RUN apk add --no-cache vim  # for xxd

WORKDIR /bootstrap
COPY stage0.hex .
COPY test.sh .

RUN chmod +x test.sh

CMD ["./test.sh"]
