{
  "name": "RDS SQL Server",
  "slug": "rds-sqlserver",
  "type": "dependency",
  "unique": false,
  "assignable_to": "any",
  "use_default_actions": true,
  "available_links": [],
  "selectors": {
    "category": "Database",
    "imported": false,
    "provider": "AWS",
    "sub_category": "Relational Database"
  },
  "attributes": {
    "schema": {
      "type": "object",
      "$schema": "http://json-schema.org/draft-07/schema#",
      "required": ["edition", "workload"],
      "properties": {
        "edition": {
          "type": "string",
          "title": "Edition",
          "default": "sqlserver-ex",
          "oneOf": [
            { "const": "sqlserver-ex", "title": "Express (free, 10 GB per database, single-AZ)" },
            { "const": "sqlserver-web", "title": "Web (public web applications only)" },
            { "const": "sqlserver-se", "title": "Standard (requires 200 GB storage or more)" }
          ],
          "description": "SQL Server edition. Licensing is always included in the instance price; cannot be changed after creation.",
          "editableOn": ["create"],
          "order": 1
        },
        "workload": {
          "type": "string",
          "title": "Workload",
          "default": "development",
          "oneOf": [
            { "const": "development", "title": "Development / testing" },
            { "const": "production-light", "title": "Production — light traffic" },
            { "const": "production-heavy", "title": "Production — heavy traffic" }
          ],
          "description": "Expected usage of the database. Capacity is sized for it automatically.",
          "editableOn": ["create", "update"],
          "order": 2
        },
        "allocated_storage": {
          "type": "integer",
          "title": "Storage",
          "default": 20,
          "oneOf": [
            { "const": 20, "title": "20 GB" },
            { "const": 50, "title": "50 GB" },
            { "const": 100, "title": "100 GB" },
            { "const": 200, "title": "200 GB" },
            { "const": 500, "title": "500 GB" },
            { "const": 1000, "title": "1 TB" },
            { "const": 2000, "title": "2 TB" }
          ],
          "description": "Allocated storage size. Standard edition requires 200 GB or more.",
          "editableOn": ["create", "update"],
          "order": 3
        },
        "sqlserver_version": {
          "type": "string",
          "title": "SQL Server Version",
          "default": "16.00",
          "oneOf": [
            { "const": "15.00", "title": "SQL Server 2019" },
            { "const": "16.00", "title": "SQL Server 2022" }
          ],
          "description": "SQL Server major version (cannot be changed after creation)",
          "editableOn": ["create"],
          "order": 4
        },
        "multi_az": {
          "type": "boolean",
          "title": "High Availability",
          "default": false,
          "description": "Run a standby replica in a second availability zone. Not available on Express.",
          "editableOn": ["create", "update"],
          "order": 5
        },
        "hostname": {
          "type": "string",
          "title": "Hostname",
          "export": true,
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "RDS endpoint hostname (auto-populated after creation)",
          "order": 6
        },
        "port": {
          "type": "number",
          "title": "Port",
          "export": true,
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "RDS port (auto-populated after creation)",
          "order": 7
        },
        "db_instance_identifier": {
          "type": "string",
          "export": false,
          "visibleOn": [],
          "editableOn": [],
          "description": "Internal AWS RDS instance identifier"
        },
        "master_secret_arn": {
          "type": "string",
          "export": false,
          "visibleOn": [],
          "editableOn": [],
          "description": "ARN of the Secrets Manager secret holding master credentials (internal use)"
        }
      }
    },
    "values": {}
  }
}
