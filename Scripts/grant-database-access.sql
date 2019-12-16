SELECT @@version

IF NOT EXISTS(SELECT name FROM sys.database_principals WHERE name = 'username')
BEGIN 
	CREATE USER [username] FROM EXTERNAL PROVIDER;
END
ALTER ROLE db_datareader ADD MEMBER [username];
ALTER ROLE db_datawriter ADD MEMBER [username];
ALTER ROLE db_ddladmin ADD MEMBER [username];

SELECT name 
FROM sys.sysusers 
WHERE altuid is NULL AND issqluser=0
ORDER BY name asc