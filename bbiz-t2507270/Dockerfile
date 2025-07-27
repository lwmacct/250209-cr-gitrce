FROM ghcr.io/lwmacct/250209-cr-ubuntu:noble-t2506180

ENV PATH=$PATH:/opt/MegaRAID/storcli
RUN set -eux; \
    echo "安装 storcli"; \
    mkdir -p /tmp/storcli; \
    wget -O /tmp/storcli/download.zip https://docs.broadcom.com/docs-and-downloads/007.3103.0000.0000_MR%207.31_storcli.zip; \
    unzip /tmp/storcli/download.zip -d /tmp/storcli; \
    unzip /tmp/storcli/storcli_rel/Unified_storcli_all_os.zip -d /tmp/storcli; \
    dpkg -i /tmp/storcli/Unified_storcli_all_os/Ubuntu/storcli_007.3103.0000.0000_all.deb; \
    rm -rf /tmp/storcli; \
    echo;

# https://github.com/etcd-io/etcd
COPY --from=gcr.io/etcd-development/etcd:v3.6.3 /usr/local/bin/etcdctl /usr/local/bin/etcdctl

# https://github.com/VictoriaMetrics/VictoriaMetrics
COPY --from=victoriametrics/vmagent:v1.122.0 /vmagent-prod /usr/local/bin/vmagent

RUN set -eux; \
    echo "安装 docker-cli https://docs.docker.com/engine/install/ubuntu/"; \
    install -m 0755 -d /etc/apt/keyrings; \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc; \
    chmod a+r /etc/apt/keyrings/docker.asc; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null; \
    apt-get update && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin; \
    rm -rf /etc/apt/sources.list.d/docker.list; \
    rm -rf /etc/apt/keyrings/docker.asc; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*;

RUN set -eux; \
    echo "安装 fluent-bit"; \
    curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*;

RUN set -eux; \
    echo "apt 包安装"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        redis virt-what freeipmi ; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*;

RUN set -eux; \
    echo "安装 uv"; \
    curl -LsSf https://astral.sh/uv/install.sh | sh; \
    export PATH="/root/.local/bin:$PATH"; \
    uv venv /opt/venv --system-site-packages; \
    uv pip install --python /opt/venv/bin/python pip; \
    /opt/venv/bin/pip config set global.index-url https://mirrors.ustc.edu.cn/pypi/simple; \
    echo; 

RUN set -eux; \
    echo "软链接"; \
    rm -rf /etc/cron.d/; \
    ln -sf /apps/data/.gitrce/cron.d/ /etc/cron.d; \
    ln -sf /bin/bash /bin/sh; \
    mkdir -p /root/.ssh; \
    chmod 700 /root/.ssh; \
    echo "StrictHostKeyChecking no" >> /root/.ssh/config; \
    if [ ! -L "/etc/cron.d" ]; then exit 1; fi; \
    echo;

ENV PATH=/root/.local/bin:/opt/venv/bin:/opt/fluent-bit/bin:$PATH
ENV TZ=Asia/Shanghai
ENV PYTHONDONTWRITEBYTECODE=1

WORKDIR /apps/data
COPY apps/ /apps/
ENTRYPOINT ["tini", "--"]
CMD ["sh", "-c", "bash /apps/.entry.sh"]

LABEL org.opencontainers.image.source=https://github.com/lwmacct/250209-cr-gitrce
LABEL org.opencontainers.image.description="专为 VSCode 容器开发环境构建"
LABEL org.opencontainers.image.licenses=MIT
