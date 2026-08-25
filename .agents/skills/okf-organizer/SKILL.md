---
name: okf-organizer
description: Organizes, structures, verifies, and manages documentation and knowledge bases using the Open Knowledge Format (OKF) v0.2 specification. Activate whenever the user asks to organize docs in OKF format, build a knowledge bundle, add OKF YAML frontmatter, generate or synchronize index.md and log.md, design or rearrange directory hierarchies for knowledge bases, structure provenance and trust tiers, create Attested Computation concepts, or validate OKF bundle conformance.
---

# OKF v0.2 Knowledge Bundle Organizer

This skill guides you through creating, organizing, restructuring, and validating documentation and materials according to the **Open Knowledge Format (OKF) v0.2** specification.

---

## 1. Core Workflow: Organizing Documentation into OKF

When the user asks to organize documentation, follow these 6 systematic steps:

```
[1. Analyze & Scope] ─> [2. Design Layout] ─> [3. Author Concepts] ─> [4. Attested Logic] ─> [5. Index & Log] ─> [6. Validate]
```

### Step 1: Analyze & Scope Knowledge Materials
1. Identify all source documents, code snippets, database schemas, playbooks, or metrics to be organized.
2. Determine whether the bundle is a:
   - **System / Architecture Knowledge Base** (Services, APIs, Infrastructure, Playbooks)
   - **Team / Organization Knowledge Base** (Guidelines, Policies, Processes, Onboarding)
   - **Data & Analytics Catalog** (Datasets, Tables, Metrics, Computations)
   - **Minimal / Single-Domain Base** (Flat or small grouping)

### Step 2: Choose & Arrange Directory Layout
OKF does not enforce a rigid taxonomy. Use [directory-patterns.md](references/directory-patterns.md) to select or customize the directory structure.

To scaffold a bundle with automated structure:
```powershell
powershell -ExecutionPolicy Bypass -File .\.agents\skills\okf-organizer\scripts\New-OkfBundle.ps1 `
    -Path ".\docs" `
    -Preset "system-docs" `
    -BundleTitle "Project Knowledge Base"
```

> **Arrangement Flexibility Rule**: Keep internal links bundle-relative (e.g. `/architecture/system-overview.md`) so documents can be reorganized across folders without broken relative paths.

### Step 3: Standardize Concept Documents (1 File = 1 Concept)
Ensure every non-reserved `.md` file follows OKF v0.2 rules:
1. **YAML Frontmatter Block**:
   - `type` (**REQUIRED**): Short descriptor (e.g. `Architecture Overview`, `Service`, `Table`, `Metric`, `Playbook`, `Attested Computation`).
   - `title`: Human-readable display title.
   - `description`: Single-sentence summary for previews and indices.
   - `resource`: Optional URI or canonical path to physical asset.
   - `tags`: List of category strings.
   - `status`: `draft` | `stable` | `deprecated`.
   - `generated`: `{ by: <actor>, at: <ISO 8601 UTC> }`.
   - `verified`: `[{ by: <actor>, at: <ISO 8601 UTC> }]`.
   - `sources`: Provenance list with `id`, `resource`, `title`, `author`, `usage_count`, `last_modified`.

2. **Body Markdown**:
   - Favor structural headings (`# Schema`, `# Examples`, `# Details`).
   - Use Markdown footnotes `[^source-id]` matching `sources[].id` in frontmatter for claim attribution.

Refer to [frontmatter-cheatsheet.md](references/frontmatter-cheatsheet.md) for full patterns.

### Step 4: Separate Attested Computations
If documents contain critical metric calculation queries or formulas (e.g., revenue calculation, active user queries):
- Do **not** embed loose code that agents might improvise.
- Extract the computation into a dedicated concept file of `type: Attested Computation` (e.g., `computations/mrr.md`).
- Define `runtime`, `parameters`, `executor`, `attester`, and the query under `# Computation`.
- Link to it from the readable narrative concept (e.g., `metrics/mrr.md` links to `[MRR Computation](/computations/mrr.md)`).

### Step 5: Generate & Synchronize Navigation (`index.md` & `log.md`)
Run the synchronization script to auto-generate/update all `index.md` files (extracting titles and descriptions) and record changes to `log.md`:

```powershell
powershell -ExecutionPolicy Bypass -File .\.agents\skills\okf-organizer\scripts\Update-OkfIndex.ps1 `
    -Path ".\docs" `
    -Recurse `
    -LogMessage "Organized architecture and playbook documents"
```

### Step 6: Validate OKF v0.2 Conformance
Always run the validation script before finishing:

```powershell
powershell -ExecutionPolicy Bypass -File .\.agents\skills\okf-organizer\scripts\Test-OkfBundle.ps1 `
    -Path ".\docs" `
    -CheckBrokenLinks
```

Confirm that:
- `IsValid` is `$true` (0 errors).
- All reserved filenames (`index.md`, `log.md`) conform to rules.
- No broken links exist.

---

## 2. Bundled References & Tooling

When organizing or reviewing knowledge bundles, inspect these resources:
- [spec-summary.md](references/spec-summary.md) - Complete OKF v0.2 specification summary and rules.
- [directory-patterns.md](references/directory-patterns.md) - Directory layout presets and customization guides.
- [frontmatter-cheatsheet.md](references/frontmatter-cheatsheet.md) - YAML frontmatter fields and examples.
- [templates/](templates/) - Ready-to-use concept and bundle templates.
- [scripts/](scripts/) - PowerShell automation tools (`Test-OkfBundle.ps1`, `Update-OkfIndex.ps1`, `New-OkfBundle.ps1`, `New-OkfConcept.ps1`).
