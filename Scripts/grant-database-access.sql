select @@version

USE vdcdemopaasappkmfdsqldb

IF NOT EXISTS(SELECT name FROM sys.database_principals WHERE name = 'vdc-demo-paasapp-kmfd-appsvc-app')
BEGIN 
	CREATE USER [vdc-demo-paasapp-kmfd-appsvc-app] FROM EXTERNAL PROVIDER;
END
ALTER ROLE db_datareader ADD MEMBER [vdc-demo-paasapp-kmfd-appsvc-app];
ALTER ROLE db_datawriter ADD MEMBER [vdc-demo-paasapp-kmfd-appsvc-app];
ALTER ROLE db_ddladmin ADD MEMBER [vdc-demo-paasapp-kmfd-appsvc-app];
GO
