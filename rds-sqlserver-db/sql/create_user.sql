SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @user SYSNAME = N'$(DbUser)';
DECLARE @sql NVARCHAR(MAX);

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @user AND type IN ('S', 'U'))
BEGIN
    SET @sql = N'CREATE USER ' + QUOTENAME(@user) + N' FOR LOGIN ' + QUOTENAME(@user);
    EXEC sp_executesql @sql;
    PRINT 'Created database user ' + @user;
END
ELSE
    PRINT 'Database user ' + @user + ' already exists';
