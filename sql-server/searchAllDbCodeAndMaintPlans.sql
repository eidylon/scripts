DECLARE @SearchString NVARCHAR(4000) = N'search string here';

IF OBJECT_ID('tempdb..#RESULTS') IS NOT NULL DROP TABLE #RESULTS;
CREATE TABLE #RESULTS (FOUNDIN VARCHAR(500));

DECLARE @SQL NVARCHAR(MAX) = N'';

-- === User DB code ===
SELECT @SQL = @SQL + '
USE [' + name + '];

INSERT INTO #RESULTS (FOUNDIN)
SELECT 
    ''DB: ' + name + ' | '' + o.type_desc + '' | '' + o.name
FROM sys.sql_modules m
JOIN sys.objects o ON m.object_id = o.object_id
WHERE m.definition LIKE ''%' + REPLACE(@SearchString, '''', '''''') + '%''
'
FROM sys.databases
WHERE state_desc = 'ONLINE'
  AND database_id > 4;

EXEC (@SQL);

-- === SQL Agent job steps ===
INSERT INTO #RESULTS (FOUNDIN)
SELECT 
    'SQLAgent Job: ' + j.name + ' | Step: ' + s.step_name
FROM msdb.dbo.sysjobsteps s
JOIN msdb.dbo.sysjobs j ON s.job_id = j.job_id
WHERE s.command LIKE '%' + @SearchString + '%';

-- === Maintenance plans (fixed conversion) ===
INSERT INTO #RESULTS (FOUNDIN)
SELECT 
    'Maintenance Plan: ' + p.name
FROM msdb.dbo.sysssispackages p
WHERE CAST(CAST(p.packagedata AS VARBINARY(MAX)) AS NVARCHAR(MAX)) 
      LIKE '%' + @SearchString + '%';

-- === Final ===
SELECT * FROM #RESULTS;
