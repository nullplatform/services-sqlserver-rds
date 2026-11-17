{
  "name": "Run migrations",
  "slug": "run-migrations",
  "type": "custom",
  "annotations": {},
  "retryable": true,
  "parameters": {
    "schema": {
      "type": "object",
      "required": [
        "repository_url",
        "ref",
        "environment_directory",
        "mode"
      ],
      "properties": {
        "repository_url": {
          "type": "string",
          "title": "Repository URL",
          "description": "The application's <sigla>-databases repository on GitHub, e.g. https://github.com/my-org/abcd-databases. The sigla comes from the namespace slug up to the first dash",
          "pattern": "^(https://github\\.com/|git@github\\.com:)[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?(\\.git)?/?$"
        },
        "ref": {
          "type": "string",
          "title": "Tag or branch",
          "description": "Tag or branch to read the scripts from"
        },
        "environment_directory": {
          "type": "string",
          "title": "Environment directory",
          "description": "Top-level directory of the repository for this environment, e.g. dev, qas or prd. Every directory except dev blocks DROP, TRUNCATE and SELECT *",
          "pattern": "^[A-Za-z0-9_-]+$"
        },
        "database_directory": {
          "type": "string",
          "title": "Database directory",
          "description": "Directory under the environment that holds this database's scripts. Defaults to the database name",
          "pattern": "^[A-Za-z0-9_-]+$"
        },
        "history_branch": {
          "type": "string",
          "title": "History branch",
          "description": "Branch that receives the executed scripts under history/. Defaults to the repository's default branch"
        },
        "mode": {
          "type": "string",
          "title": "Mode",
          "default": "preview",
          "oneOf": [
            {
              "const": "preview",
              "title": "Preview: validate and show the SQL, change nothing"
            },
            {
              "const": "apply",
              "title": "Apply: run the scripts and move them to history"
            }
          ]
        }
      }
    },
    "values": {}
  },
  "results": {
    "schema": {
      "type": "object",
      "required": [],
      "properties": {
        "mode": {
          "type": "string"
        },
        "ref": {
          "type": "string"
        },
        "scripts": {
          "type": "array",
          "items": {
            "type": "string"
          }
        },
        "history_commit": {
          "type": "string"
        }
      }
    },
    "values": {}
  }
}
