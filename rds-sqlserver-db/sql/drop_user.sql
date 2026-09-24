SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @user SYSNAME = N'$(DbUser)';
DECLARE @sql NVARCHAR(MAX) = N'';

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @user AND type IN ('S', 'U'))
BEGIN
    PRINT 'Database user ' + @user + ' does not exist, nothing to drop';
    RETURN;
END

SELECT @sql = @sql + N'ALTER AUTHORIZATION ON SCHEMA::' + QUOTENAME(s.name) + N' TO [dbo];'
FROM sys.schemas s
WHERE s.principal_id = USER_ID(@user);

IF @sql <> N''
BEGIN
    EXEC sp_executesql @sql;
    PRINT 'Reassigned schemas owned by ' + @user + ' to dbo';
END

SET @sql = N'';
SELECT @sql = @sql + N'ALTER ROLE ' + QUOTENAME(r.name) + N' DROP MEMBER ' + QUOTENAME(@user) + N';'
FROM sys.database_role_members drm
JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
WHERE m.name = @user;

IF @sql <> N''
    EXEC sp_executesql @sql;

SET @sql = N'DROP USER ' + QUOTENAME(@user);
EXEC sp_executesql @sql;
PRINT 'Dropped database user ' + @user;
