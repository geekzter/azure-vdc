-- Should run in content database
DECLARE @sql VARCHAR(4096)
SELECT @@version

IF NOT EXISTS(SELECT name FROM sys.database_principals WHERE name = '@msi_name')
BEGIN 
	-- BUG: 'AADSTS65002: Consent between first party applications and resources must be configured via preauthorization
	--      Graph Access required to look up user by name
	--CREATE USER [@msi_name] FROM EXTERNAL PROVIDER; 

	-- HACK: Using Object ID, no Graph lookup is required
	SELECT @sql = 'CREATE USER [@msi_name] WITH SID = @msi_sid, TYPE=X'
	EXEC (@sql)
END
ALTER ROLE db_datareader ADD MEMBER [@msi_name];
ALTER ROLE db_datawriter ADD MEMBER [@msi_name];
ALTER ROLE db_ddladmin ADD MEMBER [@msi_name];

SELECT name 
FROM sys.sysusers 
WHERE altuid is NULL AND issqluser=0
ORDER BY name asc