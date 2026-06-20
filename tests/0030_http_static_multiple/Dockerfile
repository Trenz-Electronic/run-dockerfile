#http.static: ALPHA=data-a
#http.static: BETA=data-b
FROM alpine:latest
RUN apk add --no-cache curl
ARG HTTP_ALPHA
ARG HTTP_BETA
# Each server must map to its OWN directory. If the second directive reuses the
# first server's port, marker-b.txt is fetched from data-a (which only has
# marker-a.txt) and this build fails at the BETA curl.
RUN curl -f ${HTTP_ALPHA}/marker-a.txt -o /tmp/a.txt
RUN curl -f ${HTTP_BETA}/marker-b.txt -o /tmp/b.txt
RUN cat /tmp/a.txt /tmp/b.txt
