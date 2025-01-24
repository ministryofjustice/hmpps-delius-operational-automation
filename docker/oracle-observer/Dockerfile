FROM ghcr.io/oracle/oraclelinux8-instantclient:19


ENV ORACLE_BASE=/u01/app/oracle
ENV ORACLE_HOME=${ORACLE_BASE}/product/19.3.0/client

RUN groupadd oinstall

RUN useradd oracle -G oinstall

RUN chown -R oracle:oinstall /home/oracle && \
    usermod -d /home/oracle oracle && \
    usermod -s /bin/bash oracle

RUN dnf -y install make binutils glibc-devel zip less jq

RUN mkdir -p ${ORACLE_HOME} && \
    chown -R oracle:oinstall /u01

COPY --chown=oracle:oinstall LINUX.X64_193000_client.zip /opt

WORKDIR /opt

RUN unzip LINUX.X64_193000_client.zip

RUN echo "inventory_loc=/u01/app/oracle/oraInventory" > /etc/oraInst.loc
RUN echo "inst_group=oinstall" >> /etc/oraInst.loc

# Install v2 of AWS CLI (v1 is installed by default)
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
RUN unzip awscliv2.zip
RUN /opt/aws/install

USER oracle:oinstall

WORKDIR /home/oracle

RUN echo "export ORACLE_BASE=${ORACLE_BASE}" > .bash_profile
RUN echo "export ORACLE_HOME=${ORACLE_HOME}" >> .bash_profile
RUN echo "export PATH=\$PATH:\$ORACLE_HOME/bin" >> .bash_profile
RUN echo "export LD_LIBRARY_PATH=\$ORACLE_HOME/lib:/lib:/usr/lib" >> .bash_profile
RUN chmod u+x .bash_profile

# We treat a return code of 6 as success since that is only an ignorable warning -> convert to 0 to continue
RUN export CV_ASSUME_DISTID=OEL7.8 && \
    /opt/client/runInstaller -silent -ignoreSysPrereqs -waitForCompletion ORACLE_BASE=${ORACLE_BASE} ORACLE_HOME=${ORACLE_HOME} INSTALL_TYPE="Administrator" || [ $? -eq 6 ]

USER root

RUN ${ORACLE_HOME}/root.sh
RUN rm -rf /opt/client
RUN rm -rf /opt/aws

COPY sqlnet.ora ${ORACLE_HOME}/network/admin
RUN chown oracle:oracle ${ORACLE_HOME}/network/admin/sqlnet.ora
COPY configure_tnsnames.sh /home/oracle/configure_tnsnames.sh
RUN chown oracle:oracle /home/oracle/configure_tnsnames.sh && chmod +x /home/oracle/configure_tnsnames.sh
COPY create_wallet.sh /home/oracle/create_wallet.sh
RUN chown oracle:oracle /home/oracle/create_wallet.sh && chmod +x /home/oracle/create_wallet.sh
COPY run_observer.sh /home/oracle/run_observer.sh
RUN chown oracle:oracle /home/oracle/run_observer.sh && chmod +x /home/oracle/run_observer.sh

USER oracle:oinstall

# Dummy command to keep container running during development
# CMD ["/bin/bash","-c","/home/oracle/configure_tnsnames.sh; /home/oracle/create_wallet.sh; /home/oracle/run_observer.sh"]
CMD ["/bin/bash","-c","/home/oracle/configure_tnsnames.sh; /home/oracle/create_wallet.sh; sleep 14400"]