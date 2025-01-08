FROM ghcr.io/oracle/oraclelinux8-instantclient:19


ENV ORACLE_BASE=/u01/app/oracle
ENV ORACLE_HOME=${ORACLE_BASE}/product/19.3.0/client

RUN groupadd oinstall

RUN useradd oracle -G oinstall

RUN chown -R oracle:oinstall /home/oracle && \
    usermod -d /home/oracle oracle && \
    usermod -s /bin/bash oracle

RUN dnf -y install make binutils glibc-devel zip

RUN mkdir -p ${ORACLE_HOME} && \
    chown -R oracle:oinstall /u01

COPY --chown=oracle:oinstall LINUX.X64_193000_client.zip /opt

WORKDIR /opt

RUN unzip LINUX.X64_193000_client.zip

RUN echo "inventory_loc=/u01/app/oracle/oraInventory" > /etc/oraInst.loc
RUN echo "inst_group=oinstall" >> /etc/oraInst.loc

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

RUN /u01/app/oraInventory/orainstRoot.sh
RUN rm -rf /opt/client

USER oracle:oinstall

CMD ["bash"]






# mkdir -p /u01/app/oracle/product/19.3/client
# chown oracle:oracle -R /u01
# 35  dnf -y install make
# 40  dnf -y install binutils
# 44  dnf -y install glibc-devel
# 19  useradd -m -d /home/oracle -s /bin/bash oracle
# vi /etc/oraInst.loc
# inventory_loc=/u01/app/oracle/oraInventory
# inst_group=oinstall

# 12  cd /opt
# 13  cp /downloads/LINUX.X64_193000_client.zip .
# 15  dnf -y install make binutils glibc-devel zip
# 16  unzip LINUX.X64_193000_client.zip

# export CV_ASSUME_DISTID=OEL7.8
# # /

# client/runInstaller  -silent -responseFile /client/response/client_install.rsp -ignoreSysPrereqs ORACLE_BASE=/u01/app/oracle ORACLE_HOME=/u01/app/oracle/product/19.3/client INSTALL_TYPE="Administrator"

# /opt/client/runInstaller  -silent -ignoreSysPrereqs ORACLE_BASE=/u01/app/oracle ORACLE_HOME=/u01/app/oracle/product/19.3/client INSTALL_TYPE="Administrator"