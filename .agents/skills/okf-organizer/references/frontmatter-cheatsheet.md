# OKF Frontmatter チートシート & 実例集

OKF v0.2 の YAML Frontmatter で利用可能なすべてのフィールドとその書き方、実践パターンを網羅したチートシートです。

---

## 1. 全フィールド一覧

| フィールド名 | 必須 | 型 | 説明 | 例 |
|---|---|---|---|---|
| `type` | **必須** | String | コンセプトの種別。非空文字列。 | `Guide`, `Architecture`, `Table`, `Service` |
| `title` | 推奨 | String | ドキュメントの表示名。 | `ユーザー認証基盤設計書` |
| `description` | 推奨 | String | 1行の概要要約。 | `OAuth2 / OIDC をベースとした共通認証サービスの仕様。` |
| `resource` | 任意 | URI/Path | 実リソースのURLまたはパス。 | `https://console.cloud.google.com/...` |
| `tags` | 任意 | List[String] | 横断検索用タグ配列。 | `[auth, security, backend]` |
| `status` | 任意 | Enum | `draft` \| `stable` \| `deprecated` | `stable` |
| `stale_after` | 任意 | ISO 8601 | 内容が陳腐化する失効日時。 | `2026-12-31T00:00:00Z` |
| `generated` | 任意 | Object | 生成者・生成日時。 | `{ by: human:alice, at: 2026-08-24T12:00:00Z }` |
| `verified` | 任意 | List/Object | レビュー・検証履歴。 | `[{ by: human:lead, at: 2026-08-24T15:00:00Z }]` |
| `sources` | 任意 | List[Object] | 出典（Provenance）一覧。 | `[{ id: src1, resource: https://... }]` |
| `usage_window` | 任意 | Object | sources全体の期間設定。 | `{ from: 2026-01-01T00:00:00Z, to: 2026-06-30T00:00:00Z }` |
| `runtime` | 任意(*) | String | Attested Computation の実行環境。 | `bigquery`, `postgres`, `python`, `dbt` |
| `parameters` | 任意(*) | List[Object] | Attested Computation の引数定義。 | `[{ name: year, type: integer, required: true }]` |
| `executor` | 任意(*) | Object | 実行手順・レシート仕様。 | `{ resource: references/..., receipt: [...] }` |
| `attester` | 任意(*) | Object | 決定論的検証コードのパス。 | `{ resource: references/attesters/verify.py }` |

(*) `type: Attested Computation` の場合に指定。

---

## 2. 実践パターン集

### パターン A: 最小限のコンセプト (Minimal)
```yaml
---
type: Note
title: 日常メモ
---
```

### パターン B: 出典・信頼性メタデータ付きの設計書 (Full Trust)
```yaml
---
type: Architecture Doc
title: 決済データパイプライン設計
description: Stripe決済イベントを BigQuery に準リアルタイムで同期するパイプライン。
resource: https://github.com/my-org/payment-pipeline
tags: [payment, bq, streaming, architecture]
status: stable
stale_after: 2027-03-31T00:00:00Z
generated:
  by: antigravity/3.7
  at: 2026-08-24T12:00:00Z
verified:
  - by: human:reviewer-lead
    at: 2026-08-24T14:30:00Z
  - by: process:ci-schema-validator
    at: 2026-08-24T15:00:00Z
sources:
  - id: stripe-webhook-doc
    resource: https://stripe.com/docs/webhooks
    title: Stripe Webhook 仕様書
    last_modified: 2026-07-15T00:00:00Z
  - id: bq-streaming-limit
    resource: https://cloud.google.com/bigquery/quotas#streaming_inserts
    title: BigQuery Streaming Quotas
---

# 概要

本パイプラインは Stripe の Webhook を Cloud Functions で受信し、BigQuery の `raw_payments` テーブルにストリーミング挿入します。[^stripe-webhook-doc]

BigQuery のストリーミングクォータ上限[^bq-streaming-limit] を考慮し、バッファリングキューを前段に配置しています。

[^stripe-webhook-doc]: Stripe Webhook 仕様書
[^bq-streaming-limit]: BigQuery Streaming Quotas
```

### パターン C: 保証付き計算 (Attested Computation)
```yaml
---
type: Attested Computation
title: 月次継続課金収益 (MRR) 算出
description: 有効サブスクリプションに基づく月次定常収益の集計。
tags: [finance, mrr, metric]
status: stable
runtime: bigquery
parameters:
  - { name: target_month, type: string, required: true }
executor:
  resource: references/skills/run-bq-query.md
  receipt: [job_id, executed_sql, result]
attester:
  resource: references/attesters/verify-mrr.py
generated: { by: human:finance-team, at: 2026-08-20T10:00:00Z }
verified: { by: human:cfo-signoff, at: 2026-08-22T16:00:00Z }
sources:
  - id: revenue-policy
    resource: https://wiki.internal/finance/mrr-policy
    title: 収益認識規程
---

# Computation

```sql
SELECT
  DATE_TRUNC(subscription_date, MONTH) AS billing_month,
  SUM(plan_monthly_price_jpy) AS mrr_jpy
FROM billing.active_subscriptions
WHERE is_active = TRUE
  AND DATE_TRUNC(subscription_date, MONTH) = PARSE_DATE('%Y-%m', @target_month)
GROUP BY 1
```

本集計ロジックは社内収益認識規程[^revenue-policy]に準拠しています。

[^revenue-policy]: 収益認識規程
```
