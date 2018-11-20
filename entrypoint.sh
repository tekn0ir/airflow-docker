#!/usr/bin/env bash
set -xe

TRY_LOOP="60"

AIRFLOW__CORE__FERNET_KEY=${FERNET_KEY:=$(python3.6 -c "from cryptography.fernet import Fernet; FERNET_KEY = Fernet.generate_key().decode(); print(FERNET_KEY)")}

wait_for_port() {
  local name="$1" host="$2" port="$3"
  local j=0
  while ! nc -z -w 4 "$host" "$port" >/dev/null 2>&1 < /dev/null; do
    j=$((j+1))
    if [ $j -ge $TRY_LOOP ]; then
      echo >&2 "$(date) - $host:$port still not reachable, giving up"
      exit 1
    fi
    echo "$(date) - waiting for $name($host:$port)... $j/$TRY_LOOP"
    sleep 1
  done
}

if [[ $POSTGRES_ENABLED ]]; then
    wait_for_port "Postgres" "$POSTGRES_HOST" "$POSTGRES_PORT"
fi

# Task
case "$1" in
  webserver)
    exec airflow webserver
    ;;
  worker|scheduler)
    exec airflow "$@"
    ;;
  version)
    exec airflow "$@"
    ;;
  *)
    bash -cx "$@"
    ;;
esac