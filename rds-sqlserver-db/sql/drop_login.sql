SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @user SYSNAME = N'$(DbUser)';
DECLARE @sql NVARCHAR(MAX) = N'';

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @user)
BEGIN
    PRINT 'Login ' + @user + ' does not exist, nothing to drop';
    RETURN;
END

SELECT @sql = @sql + N'KILL ' + CAST(session_id AS NVARCHAR(10)) + N';'
FROM sys.dm_exec_sessions
WHERE login_name = @user AND session_id <> @@SPID;

IF @sql <> N''
BEGIN
    EXEC sp_executesql @sql;
    PRINT 'Closed open sessions for ' + @user;
END

SET @sql = N'DROP LOGIN ' + QUOTENAME(@user);
EXEC sp_executesql @sql;
PRINT 'Dropped login ' + @user;
