#!/bin/bash
#
#  ASH Reporting should not allow access to other AWR functionality.
#  Therefore we create a wrapper around the supplied DBMS_WORKLOAD_REPOSITORY package
#  to only expose that particular function.

. ~/.bash_profile

sqlplus -s / as sysdba << EOF

WHENEVER SQLERROR EXIT FAILURE;

GRANT EXECUTE ON dbms_workload_repository TO delius_user_support;

CREATE OR REPLACE PACKAGE delius_user_support.ash_report_wrapper AS
    FUNCTION ash_report_html (
        l_dbid         IN NUMBER,
        l_inst_num     IN NUMBER,
        l_btime        IN DATE,
        l_etime        IN DATE,
        l_options      IN NUMBER DEFAULT 0,
        l_slot_width   IN NUMBER DEFAULT 0,
        l_sid          IN NUMBER DEFAULT NULL,
        l_sql_id       IN VARCHAR2 DEFAULT NULL,
        l_wait_class   IN VARCHAR2 DEFAULT NULL,
        l_service_hash IN NUMBER DEFAULT NULL,
        l_module       IN VARCHAR2 DEFAULT NULL,
        l_action       IN VARCHAR2 DEFAULT NULL,
        l_client_id    IN VARCHAR2 DEFAULT NULL,
        l_plsql_entry  IN VARCHAR2 DEFAULT NULL,
        l_data_src     IN NUMBER DEFAULT 0,
        l_container    IN VARCHAR2 DEFAULT NULL
    ) RETURN awrrpt_html_type_table
        PIPELINED;

END;
/

CREATE OR REPLACE PACKAGE BODY delius_user_support.ash_report_wrapper AS

    FUNCTION ash_report_html (
        l_dbid         IN NUMBER,
        l_inst_num     IN NUMBER,
        l_btime        IN DATE,
        l_etime        IN DATE,
        l_options      IN NUMBER DEFAULT 0,
        l_slot_width   IN NUMBER DEFAULT 0,
        l_sid          IN NUMBER DEFAULT NULL,
        l_sql_id       IN VARCHAR2 DEFAULT NULL,
        l_wait_class   IN VARCHAR2 DEFAULT NULL,
        l_service_hash IN NUMBER DEFAULT NULL,
        l_module       IN VARCHAR2 DEFAULT NULL,
        l_action       IN VARCHAR2 DEFAULT NULL,
        l_client_id    IN VARCHAR2 DEFAULT NULL,
        l_plsql_entry  IN VARCHAR2 DEFAULT NULL,
        l_data_src     IN NUMBER DEFAULT 0,
        l_container    IN VARCHAR2 DEFAULT NULL
    ) RETURN awrrpt_html_type_table
        PIPELINED
    AS
    BEGIN
        FOR rec IN (
            SELECT
                output
            FROM
                TABLE ( dbms_workload_repository.ash_report_html(l_dbid => l_dbid, l_inst_num => l_inst_num, l_btime => l_btime, 
                                                                l_etime => l_etime, l_options => l_options,
                                                                l_slot_width => l_slot_width, l_sid => l_sid, l_sql_id => l_sql_id, 
                                                                l_wait_class => l_wait_class, l_service_hash => l_service_hash,
                                                                l_module => l_module, l_action => l_action, l_client_id => l_client_id,
                                                                l_plsql_entry => l_plsql_entry, l_data_src => l_data_src,
                                                                l_container => l_container) )
        ) LOOP
            PIPE ROW ( awrrpt_html_type(rec.output) );
        END LOOP;
    END ash_report_html;

END ash_report_wrapper;
/

GRANT EXECUTE ON delius_user_support.ash_report_wrapper TO delius_ash_role;

EXIT
EOF