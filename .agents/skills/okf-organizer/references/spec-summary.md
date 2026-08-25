# OKF (Open Knowledge Format) v0.2 仕様要約リファレンス

本資料は、[OKF v0.2 仕様書](https://raw.githubusercontent.com/GoogleCloudPlatform/knowledge-catalog/refs/heads/main/okf/SPEC.md) のコア原則、構造、規約を凝縮した技術リファレンスです。

---

## 1. OKF の設計思想

OKF は、人間と AI エージェントの双方が生成・保守・交換できる最小限かつオープンなナレッジ表現フォーマットです。

- **プレーンな Markdown + YAML Frontmatter**: 専用ツール不要で `cat` や `git clone` で閲覧・管理可能。
- **5つの主要な問いに答えるメタデータ**:
  1. **Provenance（出典）**: 何から作られ、どう検証されたか？ (`sources`, `usage_window`)
  2. **Trust（信頼性）**: どれくらい信頼できるか？ (`generated`, `verified`)
  3. **Freshness（鮮度）**: まだ有効か？ (`stale_after`)
  4. **Lifecycle（ライフサイクル）**: 現在のステータスは？ (`status`)
  5. **Attestation（計算保証）**: 定義通りの正規の方法で計算されたか？ (`type: Attested Computation`, `executor`, `attester`)

---

## 2. バンドル構造と予約ファイル

ナレッジバンドル（Knowledge Bundle）は Markdown ファイルの階層ディレクトリです。

```
<bundle-root>/
  index.md                      # 予約ファイル: 段階的開示（Progressive Disclosure）用目次
  log.md                        # 予約ファイル: 更新履歴（Update Log）
  <concept>.md                  # ルート直下のコンセプト
  <subdirectory>/               # 任意のサブディレクトリ
    index.md
    <concept>.md
    references/                 # 慣例: 外部参照、スクリプト、アテスター配置用
```

### 2.1 予約ファイル規約 (§3.1)
- `index.md`: ディレクトリ一覧。
  - ルートの `index.md` のみ `okf_version: "0.2"` の Frontmatter を持つことが許可される（省略可）。
  - サブディレクトリの `index.md` は Frontmatter を持たない。
- `log.md`: 日付別（`## YYYY-MM-DD`）の更新履歴。Frontmatter は持たない。

---

## 3. コンセプトドキュメント規約 (§4)

すべての通常 `.md` ファイルは「コンセプト（Concept）」を表します。

### 3.1 必須および推奨 Frontmatter
```yaml
---
type: <Type name>                  # 【必須】コンセプトの種類 (例: Architecture, Table, Guide, Attested Computation)
title: <Display name>              # 【推奨】表示名（省略時はファイル名から推測）
description: <One-line summary>    # 【推奨】1文の要約（index.mdや検索プレビューで使用）
resource: <Canonical URI>          # 【推奨/任意】物理リソースのURI
tags: [<tag1>, <tag2>]             # 【任意】タグ配列
status: stable                     # 【任意】draft | stable | deprecated (省略時は stable)
stale_after: 2026-12-31T00:00:00Z  # 【任意】失効日時 (ISO 8601 UTC)
generated:                         # 【任意】生成メタデータ
  by: human:username               # Actor規約 (human:*, agent/*, process:*)
  at: 2026-08-24T12:00:00Z         # ISO 8601 UTC
verified:                          # 【任意】検証メタデータ (リストまたは単一マッピング)
  - by: human:reviewer
    at: 2026-08-24T14:00:00Z
sources:                           # 【任意】出典情報 (Provenance)
  - id: source-key                 # 脚注 [^source-key] と紐付くキー
    resource: https://...
    title: Source Title
    author: team:infra
    usage_count: 1200
    last_modified: 2026-08-01T00:00:00Z
---
```

### 3.2 慣例的な本文見出し (§4.2)
- `# Schema`: カラムやフィールドの構造記述。
- `# Examples`: 具体的なコード例・利用例。
- `# Computation`: Attested Computation の計算ロジック。

### 3.3 脚注による出典の紐付け (§5.1)
本文中の個別主張に対しては、`sources[].id` をラベルとした Markdown 脚注を使用します：

```markdown
このキャッシュは最大5分間保持されます。[^cache-spec]

[^cache-spec]: キャッシュ設計仕様書
```

---

## 4. Actor 規約 (§7)
- **人間**: `human:<id>` (例: `human:alice`, `human:infra-lead`)
- **エージェント・AI**: `<producer>/<version>` (例: `reference_agent/gemini-2.5-pro`, `antigravity/3.7`)
- **自動プロセス**: `process:<id>` (例: `process:nightly-sync`, `process:ci-build`)

### Trust Tier（信頼水準）の判定 (§5.3)
1. `verified` なし $\rightarrow$ **unverified**
2. `verified` に非 `human:` のみ存在 $\rightarrow$ **machine-confirmed**
3. `verified` に `human:<id>` が1つ以上存在 $\rightarrow$ **human-reviewed**

---

## 5. Attested Computation（保証付き計算）(§10)
数値や指標の算出ロジックを「独立したコンセプト」として定義し、実行と検証を分離する仕組みです。

```yaml
---
type: Attested Computation
title: Monthly Active Users
description: 30日間に1回以上アクションを起こしたユニークユーザー数。
runtime: bigquery
parameters:
  - { name: target_month, type: string, required: true }
executor:
  resource: references/skills/run-query.md
  receipt: [job_id, executed_sql, result]
attester:
  resource: references/attesters/verify-mau.py
status: stable
---

# Computation

```sql
SELECT COUNT(DISTINCT user_id) AS mau
FROM analytics.user_events
WHERE DATE_TRUNC(event_date, MONTH) = PARSE_DATE('%Y-%m', @target_month)
```
```

---

## 6. 適合性チェックリスト (Conformance Checklist §11)
- [ ] すべての非予約 `.md` ファイルに YAML Frontmatter が存在する。
- [ ] すべての Frontmatter に非空の `type` フィールドが存在する。
- [ ] 予約ファイル `index.md` / `log.md` の Frontmatter 規約を遵守している。
- [ ] クロスリンク（`/path/to/doc.md` または `./doc.md`）が壊れていない。
