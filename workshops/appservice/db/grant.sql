-- Grant the App Service managed identity least-privilege read access.
-- $(uamiName) and $(uamiSid) are passed as sqlcmd variables by the deploy workflow.
-- Using WITH SID = <client-id bytes>, TYPE = E creates the external-provider user
-- WITHOUT an MS Graph lookup, so the SQL server needs no Directory Readers role.
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$(uamiName)')
BEGIN
    CREATE USER [$(uamiName)] WITH SID = $(uamiSid), TYPE = E;
    ALTER ROLE db_datareader ADD MEMBER [$(uamiName)];
END;
GO
