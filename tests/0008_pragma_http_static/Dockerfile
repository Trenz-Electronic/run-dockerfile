#http.static: TESTDATA=http-data
FROM alpine:latest
RUN apk add --no-cache curl
ARG HTTP_TESTDATA
RUN curl -f ${HTTP_TESTDATA}/marker.txt -o /tmp/fetched.txt
RUN ! curl -fsS ${HTTP_TESTDATA%/*}/marker.txt -o /tmp/no-token.txt
RUN cat /tmp/fetched.txt
