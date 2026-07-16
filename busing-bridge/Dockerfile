ARG BUILD_FROM
FROM $BUILD_FROM

ENV LANG C.UTF-8

RUN apk add --no-cache ruby ruby-bundler git

RUN mkdir -p /bridge
WORKDIR /bridge

COPY run.sh /
RUN chmod a+x /run.sh

COPY src/* /bridge/
RUN bundle install

CMD [ "/run.sh" ]
