---
type: "Attested Computation"
title: "検索スコアリング計算 (Search Scoring Formula)"
description: "SimpleWiki の全文検索におけるタイトル・タグ・本文・完全一致ボーナスに基づくスコア算出ロジック。"
runtime: "powershell"
parameters:
  - { name: "title_matches", type: "integer", required: true }
  - { name: "tag_matches", type: "integer", required: true }
  - { name: "body_matches", type: "integer", required: true }
  - { name: "exact_phrase", type: "boolean", required: false }
executor:
  resource: "lib/WikiSearch.ps1"
  receipt:
    - "score"
    - "match_details"
attester:
  resource: "tests/Start-MarkdigWiki.Tests.ps1"
status: stable
last_updated: 2026-08-25
generated:
  by: "human:simplewiki-team"
  at: "2026-08-25T00:00:00Z"
verified:
  - by: "human:search-lead"
    at: "2026-08-25T00:00:00Z"
---

# 検索スコアリング計算 (Search Scoring Formula)

SimpleWiki の多層スコアリング検索アルゴリズムにおける確定ロジック仕様です。

---

## 🎯 目的と保証

検索クエリに対して、タイトル完全一致ボーナス、タグ一致、本文形態素ヒット、およびドキュメント状態（`status: deprecated` ペナルティ）を正規の重み付けで算定します。

---

## # Schema

| パラメータ名 | 型 | 必須 | 既定値 | 説明 |
| :--- | :---: | :---: | :--- | :--- |
| `title_matches` | `integer` | ✅ | `0` | タイトル内のヒット語数 |
| `tag_matches` | `integer` | ✅ | `0` | タグ配列内の完全一致数 |
| `body_matches` | `integer` | ✅ | `0` | 本文内のヒット数（上限10回） |
| `exact_phrase` | `boolean` | 任意 | `$false` | クエリ文字列の完全一致フレーズ |
| `is_deprecated` | `boolean` | 任意 | `$false` | 非推奨ドキュメント減衰フラグ |

---

## # Computation

```powershell
function Calculate-SearchScore {
    param(
        [int]$TitleMatches,
        [int]$TagMatches,
        [int]$BodyMatches,
        [bool]$ExactPhrase = $false,
        [bool]$IsDeprecated = $false
    )

    $titleWeight = 10
    $tagsWeight  = 8
    $bodyWeight  = 1
    $bodyMaxHits = 10
    $exactBonus  = 15

    $score = ($TitleMatches * $titleWeight) + ($TagMatches * $tagsWeight)

    $clampedBody = [System.Math]::Min($BodyMatches, $bodyMaxHits)
    $score += ($clampedBody * $bodyWeight)

    if ($ExactPhrase) {
        $score += $exactBonus
    }

    if ($IsDeprecated) {
        $score = [int] ($score * 0.3)
    }

    return $score
}
```

---

## 🔗 関連ドキュメント

- [詳細仕様書を見る](../詳細仕様.md)
- [REST API 仕様書を見る](../api/REST-API.md)
- [ドキュメント一覧に戻る](../index.md)
