---
type: {{RESOURCE_TYPE}}
title: "{{TITLE}}"
description: "{{DESCRIPTION}}"
resource: {{RESOURCE_URI}}
tags: [{{TAGS}}]
status: stable
generated: { by: {{ACTOR}}, at: {{TIMESTAMP}} }
---

# Schema

| Field / Column | Type | Description |
|---|---|---|
| `id` | STRING | Unique identifier. |
| `created_at` | TIMESTAMP | Creation timestamp in UTC. |

# Relationships & Joins

Describe links to related concepts, e.g., see [Related Concept](/path/to/related.md).

# Examples

```sql
SELECT * FROM {{RESOURCE_NAME}} LIMIT 10;
```
