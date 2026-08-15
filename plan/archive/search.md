# **追加機能実装計画書：OKF文脈検索エンジン**

本ドキュメントは、構築済みの **Markdig ＋ OKF対応 PowerShell ローカルWiki** に対し、OKFメタデータの特性を最大限に活かした「文脈検索エンジン（ファセット検索 ＆ 重み付けスコアリング）」を追加するための詳細な実装計画書です。

## **1\. 機能概要と追加目的**

### **1.1 目的**

単なる「単語の文字列一致（全文検索）」にとどまらず、ドキュメントの持つ属性（title, tags, domain, author, status）を評価軸に加えることで、**「今本当に必要な最新かつ信頼性の高いナレッジ」を瞬時に最上位へ抽出・表示すること**を目的とします。

### **1.2 コア機能**

> 1. **重み付けスコアリング（Relevance Ranking）**: メタデータ（タイトルやタグ）へのヒットを高く評価し、関連度順にソート。  
> 2. **OKFファセットフィルター**: status（Active/Draft/Deprecated）や domain（カテゴリ）による動的なノイズ除去・絞り込み。  
> 3. **deprecated（非推奨）自動抑制**: 古いドキュメントの誤参照を防ぐため、検索スコアを70%自動カットし警告表示。  
> 4. **コンテキストスニペット ＆ キーワードハイライト**: マッチした本文の前後テキストを抽出し、キーワードを \<mark\> タグで黄色にハイライト表示。  
> 5. **ヘッダー常駐検索バー**: どのページを開いていても即座に検索を実行可能。

## **2\. 検索処理アーキテクチャ ＆ データフロー**

Plaintext  
 \[ ユーザー (ブラウザ) \]  
        │  ① URIリクエスト: /search?q=PostgreSQL+障害\&status=active\&domain=インフラ  
        ▼  
 \[ PowerShell HttpListener \]  
        │  ② リクエストパラメータ分解 (q, status, domain)  
        ▼  
 \[ 検索処理モジュール: Get-OKFSearchResultsHtml \]  
        ├─ ③ メモリアレイ ($script:WikiIndex) を全件走査  
        ├─ ④ フィルタリング (status, domain 条件判定)  
        ├─ ⑤ 重み付けスコアリング (Title: \+10, Tags: \+8, Desc: \+5, Domain: \+4, Author: \+3, Body: \+1)  
        ├─ ⑥ AND検索判定 (すべてのキーワードが含まれているか)  
        ├─ ⑦ スコア調整 (status=deprecated はスコア 70% 削減)  
        ├─ ⑧ 関連度スコア順に降順ソート  
        └─ ⑨ スニペット抽出 ＆ キーワード \<mark\> ハイライト処理  
        │  
        ▼  
 \[ 検索結果画面 (HTML) を描画・返却 \]

## **3\. スコアリング ＆ フィルタリング仕様**

### **3.1 スコアリングルール定義**

各キーワード 1 つにつき、メタデータおよび本文の一致状況に応じて以下の加算点を与えます。

| 検索対象フィールド | 加算スコア | 理由 / OKFにおける位置づけ |
| :---- | :---- | :---- |
| **title (タイトル)** | **\+10 点** | 文書のテーマそのものであるため最優先 |
| **tags (タグ)** | **\+8 点** | 意図的に付与されたキーワードのため高評価 |
| **description (概要)** | **\+5 点** | 要約文内での一致は文脈的関連度が高い |
| **domain (ドメイン)** | **\+4 点** | 該当カテゴリに属するナレッジ |
| **author (著者)** | **\+3 点** | 特定の有識者が書いた文書の検索に対応 |
| **body (本文)** | **\+1 点/回** | 本文内でのヒット（上限 10 点まで） |

### **3.2 フィルター ＆ 減点ルール**

* **AND検索ロジック**: 複数キーワード（例: PostgreSQL 障害）が指定された場合、**すべてのキーワードがいずれかのフィールドにヒットしているドキュメントのみ**を出力（OR検索によるノイズを排除）。  
* **非推奨ドキュメントの減点**: status: deprecated の場合、最終算出スコアを **Score \= Math.Floor(Score \* 0.3)**（70%カット）とし、検索結果の最下位付近へ移動させる。

## **4\. UI / UX 画面設計**

