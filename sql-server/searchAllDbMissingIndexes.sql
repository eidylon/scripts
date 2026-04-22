SELECT
    d.name AS DatabaseName,
    OBJECT_NAME(mid.object_id, mid.database_id) AS TableName,
    migs.user_seeks,
    migs.user_scans,
    migs.avg_total_user_cost,
    migs.avg_user_impact,
    (migs.user_seeks + migs.user_scans) * migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) AS EstimatedImpactScore,
    
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns,

    'CREATE INDEX IX_' 
        + OBJECT_NAME(mid.object_id, mid.database_id) + '_'
        + REPLACE(REPLACE(ISNULL(mid.equality_columns,''), ', ', '_'), '[','')
        + ' ON ' + mid.statement
        + ' (' + ISNULL(mid.equality_columns,'')
        + CASE WHEN mid.inequality_columns IS NOT NULL THEN 
            CASE WHEN mid.equality_columns IS NOT NULL THEN ', ' ELSE '' END + mid.inequality_columns
          ELSE '' END + ')'
        + ISNULL(' INCLUDE (' + mid.included_columns + ')', '') AS CreateIndexStatement

FROM sys.dm_db_missing_index_group_stats migs
JOIN sys.dm_db_missing_index_groups mig
    ON migs.group_handle = mig.index_group_handle
JOIN sys.dm_db_missing_index_details mid
    ON mig.index_handle = mid.index_handle
JOIN sys.databases d
    ON d.database_id = mid.database_id

WHERE d.state_desc = 'ONLINE'
  AND d.database_id > 4  -- user DBs only

ORDER BY EstimatedImpactScore DESC;
