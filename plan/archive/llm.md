これまで設計してきた OKF（Open Knowledge Format）の構造化メタデータ（last_updated / status: deprecated / author） があることで、一般的なRAG（Retrieval-Augmented Generation）で最も問題になる「古い情報をLLMが信じ込んで嘘をつく（ハルシネーション）」という課題をシステム的に防御できるのが最大の強みになります。
1. 全体アーキテクチャ ＆ データフロー
外部のベクトルDBや複雑なPython環境を用意しなくても、PowerShellと既存の「OKF検索エンジン」をそのまま活用して軽量にRAGを実現できます。



Plaintext
 [ ユーザー (ブラウザ) ]
        │  ① チャットで質問: 「基幹DBが接続エラーになった時の手順は？」
        ▼
 [ PowerShell HttpListener (/api/chat) ]
        │  ② 検索モジュールでWiki内をコンテキスト検索 (status: active のみ)
        │  ③ 検索スコア上位 2〜3 件の Markdown 本文 ＋ OKFメタデータを抽出
        │  ④ LLM用システムプロンプト（文脈）を自動生成
        ▼
 [ OpenAI 互換 API エンドポイント ]  <--- config.json で切り替え可能
   ├─ Local:  Ollama / LM Studio / vLLM (http://localhost:11434/v1)
   └─ Cloud:  OpenAI API / Azure / Claude互換 (https://api.openai.com/v1)
        │  ⑤ 回答を生成
        ▼
 [ PowerShell HttpListener ]
        │  ⑥ 回答 ＋ 参考にした出典ドキュメント（リンク）を結合
        ▼
 [ ブラウザに回答を表示 ]


2. 2つのRAG実装アプローチの比較
PowerShell上でRAGを組む場合、以下の2つのアプローチがあります。まずはアプローチA（検索エンジン連動型）から始めるのが最も手軽で高速です。
評価軸
アプローチA: OKF検索連動型（推奨）
アプローチB: Embeddings（ベクトル）型
仕組み
構築済みのOKF検索エンジンで上位数件を抽出し、プロンプトに埋め込む
OpenAI互換の /v1/embeddings でベクトル化し、コサイン類似度で検索
追加ライブラリ
不要（PowerShellのみで完結）
数値計算（C#のMathクラス呼び出し等）が必要
処理速度
爆速（数ミリ秒でコンテキスト抽出）
ベクトル計算・API呼び出しのオーバーヘッドあり
特徴
検索キーワードに素直に反応。OKFメタデータ（著者・更新日）を100%活用
言い換えや曖昧な質問に強い

3. 設定ファイル設計 (config.json)
OpenAI互換APIのエンドポイントやモデル名を外部ファイルで変更できるようにします。



JSON
{
  "rag": {
    "enabled": true,
    "apiUrl": "http://localhost:11434/v1",
    "apiKey": "lm-studio",
    "model": "qwen2.5-coder-7b-instruct",
    "maxContextDocs": 3,
    "systemPrompt": "あなたは社内Wikiのナレッジを元に回答するアシスタントです。提供されたコンテキスト情報のみに基づいて、正確かつ丁寧に回答してください。情報がない場合は『Wiki内に該当する情報が見つかりませんでした』と答えてください。"
  }
}


4. プロンプト生成（OKF × RAGの最大のメリット）
LLMへ渡すプロンプトにOKFメタデータを埋め込むことで、LLMがドキュメントの文脈・鮮度・信頼性を理解して回答できるようになります。
PowerShell側で自動生成するプロンプトイメージ



Plaintext
[システムプロンプト]
あなたは社内Wikiのナレッジを元に回答するアシスタントです。

[参照されたWikiコンテキスト]
---
■ ドキュメント 1: データベース接続障害 一次対応手順書
・ドメイン: インフラ/データベース
・著者: 知識 太郎
・最終更新日: 2026-08-01
・ステータス: Active (現行)
本文:
基幹DBへの接続タイムアウトが発生した場合は、まず...
---

[ユーザーの質問]
基幹DBが接続エラーになった時の手順は？


なぜこれが強力なのか？
非推奨（deprecated）の自動除外: status: active のドキュメントのみをプロンプトに入れるため、古い手順をLLMが教えるリスクをゼロにできます。
出典の自動明示: 回答の末尾に「参照元: [データベース接続障害 一次対応手順書](infrastructure/db.md) (最終更新: 2026-08-01)」を自動付与できます。
5. UI（画面イメージ）
画面の右下に常駐するチャットウィジェット（吹き出しボタン）を配置するか、専用ページ（/chat）を追加します。



Plaintext
+-----------------------------------------------------------------------+
| 📄 データベース接続障害 一次対応手順書                                 |
| (Wikiの本文...)                                                      |
|                                                                       |
|                                         +---------------------------+ |
|                                         | 🤖 Wiki AI アシスタント    | |
|                                         | ------------------------- | |
|                                         | Q: DB接続エラーの対応は？  | |
|                                         |                           | |
|                                         | A: 以下の順で切り分けます | |
|                                         | 1. サービスの稼働確認     | |
|                                         | 2. ポート5432の導通確認   | |
|                                         | 📖 出典: DB接続手順書     | |
|                                         | [質問を入力...     ] [送信] | |
|                                         +---------------------------+ |
+-----------------------------------------------------------------------+


6. 実装に必要なAPI呼び出しコード（PowerShell 5.1）
PowerShellからOpenAI互換APIを呼び出す処理は、Invoke-RestMethod だけで数行で記述できます。



PowerShell
function Invoke-OpenAiChatCompletions {
    param (
        [string]$apiUrl,
        [string]$apiKey,
        [string]$model,
        [string]$systemPrompt,
        [string]$userMessage
    )

    $headers = @{
        "Authorization" = "Bearer $apiKey"
        "Content-Type"  = "application/json; charset=utf-8"
    }

    $body = @{
        model = $model
        messages = @(
            @{ role = "system"; content = $systemPrompt },
            @{ role = "user";   content = $userMessage }
        )
        temperature = 0.3 # 事実に基づかせるため低めに設定
    } | ConvertTo-Json -Depth 5 -Compress

    # UTF-8 でリクエスト送信
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $response = Invoke-RestMethod -Uri "$apiUrl/chat/completions" -Method Post -Headers $headers -Body $bytes
    
    return $response.choices[0].message.content
}


まとめ：実装のロードマップ
config.json の追加: ローカルLLM（Ollama/LM Studio）やOpenAIの接続設定を保持。
/api/chat エンドポイントの追加: 受け取った質問からOKF検索を実行 ➔ コンテキスト抽出 ➔ LLM呼び出し ➔ JSONレスポンス返却。
フロントエンド（JS）の統合: 画面右下に非同期（fetch）で対話できるチャットUIを追加。
既存のPowerShell Wiki基盤のコードを崩すことなく、「追加モジュール」として綺麗に統合できます。
