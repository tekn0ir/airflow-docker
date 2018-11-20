FROM python:3.6-slim as airflow-base
LABEL maintainer="Anders Åslund <anders.aslund@teknoir.se>"

ENV DEBIAN_FRONTEND noninteractive
ENV TERM linux

# Airflow
ARG AIRFLOW_VERSION=1.10.1rc2
ARG AIRFLOW_DEPS=""
ARG PYTHON_DEPS=""
ENV AIRFLOW_HOME=/usr/local/airflow
ENV AIRFLOW_GPL_UNIDECODE yes

# Define en_US.
ENV LANGUAGE en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV LC_CTYPE en_US.UTF-8
ENV LC_MESSAGES en_US.UTF-8

RUN set -ex \
    && buildDeps=' \
        freetds-dev \
        python3-dev \
        libkrb5-dev \
        libsasl2-dev \
        libssl-dev \
        libffi-dev \
        libpq-dev \
        git \
    ' \
    && apt-get update -yqq \
    && apt-get upgrade -yqq \
    && apt-get install -yqq --no-install-recommends \
        $buildDeps \
        freetds-bin \
        build-essential \
        python3-pip \
        python3-requests \
        default-libmysqlclient-dev \
        apt-utils \
        curl \
        rsync \
        netcat \
        locales \
    && sed -i 's/^# en_US.UTF-8 UTF-8$/en_US.UTF-8 UTF-8/g' /etc/locale.gen \
    && locale-gen \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    && useradd -ms /bin/bash -d ${AIRFLOW_HOME} airflow \
    && pip install -U pip setuptools wheel \
    && pip install pytz \
    && pip install pyOpenSSL \
    && pip install ndg-httpsclient \
    && pip install pyasn1 \
    && pip install apache-airflow[crypto,postgres,hive,jdbc,kubernetes,async,hdfs,password,ssh${AIRFLOW_DEPS:+,}${AIRFLOW_DEPS}]==${AIRFLOW_VERSION} \
    && if [ -n "${PYTHON_DEPS}" ]; then pip install ${PYTHON_DEPS}; fi \
    && apt-get purge --auto-remove -yqq $buildDeps \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/* \
        /usr/share/man \
        /usr/share/doc \
        /usr/share/doc-base

COPY entrypoint.sh /entrypoint.sh

RUN chown -R airflow: ${AIRFLOW_HOME}

EXPOSE 8080 5555 8793

USER airflow
WORKDIR ${AIRFLOW_HOME}
ENTRYPOINT ["/entrypoint.sh"]
CMD ["webserver"]

###################################
FROM airflow-base as airflow-rs

USER root
RUN set -ex \
    && mkdir -p /usr/share/man/man1 \
    && apt-get update -yqq \
    && apt-get upgrade -yqq \
    && apt-get install -yqq --no-install-recommends \
        git \
        openjdk-8-jre-headless \
    && pip install prometheus_client \
    && pip install awscli \
    && pip install JayDeBeApi==1.1.1 \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/* \
        /usr/share/man \
        /usr/share/doc \
        /usr/share/doc-base

# Patches
RUN sed -i.bak s/"supports_autocommit = True"/"supports_autocommit = False"/ /usr/local/lib/python3.6/site-packages/airflow/hooks/jdbc_hook.py
RUN sed -i.bak s/"'readOnly': True"/"'readOnly': False"/ /usr/local/lib/python3.6/site-packages/airflow/contrib/kubernetes/worker_configuration.py

# Add prometheus exporter
RUN git clone https://github.com/epoch8/airflow-exporter ${AIRFLOW_HOME}/plugins/prometheus_exporter

# Copy Redshift Jdbc driver into container
RUN mkdir -p ${AIRFLOW_HOME}/drivers
RUN curl -fsSL https://s3.amazonaws.com/redshift-downloads/drivers/jdbc/1.2.15.1025/RedshiftJDBC42-no-awssdk-1.2.15.1025.jar -o ${AIRFLOW_HOME}/drivers/RedshiftJDBC42-no-awssdk-1.2.15.1025.jar

RUN chown -R airflow.airflow ${AIRFLOW_HOME}
USER airflow

###################################
FROM airflow-rs as airflow-example-dags

RUN set -ex \
    && mkdir -p /usr/local/airflow/dags \
    && cd /usr/local/airflow/dags \
    && curl -L -s -N https://github.com/apache/incubator-airflow/raw/master/airflow/contrib/example_dags/example_kubernetes_executor.py -o example_kubernetes_executor.py \
    && curl -L -s -N https://github.com/apache/incubator-airflow/raw/master/airflow/contrib/example_dags/example_kubernetes_executor_config.py -o example_kubernetes_executor_config.py \
    && curl -L -s -N https://github.com/apache/incubator-airflow/raw/master/airflow/contrib/example_dags/example_kubernetes_operator.py -o example_kubernetes_operator.py \
    && curl -L -s -N https://github.com/apache/incubator-airflow/raw/master/airflow/example_dags/example_bash_operator.py -o example_bash_operator.py \
    && curl -L -s -N https://github.com/apache/incubator-airflow/raw/master/airflow/example_dags/example_branch_operator.py -o example_branch_operator.py \
    && curl -L -s -N https://github.com/apache/incubator-airflow/raw/master/airflow/example_dags/example_python_operator.py -o example_python_operator.py \
    && curl -L -s -N https://github.com/apache/incubator-airflow/raw/master/airflow/example_dags/example_latest_only.py -o example_latest_only.py \
    && curl -L -s -N https://github.com/apache/incubator-airflow/raw/master/airflow/example_dags/example_trigger_controller_dag.py -o example_trigger_controller_dag.py