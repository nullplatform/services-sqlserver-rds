SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @user SYSNAME = N'$(DbUser)';
DECLARE @wantRead BIT = $(WantRead);
DECLARE @wantWrite BIT = $(WantWrite);
DECLARE @wantDdl BIT = $(WantDdl);
DECLARE @sql NVARCHAR(MAX);

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @user AND type IN ('S', 'U'))
BEGIN
    RAISERROR('Database user %s does not exist', 16, 1, @user);
    RETURN;
END

DECLARE @managed TABLE (role_name SYSNAME, wanted BIT);
INSERT INTO @managed (role_name, wanted) VALUES
    (N'db_datareader', @wantRead),
    (N'db_datawriter', @wantWrite),
    (N'db_ddladmin',   @wantDdl);

DECLARE @role SYSNAME, @wanted BIT;
DECLARE role_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT role_name, wanted FROM @managed;

OPEN role_cursor;
FETCH NEXT FROM role_cursor INTO @role, @wanted;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF @wanted = 1
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM sys.database_role_members drm
            JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
            JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
            WHERE r.name = @role AND m.name = @user)
        BEGIN
            SET @sql = N'ALTER ROLE ' + QUOTENAME(@role) + N' ADD MEMBER ' + QUOTENAME(@user);
            EXEC sp_executesql @sql;
            PRINT 'Added ' + @user + ' to ' + @role;
        END
    END
    ELSE
    BEGIN
        IF EXISTS (
            SELECT 1 FROM sys.database_role_members drm
            JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
            JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
            WHERE r.name = @role AND m.name = @user)
        BEGIN
            SET @sql = N'ALTER ROLE ' + QUOTENAME(@role) + N' DROP MEMBER ' + QUOTENAME(@user);
            EXEC sp_executesql @sql;
            PRINT 'Removed ' + @user + ' from ' + @role;
        END
    END

    FETCH NEXT FROM role_cursor INTO @role, @wanted;
END

CLOSE role_cursor;
DEALLOCATE role_cursor;
