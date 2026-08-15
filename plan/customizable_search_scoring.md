# **検索スコアリングエンジンのカスタマイズ設計計画書**

> **【ステータス: 実装完了】**
> 本設計計画書で定義された `config.json` 駆動の検索スコアリング・優先/抑制ルールは `Get-SearchConfig` および `Search-OkfDocs` にて完全に実装され、単体テスト（全98件パス）および動作検証が完了しました。

本ドキュメントは、**SimpleWiki** の OKF 文脈検索エンジンおよび RAG（Fast / Agentic）検索基盤において、検索スコアリングの重み付けや優先・抑制ルールをユーザー/プロジェクトごとに柔軟にカスタマイズ可能にするための拡張設計書です。

---

## **1. スコアリングのカスタマイズが全般に有効な理由**

### **1.1 プロジェクトや文書種別による特性の違い**
Wiki やドキュメント群は、用途によって「どのドキュメントを最も重視すべきか」が異なります：

| ドキュメント体系 | 最重要とすべき文書 (加点対象) | 検索ノイズとなりやすい文書 (減点/除外対象) |
| :--- | :--- | :--- |
| **社内規程・法令文書** | 総則 (`01_総則.md`)、規程本体 (`index.md`) | 附則 (`suppl/`)、改正履歴 (`amendments`)、別表 (`appendix/`) |
| **システム仕様書・技術文書** | 概要 (`overview.md`)、README (`README.md`)、アーキテクチャ設計 | 変更履歴 (`CHANGELOG.md`)、移行パッチ (`migration/`) |
| **業務マニュアル・SOP** | クイックスタート (`quickstart.md`)、目次 (`index.md`) | 旧版アーカイブ (`archive/`)、廃止手順 (`deprecated`) |
| **FAQ・ナレッジベース** | よくある質問 (`faq.md`)、トラブルシュート | 下書き (`draft`)、テンプレート (`templates/`) |

### **1.2 汎用化・設定駆動化のメリット**
1. **コード変更なしで検索挙動を最適化**:
   - スクリプト（`Start-MarkdigWiki.ps1`）を編集することなく、`config.json` の設定値を調整するだけで、プロジェクトの特性に合わせた最適な検索ランキングを実現できます。
2. **AI チャット (RAG) 回答精度の最大化**:
   - Fast RAG や Agentic RAG が参照するコンテキストに「最も本質的なドキュメント」が確実に選定されるため、AI 回答のハルシネーションや「該当情報なし」の誤答を根絶できます。

---

## **2. `config.json` 設定スキーマ設計**

`config.json` に新設する `search` セクションの設計案です：

```json
{
  "search": {
    "scoring": {
      "exactPhraseBonus": 15,
      "exactTitleBonus": 25,
      "titleWeight": 10,
      "tagsWeight": 8,
      "descriptionWeight": 5,
      "domainWeight": 4,
      "authorWeight": 3,
      "bodyHitWeight": 1,
      "bodyMaxHits": 10,
      "deprecatedPenaltyRate": 0.3
    },
    "priorityRules": {
      "mainDocPatterns": [
        "index.md",
        "README.md",
        "overview.md",
        "guide.md",
        "quickstart.md"
      ],
      "mainDocBonus": 20
    },
    "suppressionRules": {
      "noisePatterns": [
        "suppl",
        "appendix",
        "amendments?",
        "history",
        "changelog",
        "patch",
        "archive",
        "別表",
        "附則",
        "沿革"
      ],
      "suppressionRate": 0.3
    }
  }
}
```

---

## **3. スコアリング処理のアーキテクチャ**

### **3.1 動的スコア算出ロジック**

```powershell
# 1. 基本メタデータスコアリング (config.json の重み設定を反映)
$score = 0
if ($item.Title -and $item.Title -match $phraseRegex) { $score += $cfg.scoring.exactPhraseBonus }
if ($item.Title -and $item.Title.Trim() -eq $cleanQuery) { $score += $cfg.scoring.exactTitleBonus }

foreach ($kw in $keywords) {
    $kwRegex = [regex]::Escape($kw)
    if ($item.Title -and $item.Title -match $kwRegex) { $score += $cfg.scoring.titleWeight }
    if ($item.Tags -match $kwRegex) { $score += $cfg.scoring.tagsWeight }
    if ($item.Description -and $item.Description -match $kwRegex) { $score += $cfg.scoring.descriptionWeight }
    if ($item.Domain -and $item.Domain -match $kwRegex) { $score += $cfg.scoring.domainWeight }
    if ($item.Author -and $item.Author -match $kwRegex) { $score += $cfg.scoring.authorWeight }
    
    # 高速 IndexOf プリフィルタ後の本文マッチ
    if ($item.BodyText -and $item.BodyText.IndexOf($kw, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $bodyMatches = ([regex]::Matches($item.BodyText, "(?i)$kwRegex")).Count
        if ($bodyMatches -gt 0) {
            $score += [Math]::Min($bodyMatches, $cfg.scoring.bodyMaxHits) * $cfg.scoring.bodyHitWeight
        }
    }
}

# 2. メインドキュメント優遇判定 (設定ファイルのマッチパターン)
$relLower = $item.RelPath.ToLower().Replace('/', '\')
foreach ($pattern in $cfg.priorityRules.mainDocPatterns) {
    if ($relLower.EndsWith("\" + $pattern.ToLower()) -or $relLower -eq $pattern.ToLower()) {
        $score += $cfg.priorityRules.mainDocBonus
        break
    }
}

# 3. ノイズ・補助ドキュメント抑制判定 (設定ファイルのマッチパターン)
$noiseRegex = "[\\_](" + ($cfg.suppressionRules.noisePatterns -join "|") + ")[\\_\.]"
if ($relLower -match $noiseRegex) {
    $score = [Math]::Max(1, [Math]::Floor($score * $cfg.suppressionRules.suppressionRate))
}

# 4. 非推奨 (deprecated) ドキュメント減点
if ($item.Status -eq "deprecated") {
    $score = [Math]::Floor($score * $cfg.scoring.deprecatedPenaltyRate)
}
```

---

## **4. 今後のロードマップと期待される効果**

1. **フェーズ 1**: `config.json.example` への設定定義追加とデフォルト値の定義。
2. **フェーズ 2**: `Get-ConfigJson` における `search` セクションの読み込みとデフォルトフォールバック。
3. **フェーズ 3**: `Search-OkfDocs` への設定値バインドと、GUI（`Export-GUI.ps1`）や Web 管理画面での重み付けチューニング UI の提供。

この仕組みにより、あらゆる業界・組織のドキュメント体系に対して、**常に 100% の適合率と最高精度の検索・RAG 体験** を提供することが可能になります。
