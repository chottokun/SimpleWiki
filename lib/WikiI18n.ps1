# ==============================================================================
#  SimpleWiki 多言語化 (i18n) モジュール
#  対応: Windows PowerShell 5.1 / PowerShell 7+
#  文字コード: UTF-8 with BOM
# ==============================================================================

$script:I18n = @{
    "ja" = @{
        "brand_title"               = "📖 SimpleWiki"
        "home"                      = "🏠 ホーム"
        "recent_updates"            = "🕒 最近の更新"
        "tags"                      = "🏷️ タグ一覧"
        "maintenance"               = "🧹 メンテナンス"
        "authors"                   = "👥 著者一覧"
        "api_json"                  = "🤖 API (JSON)"
        "settings"                  = "⚙️ 設定"
        "search_placeholder"        = "Wikiを検索..."
        "search_btn"                = "検索"
        "doc_list_title"            = "📄 ドキュメント一覧"
        "no_content"                = "このフォルダにはコンテンツがありません。"
        "items_count"               = "{0} 件のアイテム"
        "no_index_warning"          = "ℹ️ index.md / README.md がないため、フォルダ一覧を表示しています。"
        "recent_updates_title"      = "🕒 最近の更新ドキュメント"
        "recent_updates_desc"       = "Wiki内の全ドキュメントを更新日順に表示しています。"
        "table_col_last_updated"    = "最終更新日"
        "table_col_title"           = "タイトル"
        "table_col_domain"          = "ドメイン"
        "table_col_author"          = "著者"
        "table_col_status"          = "状態"
        "tag_list_title"            = "🏷️ タグ一覧"
        "tag_results_title"         = "🏷️ タグ: {0}"
        "back_to_tags"              = "← 全タグ一覧へ戻る"
        "maint_dashboard_title"     = "🧹 品質・メンテナンスダッシュボード"
        "maint_dashboard_desc"      = "ドキュメントの風化を防ぎ、ナレッジの信頼性を維持するための管理画面です。"
        "maint_stale_docs"          = "⚠️ 更新停滞ドキュメント (最終更新から365日以上経過)"
        "maint_drafts"              = "📝 下書き一覧 (status: draft)"
        "maint_deprecated"          = "🗑️ 非推奨・旧版一覧 (status: deprecated)"
        "maint_no_docs"             = "該当ドキュメントはありません。"
        "author_list_title"         = "👥 著者一覧"
        "author_results_title"      = "👥 著者: {0}"
        "back_to_authors"           = "← 全著者一覧へ戻る"
        "search_results_title"      = "🔍 OKF ナレッジ検索結果 ({0} 件)"
        "search_keyword_label"      = "キーワード (例: PostgreSQL 障害)"
        "search_status_label"       = "ステータス:"
        "search_status_active"      = "現行 (Active)"
        "search_status_draft"       = "下書き (Draft)"
        "search_status_dep"         = "非推奨 (Deprecated)"
        "search_status_all"         = "すべて (All)"
        "search_domain_label"       = "ドメイン:"
        "search_domain_placeholder" = "例: infrastructure"
        "search_domain_prefix"      = "📁 ドメイン: "
        "search_score"              = "(関連度スコア: {0})"
        "search_no_results"         = "該当するドキュメントが見つかりませんでした。"
        "edit_doc_btn"              = "✏️ 編集"
        "metadata_card_title"       = "ℹ️ ドキュメント メタデータ (OKF)"
        "metadata_author"           = "著者: "
        "metadata_last_updated"     = "最終更新日: "
        "metadata_version"          = "バージョン: "
        "metadata_reviewer"         = "レビュアー: "
        "metadata_contributors"     = "共同執筆者: "
        "metadata_related"          = "関連ドキュメント: "
        "superseded_by_notice"      = "後継ドキュメント: "
        "unknown"                   = "不明"
        "warning_deprecated"        = "⚠️ <strong>警告: 非推奨ドキュメント</strong><br>このドキュメントは非推奨または旧版です。最新の情報を参照してください。"
        "editor_title"              = "📝 Markdown エディター"
        "editor_latest_version"     = "最新版 (編集用)"
        "editor_gen_prefix"         = "世代 {0} (.bak{0})"
        "editor_placeholder"        = "Markdown を記述してください..."
        "editor_cancel_btn"         = "キャンセル"
        "editor_save_btn"           = "保存"
        "editor_loading"            = "読み込み中..."
        "editor_history_loading"    = "履歴読込中..."
        "editor_load_error"         = "エラー: 読み込みに失敗しました。"
        "editor_backup_load_err"    = "エラー: 履歴の読み込みに失敗しました。"
        "editor_saved"              = "保存しました。"
        "editor_saved_warning"      = "保存しました。`n`n⚠️ YAML Front Matter に記述エラーが見つかりました:`n・"
        "editor_warning_yaml"       = "⚠️ YAML Front Matter に記述エラーが見つかりました:"
        "chat_widget_btn"           = "🤖 Wiki AI チャット"
        "chat_header_title"         = "🤖 OKF Wiki AI アシスタント"
        "chat_clear_history"        = "🧹 履歴クリア"
        "chat_expand"               = "⛶ 拡大"
        "chat_collapse"             = "🗗 縮小"
        "chat_mode_label"           = "モード:"
        "chat_include_current"      = "📄 開いているページを含める"
        "chat_welcome_msg"          = "こんにちは！Wiki内のナレッジを元にお答えします。質問を入力してください。"
        "chat_input_placeholder"    = "Wikiに質問..."
        "chat_send_btn"             = "送信"
        "chat_reset_history"        = "会話履歴をリセットしました。質問を入力してください。"
        "chat_thinking_fast"        = "⚡ 検索・生成中..."
        "chat_thinking_agent"       = "🧠 自律深掘り調査中..."
        "chat_comm_error"           = "⚠️ 通信エラーが発生しました。"
        "chat_error_prefix"         = "⚠️ エラー: "
        "chat_agent_thinking"       = "🧠 Agent 思考プロセス ({0} ステップ)"
        "chat_source_docs"          = "📖 <strong>根拠ドキュメント (Markdown):</strong>"
        "chat_source_empty"         = "📖 <strong>根拠ドキュメント:</strong> なし (特定のドキュメント参照なし)"
        "chat_copy_btn"             = "📋 コピー"
        "chat_copy_completed"       = "✓ コピー完了"
        "sidebar_clear_cache"       = "🔄 キャッシュクリア"
        "sidebar_processing"        = "⏳ 処理中..."
        "sidebar_clear_failed"      = "キャッシュクリアに失敗しました。"
        "sidebar_error"             = "エラーが発生しました。"
        "default_system_prompt"         = "あなたはWikiのナレッジを元に回答するアシスタントです。提供されたコンテキスト情報のみに基づいて、正確かつ丁寧に回答してください。情報がない場合は『Wiki内に該当する情報が見つかりませんでした』と答えてください。用語のブレも考慮し、言及したうえで回答します。除外条件（〜以外、〜を除く等）が指定された場合はそれに従ってください。"
        "default_agentic_system_prompt" = "あなたはWikiのナレッジを自律調査して回答する Agentic RAG アシスタントです。目次(index.md)を見つけた場合は必ずリンク先の本文(read_doc)まで参照してください。除外条件やノイズ除去には search_okf で '-除外語' や 'NOT 除外語' 構文を活用してください。"
        "settings_title"                = "⚙️ システム設定"
        "settings_desc"             = "検索キャッシュや起動時動作、LLM/RAG連携の各種オプションを設定します。"
        "settings_search_title"     = "🔍 検索＆インデックス設定"
        "settings_prebuild_label"   = "起動時にインデックスを新規生成する"
        "settings_default_off"      = "（デフォルト: オフ）"
        "settings_prebuild_desc"    = "サーバー起動時に全 Markdown ドキュメントのメタデータと本文インデックスを事前構築します。"
        "settings_cache_label"      = "インデックスキャッシュを有効化する"
        "settings_cache_desc"       = "生成したインデックスをディスクに保存し、次回以降の読み込みを高速化します。"
        "settings_cache_folder"     = "キャッシュ保存フォルダ名:"
        "settings_cached_status"    = "現在のメモリ内インデックス状態: {0} 件保持 (最終読み込み: {1})"
        "settings_rebuild_btn"      = "🔄 今すぐインデックス再生成"
        "settings_rag_title"        = "🤖 AI / LLM RAG 設定 ＆ アクティベーション"
        "settings_rag_enable"       = "LLM RAG チャット機能を有効化"
        "settings_machine_id"       = "この PC のマシン ID:"
        "settings_copy_machine_id"  = "📋 マシン ID をコピー"
        "indexing_in_progress"      = "⏳ インデックスを構築しています... ({0}/{1} 件)"
        "indexing_searching"        = "🔍 検索中..."
        "indexing_console_msg"      = "インデックス構築中: [{0}/{1} 件] ({2}%)"
        "indexing_completed"        = "✅ インデックス構築が完了しました ({0} 件)"
        "settings_act_code"         = "アクティベーションコード (ENC:xxxx):"
        "settings_act_code_holder"  = "配布されたアクティベーションコードを貼り付け"
        "settings_act_desc"         = "マシン ID を使って発行されたアクティベーションコードを入力してください。保存時にこの PC 専用の保護形式 (DPAPI) に安全に自動変換されます。"
        "settings_act_site_link"    = "👉 アクティベーションコードの発行はこちら"
        "settings_api_url"          = "API エンドポイント URL:"
        "settings_model"            = "使用モデル名:"
        "settings_save_btn"         = "💾 設定を保存する"
        "settings_saved_success"    = "✅ 設定を正常に保存しました。"
        "settings_saved_error"      = "❌ 保存エラー: "
        "settings_comm_error"       = "❌ 通信エラーが発生しました。"
        "settings_rebuild_running"  = "⏳ インデックス構築中..."
        "settings_rebuild_start"    = "⏳ インデックスを再構築しています... 完了までお待ちください"
        "settings_rebuild_failed"   = "❌ 再生成失敗: "
        "settings_clear_all_cache"  = "🗑️ ローカルキャッシュ全消去"
        "settings_clear_all_desc"   = "起動元に保存された全フォルダのインデックスキャッシュ (.cache/.index-cache-*.json) を一括消去します。"
        "settings_clear_all_confirm"= "保存されているすべてのインデックスキャッシュを消去しますか？"
        "settings_clear_all_running"= "⏳ キャッシュ消去中..."
        "settings_clear_all_success"= "✅ ローカルキャッシュを全消去しました ({0} 件のファイルを削除)"
        "settings_clear_all_failed" = "❌ キャッシュ消去失敗: "
        "settings_not_run"          = "未実行"
        "shutdown_btn"              = "⏻ 終了"
        "shutdown_confirm"          = "SimpleWiki サーバーを終了しますか？"
        "shutdown_done_title"       = "🛑 サーバーを停止しました"
        "shutdown_done_desc"        = "Wiki サーバーは正常に終了しました。ブラウザのタブを閉じてください。"
        "settings_server_title"     = "🛑 サーバー制御"
        "settings_shutdown_desc"    = "現在稼働中の Wiki サーバープロセスを安全に停止します。"
        "settings_shutdown_btn"     = "🛑 サーバーを停止する"
    }
    "en" = @{
        "brand_title"               = "📖 SimpleWiki"
        "home"                      = "🏠 Home"
        "recent_updates"            = "🕒 Recent Updates"
        "tags"                      = "🏷️ Tags"
        "maintenance"               = "🧹 Maintenance"
        "authors"                   = "👥 Authors"
        "api_json"                  = "🤖 API (JSON)"
        "settings"                  = "⚙️ Settings"
        "search_placeholder"        = "Search Wiki..."
        "search_btn"                = "Search"
        "doc_list_title"            = "📄 Document List"
        "no_content"                = "This folder contains no content."
        "items_count"               = "{0} items"
        "no_index_warning"          = "ℹ️ Showing directory listing because index.md / README.md is missing."
        "recent_updates_title"      = "🕒 Recent Updates"
        "recent_updates_desc"       = "Displaying all documents in the Wiki sorted by update date."
        "table_col_last_updated"    = "Last Updated"
        "table_col_title"           = "Title"
        "table_col_domain"          = "Domain"
        "table_col_author"          = "Author"
        "table_col_status"          = "Status"
        "tag_list_title"            = "🏷️ Tags"
        "tag_results_title"         = "🏷️ Tag: {0}"
        "back_to_tags"              = "← Back to all tags"
        "maint_dashboard_title"     = "🧹 Quality & Maintenance Dashboard"
        "maint_dashboard_desc"      = "Management screen to keep documents fresh and maintain knowledge reliability."
        "maint_stale_docs"          = "⚠️ Stale Documents (No updates for 365+ days)"
        "maint_drafts"              = "📝 Draft List (status: draft)"
        "maint_deprecated"          = "🗑️ Deprecated/Outdated List (status: deprecated)"
        "maint_no_docs"             = "No matching documents found."
        "author_list_title"         = "👥 Authors"
        "author_results_title"      = "👥 Author: {0}"
        "back_to_authors"           = "← Back to all authors"
        "search_results_title"      = "🔍 OKF Knowledge Search Results ({0} items)"
        "search_keyword_label"      = "Keywords (e.g., PostgreSQL issue)"
        "search_status_label"       = "Status:"
        "search_status_active"      = "Active"
        "search_status_draft"       = "Draft"
        "search_status_dep"         = "Deprecated"
        "search_status_all"         = "All"
        "search_domain_label"       = "Domain:"
        "search_domain_placeholder" = "e.g., infrastructure"
        "search_domain_prefix"      = "📁 Domain: "
        "search_score"              = "(Relevance Score: {0})"
        "search_no_results"         = "No matching documents were found."
        "edit_doc_btn"              = "✏️ Edit"
        "metadata_card_title"       = "ℹ️ Document Metadata (OKF)"
        "metadata_author"           = "Author: "
        "metadata_last_updated"     = "Last Updated: "
        "metadata_version"          = "Version: "
        "metadata_reviewer"         = "Reviewer: "
        "metadata_contributors"     = "Contributors: "
        "metadata_related"          = "Related Documents: "
        "superseded_by_notice"      = "Superseded by: "
        "unknown"                   = "Unknown"
        "warning_deprecated"        = "⚠️ <strong>Warning: Deprecated Document</strong><br>This document is deprecated or outdated. Please refer to the latest information."
        "editor_title"              = "📝 Markdown Editor"
        "editor_latest_version"     = "Latest (For Editing)"
        "editor_gen_prefix"         = "Gen {0} (.bak{0})"
        "editor_placeholder"        = "Write Markdown content here..."
        "editor_cancel_btn"         = "Cancel"
        "editor_save_btn"           = "Save"
        "editor_loading"            = "Loading..."
        "editor_history_loading"    = "Loading history..."
        "editor_load_error"         = "Error: Failed to load."
        "editor_backup_load_err"    = "Error: Failed to load backup history."
        "editor_saved"              = "Saved successfully."
        "editor_saved_warning"      = "Saved successfully.`n`n⚠️ YAML Front Matter format error found:`n・"
        "editor_warning_yaml"       = "⚠️ YAML Front Matter format error found:"
        "chat_widget_btn"           = "🤖 Wiki AI Chat"
        "chat_header_title"         = "🤖 OKF Wiki AI Assistant"
        "chat_clear_history"        = "🧹 Clear History"
        "chat_expand"               = "⛶ Expand"
        "chat_collapse"             = "🗗 Collapse"
        "chat_mode_label"           = "Mode:"
        "chat_include_current"      = "📄 Include current page"
        "chat_welcome_msg"          = "Hello! I will answer based on the knowledge in the Wiki. Please enter your question."
        "chat_input_placeholder"    = "Ask Wiki..."
        "chat_send_btn"             = "Send"
        "chat_reset_history"        = "Conversation history has been reset. Please enter your question."
        "chat_thinking_fast"        = "⚡ Searching & Generating..."
        "chat_thinking_agent"       = "🧠 Investigating deeply..."
        "chat_comm_error"           = "⚠️ Communication error occurred."
        "chat_error_prefix"         = "⚠️ Error: "
        "chat_agent_thinking"       = "🧠 Agent Thinking Process ({0} steps)"
        "chat_source_docs"          = "📖 <strong>Source Documents (Markdown):</strong>"
        "chat_source_empty"         = "📖 <strong>Source Documents:</strong> None (no specific document referenced)"
        "chat_copy_btn"             = "📋 Copy"
        "chat_copy_completed"       = "✓ Copied"
        "sidebar_clear_cache"       = "🔄 Clear Cache"
        "sidebar_processing"        = "⏳ Processing..."
        "sidebar_clear_failed"      = "Failed to clear cache."
        "sidebar_error"             = "An error occurred."
        "default_system_prompt"         = "You are an assistant who answers based on the knowledge of the Wiki. Please reply accurately and politely based strictly on the provided context information. If the information is not found, reply that it was not found in the Wiki. Please also consider variations in terminology and mention them when answering. Follow exclusion criteria if specified (e.g., excluding X, without Y)."
        "default_agentic_system_prompt" = "You are an Agentic RAG assistant that autonomously investigates Wiki knowledge to answer questions. If you find a table of contents (index.md), be sure to refer to the target document body (read_doc). For exclusion requirements or noise reduction, utilize '-keyword' or 'NOT keyword' syntax in search_okf."
        "settings_title"                = "⚙️ System Settings"
        "settings_desc"             = "Configure search cache, startup behavior, and LLM/RAG integration options."
        "settings_search_title"     = "🔍 Search & Index Settings"
        "settings_prebuild_label"   = "Prebuild index on server startup"
        "settings_default_off"      = "(Default: Off)"
        "settings_prebuild_desc"    = "Prebuild metadata and body search index for all Markdown documents upon server launch."
        "settings_cache_label"      = "Enable index cache"
        "settings_cache_desc"       = "Save generated index to disk to accelerate subsequent startups."
        "settings_cache_folder"     = "Cache folder name:"
        "settings_cached_status"    = "Current in-memory index state: {0} items (Last loaded: {1})"
        "settings_rebuild_btn"      = "🔄 Rebuild Index Now"
        "settings_rag_title"        = "🤖 AI / LLM RAG Settings & Activation"
        "settings_rag_enable"       = "Enable LLM RAG Chat"
        "settings_machine_id"       = "This PC's Machine ID:"
        "settings_copy_machine_id"  = "📋 Copy Machine ID"
        "indexing_in_progress"      = "⏳ Building search index... ({0}/{1} files)"
        "indexing_searching"        = "🔍 Searching..."
        "indexing_console_msg"      = "Building index: [{0}/{1} files] ({2}%)"
        "indexing_completed"        = "✅ Index building completed ({0} files)"
        "settings_act_code"         = "Activation Code (ENC:xxxx):"
        "settings_act_code_holder"  = "Paste your distributed activation code"
        "settings_act_desc"         = "Enter the activation code generated for your Machine ID. It will be automatically converted to DPAPI format locked to this PC upon saving."
        "settings_act_site_link"    = "👉 Get your activation code here"
        "settings_api_url"          = "API Endpoint URL:"
        "settings_model"            = "Model Name:"
        "settings_save_btn"         = "💾 Save Settings"
        "settings_saved_success"    = "✅ Settings saved successfully."
        "settings_saved_error"      = "❌ Save error: "
        "settings_comm_error"       = "❌ Communication error occurred."
        "settings_rebuild_running"  = "⏳ Rebuilding index..."
        "settings_rebuild_start"    = "⏳ Rebuilding index... Please wait until completed."
        "settings_rebuild_failed"   = "❌ Rebuild failed: "
        "settings_clear_all_cache"  = "🗑️ Clear All Local Caches"
        "settings_clear_all_desc"   = "Batch delete all index cache files (.cache/.index-cache-*.json) stored in the startup directory."
        "settings_clear_all_confirm"= "Are you sure you want to clear all stored index caches?"
        "settings_clear_all_running"= "⏳ Clearing caches..."
        "settings_clear_all_success"= "✅ Successfully cleared all local caches ({0} files deleted)"
        "settings_clear_all_failed" = "❌ Failed to clear caches: "
        "settings_not_run"          = "Not executed"
        "shutdown_btn"              = "⏻ Shutdown"
        "shutdown_confirm"          = "Are you sure you want to stop the SimpleWiki server?"
        "shutdown_done_title"       = "🛑 Server Stopped"
        "shutdown_done_desc"        = "The Wiki server has stopped. You can safely close this browser tab."
        "settings_server_title"     = "🛑 Server Control"
        "settings_shutdown_desc"    = "Safely shut down the running Wiki server process."
        "settings_shutdown_btn"     = "🛑 Stop Server"
    }
}

