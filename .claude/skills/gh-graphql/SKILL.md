---
name: gh-graphql
description: Test and explore GitHub Projects v2 GraphQL queries using the gh CLI
argument-hint: "[query-description]"
allowed-tools: Bash, Read, Write, Grep
---

# GitHub GraphQL Query Explorer

Build and test GitHub Projects v2 GraphQL queries.

## Usage

- `/gh-graphql list my projects` — Build and test a query to list projects
- `/gh-graphql get items for project X` — Fetch items from a specific project
- `/gh-graphql` — Interactive exploration of the API

## Steps

1. **Check auth**: Run `gh auth status` to verify GitHub access
2. **Build query**: Construct the GraphQL query for `$ARGUMENTS`
3. **Test it**: Execute via `gh api graphql -f query='...'`
4. **Iterate**: Refine based on the response
5. **Save**: Write working queries to `lua/okuban/queries/` as reusable strings

## Key Endpoints

### List user projects
```bash
gh api graphql -f query='
  query {
    viewer {
      projectsV2(first: 20) {
        nodes { id title number }
      }
    }
  }
'
```

### Get project columns and items
```bash
gh api graphql -f query='
  query($id: ID!) {
    node(id: $id) {
      ... on ProjectV2 {
        title
        fields(first: 20) {
          nodes {
            ... on ProjectV2SingleSelectField {
              name
              options { id name }
            }
          }
        }
        items(first: 50) {
          nodes {
            id
            fieldValues(first: 10) {
              nodes {
                ... on ProjectV2ItemFieldSingleSelectValue {
                  name field { ... on ProjectV2SingleSelectField { name } }
                }
              }
            }
            content {
              ... on Issue { title number state }
              ... on PullRequest { title number state }
              ... on DraftIssue { title }
            }
          }
        }
      }
    }
  }
' -f id='PROJECT_NODE_ID'
```

## Output

Always provide:
1. The working query
2. Example response (trimmed)
3. Notes on pagination or rate limits if relevant
