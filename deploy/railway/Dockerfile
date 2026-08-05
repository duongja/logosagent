FROM python:3.12-slim-trixie@sha256:646fb0bca3dd3ea1bcc6feb72c17ed16eed6e10cffc732fcc1478bd3e7f02d7b

WORKDIR /opt/logos
COPY runtime.tar.gz /tmp/runtime.tar.gz
RUN tar -xzf /tmp/runtime.tar.gz -C /opt/logos \
    && rm /tmp/runtime.tar.gz \
    && test -x /opt/logos/runtime/logoscore/AppRun \
    && test -f /opt/logos/modules/logos_agent/manifest.json

COPY entrypoint.py /opt/logos/entrypoint.py

ENV LOGOSCORE=/opt/logos/runtime/logoscore/AppRun \
    LOGOS_MODULES_DIR=/opt/logos/modules \
    LOGOS_DATA_DIR=/data \
    HOME=/data/home \
    LOGOS_NETWORK=logos-testnet-v0.2 \
    DELIVERY_PRESET=logos.test \
    STORAGE_NETWORK=logos.test \
    PYTHONUNBUFFERED=1

EXPOSE 8080
VOLUME ["/data"]
ENTRYPOINT ["python3", "/opt/logos/entrypoint.py"]
