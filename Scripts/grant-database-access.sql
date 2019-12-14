SELECT @@version

USE sqldbname

select name,sid,issqluser from sys.sysusers

IF NOT EXISTS(SELECT name FROM sys.database_principals WHERE name = 'username')
BEGIN 
	CREATE USER [username] FROM EXTERNAL PROVIDER;
END
ALTER ROLE db_datareader ADD MEMBER [username];
ALTER ROLE db_datawriter ADD MEMBER [username];
ALTER ROLE db_ddladmin ADD MEMBER [username];

--GO