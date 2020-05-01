# UseBasicParsing is required with Windows PowerShell (non-Core) to prevent IE being loaded
Invoke-WebRequest -Uri http://127.0.0.1/default.aspx -UseBasicParsing -MaximumRetryCount 9