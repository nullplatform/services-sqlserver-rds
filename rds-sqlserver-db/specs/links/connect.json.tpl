{
  "name": "Connect",
  "slug": "connect",
  "unique": false,
  "assignable_to": "any",
  "use_default_actions": true,
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
      "required": [],
      "properties": {
        "access_level": {
          "type": "string",
          "title": "Access Level",
          "default": "read-write",
          "oneOf": [
            { "const": "read", "title": "Read (db_datareader)" },
            { "const": "write", "title": "Write (db_datawriter)" },
            { "const": "read-write", "title": "Read and write, including schema migrations (db_datareader, db_datawriter, db_ddladmin)" }
          ],
          "editableOn": ["create", "update"],
          "description": "Database roles granted to the application user",
          "order": 1
        },
        "hostname": {
          "type": "string",
          "title": "Hostname",
          "export": true,
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "RDS endpoint hostname",
          "order": 2
        },
        "port": {
          "type": "number",
          "title": "Port",
          "export": true,
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "RDS port",
          "order": 3
        },
        "username": {
          "type": "string",
          "title": "DB Username",
          "export": true,
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "Database username",
          "order": 4
        },
        "password": {
          "type": "string",
          "title": "DB Password",
          "export": {"type": "environment_variable", "secret": true},
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "Database password (auto-generated at service create)",
          "order": 5
        },
        "database_name": {
          "type": "string",
          "title": "Database",
          "export": true,
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "Database name",
          "order": 6
        },
        "jdbc_url": {
          "type": "string",
          "title": "JDBC URL",
          "export": true,
          "visibleOn": ["read"],
          "editableOn": [],
          "description": "Ready-to-use JDBC connection string for this database",
          "order": 7
        },
        "master_secret_arn": {
          "type": "string",
          "export": false,
          "visibleOn": [],
          "editableOn": [],
          "description": "ARN of the Secrets Manager secret for master credentials (internal use)"
        },
        "app_secret_arn": {
          "type": "string",
          "export": false,
          "visibleOn": [],
          "editableOn": [],
          "description": "ARN of the Secrets Manager secret holding the app-level credentials (internal use)"
        }
      }
    },
    "values": {}
  }
}
