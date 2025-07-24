#!/bin/bash
# Admin https://www.yuque.com/lwmacct

__network() {
  if [ ! -d "/host/proc/1/ns/" ]; then
    unset _netns
    return
  fi

  if ! ping 223.5.5.5 -c1 -W1 >/dev/null 2>&1; then
    _netns='nsenter --net=/host/proc/1/ns/net'
  else
    unset _netns
  fi
}

__init_ssh() {
  if [ ! -d "/root/.ssh" ]; then
    mkdir -p /apps/data/.ssh
    chmod 700 /apps/data/.ssh
    ln -sf /apps/data/.ssh /root/.ssh
    # 连接新设备时不提示指纹信息
    echo "StrictHostKeyChecking no" >>/root/.ssh/config
  fi

  if [[ -f "/root/.ssh/id_ed25519" ]]; then
    if [[ "${SSH_SECRET_KEY}" != "" && "${SSH_OVERWRITE}" == "1" ]]; then # 如果存在秘钥, 并且设置了覆盖, 则覆盖
      echo "$SSH_SECRET_KEY" | base64 -d >/root/.ssh/id_ed25519
      chmod 600 /root/.ssh/id_ed25519
      ssh-keygen -y -f /root/.ssh/id_ed25519 >/root/.ssh/id_ed25519.pub
      chmod 644 /root/.ssh/id_ed25519.pub
    fi
  else
    if [[ "${SSH_SECRET_KEY}" != "" ]]; then # 如果不存在秘钥, 则创建
      echo "$SSH_SECRET_KEY" | base64 -d >/root/.ssh/id_ed25519
      chmod 600 /root/.ssh/id_ed25519
      ssh-keygen -y -f /root/.ssh/id_ed25519 >/root/.ssh/id_ed25519.pub
      chmod 644 /root/.ssh/id_ed25519.pub
    else
      ssh-keygen -t ed25519 -N '' -f /root/.ssh/id_ed25519 -C 'lwmacct'
    fi
  fi
}
# __init_ssh

__git_fetch() {
  __network
  cd /apps/data/.gitrce || service cron restart
  find /apps/data/.gitrce/.git -maxdepth 3 -name '*.lock' -print0 | xargs -0 -r rm -f
  $_netns git clean -fd
  _git_fetch=$($_netns git fetch --prune 2>&1)
  $_netns git reset --hard HEAD
  _git_branch=$($_netns git branch -r 2>/dev/null | awk '{print $NF}' | head -n1)

  if [[ "$(echo "$_git_fetch" | grep '^fatal:.*git/index:' -Ec)" == "1" ]]; then
    # 如果索引存在致命错误, 则删除本地仓库, 重新拉取
    rm -rf /apps/data/.gitrce
    service cron restart
  fi

  if [[ "${_git_branch}" != "" ]]; then
    # 如果分支不为空, 则切换到该分支
    $_netns git reset --hard "$_git_branch"
    $_netns git checkout "$(echo "$_git_branch" | awk -F '/' '{print $NF}')"
    $_netns git branch --set-upstream-to="$_git_branch"
  else
    rm -rf /apps/data/.gitrce
    service cron restart
  fi
}

__init_git() {
  export LANG=C.UTF-8             # 不设置会出大问题
  DOCKER_LOGS="${DOCKER_LOGS:-0}" #  是否开启 /dev/logs 日志管道, 0:不开启 1:开启
  INTERVAL_MIN="${INTERVAL_MIN:-500}"
  INTERVAL_MAX="${INTERVAL_MAX:-600}"
  ALLOW_NOT_LATEST="${ALLOW_NOT_LATEST:-1}" # 默认允许仓库不是最新的
  GIT_LOCK="${GIT_LOCK:-0}"                 # 是否锁定第一次获取后的版本 0:不锁定 1:启动更新时更新 2:锁定

  if [[ "${GIT_REMOTE_REPO}" == "" ]]; then
    echo "GIT_REMOTE_REPO is empty"
    return
  fi

  # 创建软链接
  {
    mkdir -p /apps/data/.gitrce
    cd /apps || service cron restart # 必须在能站稳的目录下
    if [ -L "/apps/gitrce" ]; then rm "/apps/gitrce"; fi
    ln -sf /apps/data/.gitrce /apps/gitrce
  }

  # clone 仓库
  {
    __network # 检查网络
    # 空仓库下载
    cd /apps/data/.gitrce || mkdir -p /apps/data/.gitrce
    if [[ "$($_netns git remote get-url origin)" == "" ]]; then
      cd /apps || mkdir -p /apps
      rm -rf /apps/data/.gitrce
      mkdir -p /apps/data/.gitrce
      $_netns git clone --depth=1 "$GIT_REMOTE_REPO" /apps/data/.gitrce
    fi

    # 仓库不一致重新下载
    cd /apps/data/.gitrce || mkdir -p /apps/data/.gitrce
    if [[ "$GIT_REMOTE_REPO" != "$($_netns git remote get-url origin)" ]]; then
      cd /apps || mkdir -p /apps
      rm -rf /apps/data/.gitrce
      mkdir -p /apps/data/.gitrce
      $_netns git clone --depth=1 "$GIT_REMOTE_REPO" /apps/data/.gitrce
    fi
  }

  if [ ! -f "/apps/data/.gitrce/boot/start.sh" ]; then __git_fetch; fi
  if [ ! -f "/apps/data/.gitrce/boot/start.sh" ]; then service cron restart; fi

  # 允许更新一次
  if [[ "$GIT_LOCK" == "1" ]]; then
    __git_fetch
    if [[ "$(cd /apps/data/.gitrce && $_netns git pull 2>&1 | grep '^Already up to date.$' -c)" != "0" || "$ALLOW_NOT_LATEST" == "1" ]]; then
      echo "开始运行 boot/start.sh"
      nohup timeout "$INTERVAL_MIN" bash /apps/data/.gitrce/boot/start.sh >/dev/null 2>&1 &
    else
      echo "无法获取最新代码, 而且不允许旧代码启动"
      service cron restart
    fi
    return # 不再继续执行
  fi

  # 锁定版本
  if [[ "$GIT_LOCK" == "2" ]]; then
    echo "GIT_LOCK=1, 版本锁定, 不会自动更新"
    nohup timeout "$INTERVAL_MIN" bash /apps/data/.gitrce/boot/start.sh >/dev/null 2>&1 &
    return # 不再继续执行
  fi

  # 其他情况更新一次后启动
  __git_fetch
  nohup timeout "$INTERVAL_MIN" bash /apps/data/.gitrce/boot/start.sh >/dev/null 2>&1 &

  while true; do
    # shellcheck disable=SC1091
    source /apps/data/.gitrce/boot/env.sh 2>/dev/null
    # shellcheck disable=SC1091
    source /apps/data/.gitrce_env.sh 2>/dev/null
    __git_fetch
    if [[ "$(echo "$_git_fetch" | grep '^From' -c)" != "0" ]]; then nohup timeout "$INTERVAL_MIN" bash /apps/data/.gitrce/boot/update.sh >/dev/null 2>&1 & fi
    sleep "$(shuf -i "$INTERVAL_MIN-$INTERVAL_MAX" -n 1)"
  done

}

mkdir -p /apps/data/logs
{
  __init_ssh
  __init_git
}
