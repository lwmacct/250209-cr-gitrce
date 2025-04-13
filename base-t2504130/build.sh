#!/usr/bin/env bash
# shellcheck disable=SC2317

# Admin https://www.yuque.com/lwmacct
# document https://www.yuque.com/lwmacct/dockerfile/dockerfile-builder

# exit 0
__main() {
    # 准备工作
    _sh_path=$(realpath "$(ps -p $$ -o args= 2>/dev/null | awk '{print $2}')") # 当前脚本路径
    _pro_name=$(echo "$_sh_path" | awk -F '/' '{print $(NF-2)}')               # 当前项目名
    _dir_name=$(echo "$_sh_path" | awk -F '/' '{print $(NF-1)}')               # 当前目录名
    _image="${_pro_name}:$_dir_name"

    # 生成Dockerfile
    {
        #  生成Dockerfile
        cd "$(dirname "$_sh_path")" || exit 1
        cat >Dockerfile <<"EOF"
FROM gcr.io/etcd-development/etcd:v3.5.17 AS etcd
FROM victoriametrics/vmagent:v1.108.1 AS vmagent

FROM registry.cn-hangzhou.aliyuncs.com/lwmacct/ubuntu:noble-t2412300
COPY --from=etcd /usr/local/bin/etcdctl /usr/local/bin/etcdctl
COPY --from=vmagent /vmagent-prod /usr/local/bin/vmagent

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

RUN set -eux; \
    echo "docker-ce-cli https://docs.docker.com/engine/install/ubuntu"; \
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
    echo "python"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        python3 python3-pip python3-venv python3-dotenv \
        python3-docker python3-dockerpty python3-dockerpycreds \
        python3-watchdog python3-psutil python3-cpuinfo python3-ping3 python3-schedule python3-pexpect \
        python3-nftables python3-pyudev python3-dmidecode \
        python3-paramiko python3-dnspython python3-scapy python3-netifaces python3-pysnmp-lextudio python3-plumbum \
        python3-etcd3 python3-redis python3-influxdb-client python3-apsw \
        python3-websockets python3-httpx python3-fastapi python3-uvicorn python3-pydantic \
        python3-requests python3-requests-unixsocket python3-requests-toolbelt python3-requests-oauthlib \
        python3-openssl python3-cryptography python3-bcrypt \
        python3-yaml python3-jinja2 python3-protobuf \
        python3-numpy python3-pandas \
        python3-prometheus-client python3-pyghmi \
        python3-urwid python3-urwid-readline python3-urwidtrees python3-urwid-utils \
        python3-rich python3-rich-click python3-textual; \
    echo "包安装"; \
    apt-get install -y --no-install-recommends \
        redis virt-what freeipmi; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*;

RUN set -eux; \
    rm -rf /etc/cron.d/; \
    ln -sf /apps/data/.gitrce/cron.d/ /etc/cron.d; \
    if [ ! -L "/etc/cron.d" ]; then exit 1; fi; \
    mkdir -p /root/.ssh; \
    chmod 700 /root/.ssh; \
    echo "StrictHostKeyChecking no" >> /root/.ssh/config; \
    echo;

RUN set -eux; \
    echo "安装 fluent-bit"; \
    curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*;

COPY apps/ /apps/
WORKDIR /apps/data
ENTRYPOINT ["tini", "--","sh", "-c", "bash /apps/.entry.sh & exec cron -f"]
EOF
        sed -i "s/SED_REPLACE/$_image/g" Dockerfile
    }

    # 打包进行
    {
        cd "$(dirname "$_sh_path")" || exit 1
        # 开始构建
        jq 'del(.credsStore)' ~/.docker/config.json | sponge ~/.docker/config.json

        _registry="ghcr.io/lwmacct"
        _repository="$_registry/$_image"

        docker buildx use default
        docker buildx build --platform linux/amd64 -t "$_repository" --network host --progress plain --load . && {
            if false; then
                docker rm -f sss
                docker run -itd --name=sss \
                    --ipc=host \
                    --network=host \
                    --cgroupns=host \
                    --privileged=true \
                    --security-opt apparmor=unconfined \
                    "$_repository"
                docker exec -it sss bash
            fi
        }
        docker push "$_repository"

    }
}

__main

__help() {
    cat >/dev/null <<"EOF"

ghcr.io/lwmacct/250209-cr-gitrce:base-t2504130

EOF
}
