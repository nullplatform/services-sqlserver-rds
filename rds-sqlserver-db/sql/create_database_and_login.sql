SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @db SYSNAME = N'$(DbName)';
DECLARE @user SYSNAME = N'$(DbUser)';
DECLARE @pwd NVARCHAR(128) = N'$(DbPassword)';
DECLARE @sql NVARCHAR(MAX);

IF DB_ID(@db) IS NULL
BEGIN
    SET @sql = N'CREATE DATABASE ' + QUOTENAME(@db);
    EXEC sp_executesql @sql;
    PRINT 'Created database ' + @db;
END
ELSE
    PRINT 'Database ' + @db + ' already exists';

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @user)
BEGIN
    SET @sql = N'CREATE LOGIN ' + QUOTENAME(@user)
             + N' WITH PASSWORD = ' + QUOTENAME(@pwd, '''')
             + N', CHECK_POLICY = OFF, DEFAULT_DATABASE = ' + QUOTENAME(@db);
    EXEC sp_executesql @sql;
    PRINT 'Created login ' + @user;
END
ELSE
BEGIN
    SET @sql = N'ALTER LOGIN ' + QUOTENAME(@user)
             + N' WITH PASSWORD = ' + QUOTENAME(@pwd, '''');
    EXEC sp_executesql @sql;
    PRINT 'Updated password for existing login ' + @user;
END