function Import-ExternalI18n {
    param (
        [string]$TargetScriptDir
    )
    if ([string]::IsNullOrWhiteSpace($TargetScriptDir)) { return }
    $extI18nPath = Join-Path $TargetScriptDir "i18n.json"
    if (Test-Path -LiteralPath $extI18nPath) {
        try {
            $rawJson = [System.IO.File]::ReadAllText($extI18nPath, [System.Text.Encoding]::UTF8)
            $extI18n = $rawJson | ConvertFrom-Json
            if ($null -ne $extI18n) {
                foreach ($langKey in $extI18n.psobject.Properties.Name) {
                    if (-not $script:I18n.ContainsKey($langKey)) {
                        $script:I18n[$langKey] = @{}
                    }
                    $langObj = $extI18n.$langKey
                    foreach ($prop in $langObj.psobject.Properties) {
                        $script:I18n[$langKey][$prop.Name] = $prop.Value
                    }
                }
            }
        } catch {
            Write-Warning "外部 i18n.json の読み込みに失敗しました: $_"
        }
    }
}

function Get-LocalizedStr {
    param (
        [string]$Key,
        [string]$Lang = "ja",
        [object[]]$FormatArgs = @()
    )
    $text = $Key
    if ($script:I18n.ContainsKey($Lang) -and $script:I18n[$Lang].ContainsKey($Key)) {
        $text = $script:I18n[$Lang][$Key]
    } elseif ($script:I18n.ContainsKey("ja") -and $script:I18n["ja"].ContainsKey($Key)) {
        $text = $script:I18n["ja"][$Key]
    }

    if ($FormatArgs -and $FormatArgs.Length -gt 0) {
        try {
            $text = [string]::Format($text, $FormatArgs)
        } catch {}
    }
    return $text
}

