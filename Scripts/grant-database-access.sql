SELECT @@version

USE sqldbname

select name,sid,issqluser from sys.sysusers

IF NOT EXISTS(SELECT name FROM sys.database_principals WHERE name = 'spname')
BEGIN 
	CREATE USER [spname] FROM EXTERNAL PROVIDER;
END
ALTER ROLE db_datareader ADD MEMBER [spname];
ALTER ROLE db_datawriter ADD MEMBER [spname];
ALTER ROLE db_ddladmin ADD MEMBER [spname];

--GO