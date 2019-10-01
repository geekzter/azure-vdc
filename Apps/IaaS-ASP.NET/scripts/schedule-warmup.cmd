schtasks.exe /create /f /ru "NT AUTHORITY\NETWORKSERVICE" /sc minute /mo 1 /tn "Demo App Keep Warm" /tr C:\Users\Public\Documents\warmup.cmd
schtasks.exe /create /f /ru "NT AUTHORITY\NETWORKSERVICE" /sc onstart      /tn "Demo App Startup Warm Up" /tr C:\Users\Public\Documents\warmup.cmd
