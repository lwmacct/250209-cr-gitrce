#!/bin/bash
# Admin https://www.yuque.com/lwmacct

__main() {
  mkdir -p /apps/data/logs
  cat >/etc/supervisord.conf <<EOF
[unix_http_server]
file=/run/supervisord.sock
chmod=0700
chown=nobody:nogroup

[supervisord]
user=root
nodaemon=true
logfile=/var/log/supervisord.log
logfile_maxbytes=5MB
logfile_backups=2
pidfile=/var/run/supervisord.pid

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///run/supervisord.sock
prompt=mysupervisor
history_file=~/.sc_history

[include]
files = /etc/supervisor/conf.d/*.conf /apps/data/.gitrce/supervisor.d/*.conf
EOF

  cat >/etc/supervisor/conf.d/cron.conf <<EOF
[program:cron]
command=cron -f
autostart=true
autorestart=true
startretries=3
user=root
redirect_stderr=true
stdout_logfile=/apps/data/logs/cron.stdout.log
stdout_logfile_maxbytes=50MB
stdout_logfile_backups=10
stderr_logfile=/apps/data/logs/cron.stderr.log
stderr_logfile_maxbytes=50MB
stderr_logfile_backups=10
environment=TERM="xterm"
EOF

  cat >/etc/supervisor/conf.d/gitrce.conf <<EOF
[program:gitrce]
command=/apps/.gitrce.sh
autostart=true
autorestart=true
startretries=3
user=root
redirect_stderr=true
stdout_logfile=/apps/data/logs/gitrce.stdout.log
stdout_logfile_maxbytes=50MB
stdout_logfile_backups=10
stderr_logfile=/apps/data/logs/gitrce.stderr.log
stderr_logfile_maxbytes=50MB
stderr_logfile_backups=10
environment=TERM="xterm"
EOF

  exec supervisord

}

__main
