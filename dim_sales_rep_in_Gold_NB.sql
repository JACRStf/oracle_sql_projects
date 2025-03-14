%%sql

CREATE OR REPLACE TABLE de_lh_400_Gold.dim_sales_rep USING DELTA AS

SELECT *
FROM (
    SELECT jrs.SalesRep_ID
        , jrs.SalesRep_Number AS Sales_Rep_Number
        , jrs.Name AS Sales_Rep
        , jrs.Email_Address AS Email_Address
        , tit.MEANING AS Title
        -- , res.ATTRIBUTE2 AS Sales_Rep_Div
        -- , res.ATTRIBUTE3 AS Sales_Rep_Plant
        -- , plt.MEANING AS Sales_Rep_Plant
        -- , tm.MEANING AS Sales_Rep_Team
        , REPLACE(ttl.Team_Name, ' Team', '') AS Team
        , REPLACE(ttl.team_desc, ' Team', '') AS Rollup_Team
        , mgr.DESCRIPTION AS Manager
        , TM.DELETE_FLAG
        , jrs.Person_ID
        , ROW_NUMBER() OVER(PARTITION BY SalesRep_Id ORDER BY tm.delete_flag) AS r
    FROM de_lh_300_Silver.oracle_jtf_rs_salesreps jrs
        LEFT JOIN de_lh_300_Silver.oracle_jtf_rs_resource_extns_vl res ON jrs.resource_id = res.resource_id
        LEFT JOIN de_lh_300_Silver.oracle_jtf_objects_vl obj ON res.category = obj.object_code
        LEFT JOIN de_lh_300_Silver.oracle_fnd_lookup_values tit ON res.ATTRIBUTE1 = tit.LOOKUP_CODE AND tit.END_DATE_ACTIVE IS NULL AND tit.ENABLED_FLAG = 'Y' AND tit.LOOKUP_TYPE = 'WSB_SALESREP_TITLES'
        LEFT JOIN de_lh_300_Silver.oracle_fnd_lookup_values plt ON res.ATTRIBUTE3 = plt.LOOKUP_CODE AND plt.END_DATE_ACTIVE IS NULL AND plt.ENABLED_FLAG = 'Y' AND plt.LOOKUP_TYPE = 'WSB_PLANTS'
        LEFT JOIN de_lh_300_Silver.oracle_fnd_lookup_values tm ON res.ATTRIBUTE4 = tm.LOOKUP_CODE AND tm.END_DATE_ACTIVE IS NULL AND tm.ENABLED_FLAG = 'Y' AND tm.LOOKUP_TYPE = 'WSB_SALES_TEAMS'
        LEFT JOIN de_lh_300_Silver.oracle_fnd_lookup_values mgr ON tm.TAG = mgr.LOOKUP_CODE AND mgr.END_DATE_ACTIVE IS NULL AND mgr.ENABLED_FLAG = 'Y' AND mgr.LOOKUP_TYPE = 'WSB_SALES_TEAM_MGRS'
        LEFT JOIN de_lh_300_Silver.oracle_jtf_rs_team_members tm ON jrs.resource_id = tm.team_resource_id
        LEFT JOIN de_lh_300_Silver.oracle_jtf_rs_teams_tl ttl ON tm.team_id = ttl.team_id
    ) x
WHERE r = 1