Use vdcdevpaasappfxausqldb

IF NOT EXISTS(SELECT name FROM sys.database_principals WHERE name = 'vdc-dev-paasapp-fxau-appsvc-app')
BEGIN 
	CREATE USER [vdc-dev-paasapp-fxau-appsvc-app] FROM EXTERNAL PROVIDER;
END
ALTER ROLE db_datareader ADD MEMBER [vdc-dev-paasapp-fxau-appsvc-app];
ALTER ROLE db_datawriter ADD MEMBER [vdc-dev-paasapp-fxau-appsvc-app];
ALTER ROLE db_ddladmin ADD MEMBER [vdc-dev-paasapp-fxau-appsvc-app];
GO
