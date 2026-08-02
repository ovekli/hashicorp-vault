FROM docker.io/hashicorp/vault:2.0.3
ENV PATH=/home/vault/bin:$PATH

ADD oc /home/vault/bin/

USER root
RUN apk add libc6-compat
USER vault