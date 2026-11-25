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
        "mode"
      ],
      "properties": {
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
              "title": "Apply: run the scripts and move them to history on main"
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
        "commit": {
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
