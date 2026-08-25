---
type: Attested Computation
title: "{{TITLE}}"
description: "{{DESCRIPTION}}"
tags: [computation, metric]
status: stable
runtime: {{RUNTIME}}
parameters:
  - { name: {{PARAM_NAME}}, type: {{PARAM_TYPE}}, required: true }
executor:
  resource: references/skills/{{EXECUTOR_SKILL}}.md
  receipt: [job_id, executed_sql, result]
attester:
  resource: references/attesters/{{ATTESTER_SCRIPT}}
generated: { by: {{ACTOR}}, at: {{TIMESTAMP}} }
---

# Computation

```{{RUNTIME}}
-- Sanctioned computation query / logic
```

# Verification & Notes

Describe computation logic assumptions and references.