### **4.1 ヘッダー常駐検索バー (全ページ共通)**

画面上部ナビゲーションエリアに配置し、Enter キーで即座に /search へ遷移させます。

Plaintext  
\+-----------------------------------------------------------------------------------+  
| 📗 OKF Wiki  | \[🏠 ホーム\] \[🕒 最近の更新\] \[🏷️ タグ\] \[🧹 メンテナンス\] | \[🔍 検索...\] |  
\+-----------------------------------------------------------------------------------+

### **4.2 検索結果ページ (/search) レイアウト**

Plaintext  
\+-----------------------------------------------------------------------------------+  
| 🔍 OKF ナレッジ検索結果 (2 件)                                                     |  
| \+-------------------------------------------------------------------------------+ |  
| | \[ キーワード: PostgreSQL 障害                     \] \[ 🔍 検索 \]              | |  
| | ステータス: \[ 現行 (Active) のみ ▼ \]   ドメイン: \[ すべてのドメイン ▼ \]         | |  
| \+-------------------------------------------------------------------------------+ |  
|                                                                                   |  
| 1\. 📄 データベース接続障害 一次対応手順書  \[ ACTIVE \]            (関連度: 18\)     |  
|    📁 ドメイン: インフラ / DB | 📅 最終更新: 2026-08-01 | 👤 著者: 知識 太郎        |  
|    \#PostgreSQL \#障害対応                                                          |  
|    ... 基幹DBへの接続タイムアウト発生時における \<mark\>PostgreSQL\</mark\> の...       |  
\+-----------------------------------------------------------------------------------+

## **5\. モジュール詳細設計 (追加コード仕様)**

既存の Start-MarkdigWiki.ps1 内に追加する 2 つの関数およびルーティング処理の設計です。

### **5.1 キーワードハイライト処理関数 (Get-HighlightText)**

HTMLエスケープを行った上で、検索キーワードのみを安全に \<mark\> タグで囲みます。

PowerShell  
function Get-HighlightText {  
    param (  
        \[string\]$text,  
        \[string\[\]\]$keywords  
    )  
    if (\[string\]::IsNullOrWhiteSpace($text)) { return "" }  
      
    \# 一旦 HTML エスケープ  
    $safeText \= \[System.Net.WebUtility\]::HtmlEncode($text)  
      
    \# 各キーワードをハイライト化 (大文字小文字を区別しない)  
    foreach ($kw in $keywords) {  
        if (\[string\]::IsNullOrWhiteSpace($kw)) { continue }  
        $escapedKw \= \[regex\]::Escape(\[System.Net.WebUtility\]::HtmlEncode($kw))  
        $safeText \= $safeText \-replace "(?i)($escapedKw)", "\<mark style='background:\#fff3cd; padding:0 2px; border-radius:2px;'\>$1\</mark\>"  
    }  
    return $safeText  
}

### **5.2 OKF検索メイン関数 (Get-OKFSearchResultsHtml)**

