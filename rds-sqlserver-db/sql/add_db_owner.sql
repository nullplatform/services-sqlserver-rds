SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @user SYSNAME = N'$(DbUser)';
DECLARE @sql NVARCHAR(MAX);

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members drm
    JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = N'db_owner' AND m.name = @user
)
BEGIN
    SET @sql = N'ALTER ROLE [db_owner] ADD MEMBER ' + QUOTENAME(@user);
    EXEC sp_executesql @sql;
    PRINT 'Added ' + @user + ' to db_owner';
END
ELSE
    PRINT @user + ' is already a member of db_owner';
