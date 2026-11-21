--// JOBS STARTED BY THIS SESSION
SELECT
    j.name AS JOB_NAME,
    ja.run_requested_date AS REQUESTED,
    ja.start_execution_date AS STARTED,
    ja.stop_execution_date AS STOPPED, 
    CASE
        WHEN ja.stop_execution_date IS NULL THEN 'RUNNING'
        ELSE 'COMPLETED'
    END AS STATUS
FROM msdb.dbo.sysjobactivity ja
JOIN msdb.dbo.sysjobs j ON j.job_id = ja.job_id
WHERE /*j.name like 'Nightly%' AND*/ ja.session_id = (
    SELECT MAX(session_id)
    FROM msdb.dbo.syssessions
)
AND ja.start_execution_date IS NOT NULL
ORDER BY ja.start_execution_date DESC;
