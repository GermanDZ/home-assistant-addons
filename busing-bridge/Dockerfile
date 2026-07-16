ARG BUILD_FROM
FROM $BUILD_FROM

ENV LANG=C.UTF-8 \
    PYTHONUNBUFFERED=1

RUN apk add --no-cache python3 py3-pip

WORKDIR /bridge

COPY src/requirements.txt ./
RUN pip3 install --no-cache-dir --break-system-packages -r requirements.txt

COPY src/ ./
COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
