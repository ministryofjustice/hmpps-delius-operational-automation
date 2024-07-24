FROM python:3.10-alpine

# Basic tools for now
RUN apk add --update --no-cache bash ca-certificates git build-base libffi-dev openssl-dev gcc musl-dev gcc g++ linux-headers build-base openldap-dev python3-dev

RUN python3 -m pip install --upgrade pip
## related to https://github.com/oracle/python-oracledb/issues/204 - pip version fails to install due to cpython3
# ignore whilst in dev

# RUN python3 -m pip install git+https://github.com/oracle/python-oracledb.git

RUN python3 -m pip install git+https://github.com/ministryofjustice/hmpps-ldap-automation-cli.git@v0.17.0-dev.1

CMD ["ldap-automation"]