function Get-RequestLanguage {
    param (
        [Parameter(Mandatory = $false)]
        [object]$QueryParams = $null,
        [Parameter(Mandatory = $false)]
        [object]$Cookies = $null,
        [Parameter(Mandatory = $false)]
        [object]$Config = $null
    )

    # 1. Query parameter: ?lang=xx
    if ($null -ne $QueryParams) {
        $rawQLang = $null
        if ($QueryParams -is [System.Collections.IDictionary]) {
            if ($QueryParams.Contains("lang")) {
                $rawQLang = $QueryParams["lang"]
            }
        } elseif ($QueryParams -is [System.Collections.Specialized.NameValueCollection]) {
            $rawQLang = $QueryParams["lang"]
        } elseif ($QueryParams.psobject -and $QueryParams.psobject.Properties["lang"]) {
            $rawQLang = $QueryParams.lang
        }
        if (-not [string]::IsNullOrWhiteSpace($rawQLang)) {
            $qLang = $rawQLang.ToString().ToLower().Trim()
            if ($script:I18n.ContainsKey($qLang)) {
                return $qLang
            }
        }
    }

    # 2. Cookie: lang=xx
    if ($null -ne $Cookies) {
        $cVal = $null
        if ($Cookies -is [System.Net.CookieCollection]) {
            if ($Cookies["lang"]) { $cVal = $Cookies["lang"].Value }
        } elseif ($Cookies -is [System.Collections.IDictionary] -and $Cookies.Contains("lang")) {
            $cVal = $Cookies["lang"]
        }
        if (-not [string]::IsNullOrWhiteSpace($cVal)) {
            $cLang = $cVal.ToString().ToLower().Trim()
            if ($script:I18n.ContainsKey($cLang)) {
                return $cLang
            }
        }
    }

    # 3. config.json: defaultLanguage
    if ($null -ne $Config -and -not [string]::IsNullOrWhiteSpace($Config.defaultLanguage)) {
        $defLang = $Config.defaultLanguage.ToString().ToLower().Trim()
        if ($script:I18n.ContainsKey($defLang)) {
            return $defLang
        }
    }

    # 4. Default: ja
    return "ja"
}

function ConvertTo-JsString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$InputString = ""
    )
    if ([string]::IsNullOrEmpty($InputString)) { return "" }
    return $InputString.Replace("\", "\\").Replace("`r`n", "\n").Replace("`n", "\n").Replace("`r", "\n").Replace('"', '\"').Replace("'", "\'")
}