PowerShell  
function Get-OKFSearchResultsHtml {  
    param (  
        \[string\]$query,  
        \[string\]$statusFilter \= "active",  
        \[string\]$domainFilter \= ""  
    )

    if (\[string\]::IsNullOrWhiteSpace($query) \-and \[string\]::IsNullOrWhiteSpace($domainFilter)) {  
        return "\<h2\>🔍 OKF ナレッジ検索\</h2\>\<p style='color:\#666;'\>検索キーワードを入力するか、フィルター条件を選択してください。\</p\>"  
    }

    $keywords \= $query \-split '\\s+' | Where-Object { $\_ \-ne "" }  
    $results \= @()

    foreach ($item in $script:WikiIndex) {  
        \# 1\. フィルター判定  
        if ($statusFilter \-eq "active" \-and $item.status \-ne "active") { continue }  
        if ($statusFilter \-eq "draft" \-and $item.status \-ne "draft") { continue }  
        if ($statusFilter \-eq "deprecated" \-and $item.status \-ne "deprecated") { continue }  
        if (\-not \[string\]::IsNullOrWhiteSpace($domainFilter) \-and $item.domain \-notlike "\*$domainFilter\*") { continue }

        $mdText \= Get-Content \-Path $item.filePath \-Raw \-Encoding UTF8  
        $score \= 0  
        $matchedKeywords \= @()

        \# 2\. 重み付けスコアリング  
        foreach ($kw in $keywords) {  
            $kwRegex \= \[regex\]::Escape($kw)  
            $kwMatched \= $false

            if ($item.title \-match $kwRegex) { $score \+= 10; $kwMatched \= $true }  
            if ($item.tags \-match $kwRegex) { $score \+= 8; $kwMatched \= $true }  
            if ($item.description \-match $kwRegex) { $score \+= 5; $kwMatched \= $true }  
            if ($item.domain \-match $kwRegex) { $score \+= 4; $kwMatched \= $true }  
            if ($item.author \-match $kwRegex) { $score \+= 3; $kwMatched \= $true }

            $bodyMatches \= (\[regex\]::Matches($mdText, $kwRegex, "IgnoreCase")).Count  
            if ($bodyMatches \-gt 0) {  
                $score \+= \[Math\]::Min($bodyMatches, 10)  
                $kwMatched \= $true  
            }

            if ($kwMatched) { $matchedKeywords \+= $kw }  
        }

        \# 3\. AND条件検証  
        if ($keywords.Count \-gt 0 \-and $matchedKeywords.Count \-lt $keywords.Count) {  
            continue  
        }

        \# 4\. 非推奨（deprecated）減点処理  
        if ($item.status \-eq "deprecated") {  
            $score \= \[Math\]::Floor($score \* 0.3)  
        }

        if ($score \-gt 0 \-or \[string\]::IsNullOrWhiteSpace($query)) {  
            \# 本文からスニペット行を抽出  
            $snippet \= ""  
            foreach ($line in ($mdText \-split "\`r?\`n")) {  
                if ($line \-notmatch '^\\s\*---' \-and ($keywords | Where-Object { $line \-match \[regex\]::Escape($\_) })) {  
                    $snippet \= $line.Trim()  
                    break  
                }  
            }

            $results \+= \[PSCustomObject\]@{  
                Meta    \= $item  
                Score   \= $score  
                Snippet \= $snippet  
            }  
        }  
    }

    \# 5\. スコア降順ソート  
    $sortedResults \= $results | Sort-Object Score, {$\_.Meta.last\_updated} \-Descending

    \# 6\. HTML 生成 (ハイライト処理を含む)  
    \# \[画面構築コード\]  
    return $html  
}

## **6\. テスト ＆ 検証計画**

機能追加後、以下のテストケースを実施して挙動を検証します。

| テストID | テストケース | 入力値 / 条件 | 期待される動作結果 |
| :---- | :---- | :---- | :---- |
| **TC-01** | 単一キーワード検索 | PostgreSQL | タイトル・タグ・本文のいずれかに含む全文書がヒットすること。 |
| **TC-02** | 複数単語 AND 検索 | PostgreSQL 障害 | **両方の単語が含まれる文書のみ** が出力されること。 |
| **TC-03** | スコアリング順序検証 | タイトル一致 vs 本文のみ一致 | タイトルにキーワードが含まれる文書が、本文のみ一致より\*\*上位（高スコア）\*\*に来ること。 |
| **TC-04** | Status フィルタリング | status=active | 非推奨（deprecated）文書がヒット一覧から除外されること。 |
| **TC-05** | 非推奨文書のスコア減点 | status=all で検索 | deprecated 文書のスコアが 70% 減点され、最下位付近に表示されること。 |
| **TC-06** | ハイライト検証 | キーワード表示 | 検索結果のスニペット内で、キーワードが \<mark\> タグで黄色く囲まれること。 |
| **TC-07** | 特殊文字安全検証 | C\#, (注) などを入力 | エラー（正規表現例外）にならず安全にエスケープ処理されて検索できること。 |

## **7\. 導入ステップ**

> 1. **既存コードへの組み込み**: Start-MarkdigWiki.ps1 内に上記 2 つの関数を追加。  
> 2. **ルーティング拡張**: switch \-Wildcard ($rawPath) に /search\* の分岐を追加。  
> 3. **共通ヘッダー改修**: ナビゲーションバー HTML に \<form action='/search'\> を追加。  
> 4. **動作テスト**: 上記 TC-01 ～ TC-07 を実行して正常動作を確認。