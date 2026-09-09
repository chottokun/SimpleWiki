# ==============================================================================
#  WikiViewsSettings.ps1
#  SimpleWiki - Settings & Maintenance Views
#  Encoding: UTF-8 with BOM
# ==============================================================================

function Get-MaintenanceViewHtml {
    param (
        [string]$Lang = "ja"
    )

    Initialize-WikiIndex -TargetWikiDir $wikiDir
    $now = Get-Date

    $staleDocs      = @($script:WikiIndex | Where-Object { $_.Status -eq "active" -and ($now - $_.LastUpdated).TotalDays -ge 365 })
    $draftDocs      = @($script:WikiIndex | Where-Object { $_.Status -eq "draft" })
    $deprecatedDocs = @($script:WikiIndex | Where-Object { $_.Status -eq "deprecated" })

    $maintTitle   = Get-LocalizedStr -Key "maint_dashboard_title" -Lang $Lang
    $maintDesc    = Get-LocalizedStr -Key "maint_dashboard_desc" -Lang $Lang
    $maintStale   = Get-LocalizedStr -Key "maint_stale_docs" -Lang $Lang
    $maintDraft   = Get-LocalizedStr -Key "maint_drafts" -Lang $Lang
    $maintDep     = Get-LocalizedStr -Key "maint_deprecated" -Lang $Lang
    $maintNoDocs  = Get-LocalizedStr -Key "maint_no_docs" -Lang $Lang

    return @"
<h1>$maintTitle</h1>
<p>$maintDesc</p>

<div class="maint-section warning-box">
    <h2>$maintStale</h2>
    $(Render-DocList $staleDocs $maintNoDocs)
</div>

<div class="maint-section info-box">
    <h2>$maintDraft</h2>
    $(Render-DocList $draftDocs $maintNoDocs)
</div>

<div class="maint-section danger-box">
    <h2>$maintDep</h2>
    $(Render-DocList $deprecatedDocs $maintNoDocs)
</div>
"@
}

function Get-SettingsViewData {
    param (
        [string]$Lang = "ja"
    )

    $config = Get-ConfigJson -TargetScriptDir $scriptDir

    $editorEnabledChecked = if ($config.editor -and $null -ne $config.editor.enabled) {
        if ($config.editor.enabled -eq $true) { "checked" } else { "" }
    } else { "checked" }
    $editorType           = if ($config.editor -and $config.editor.type) { [string]$config.editor.type } else { "toastui" }
    $editorMaxBackups     = if ($config.editor -and $null -ne $config.editor.maxBackups) { [int]$config.editor.maxBackups } else { 3 }

    $prebuildChecked   = if ($config.search -and $config.search.prebuildIndex -eq $true) { "checked" } else { "" }
    $useCacheChecked   = if ($config.search -and $config.search.useCache -eq $true) { "checked" } else { "" }
    $cacheFolder       = if ($config.search -and -not [string]::IsNullOrWhiteSpace($config.search.cacheFolder)) { [System.Net.WebUtility]::HtmlEncode($config.search.cacheFolder) } else { ".cache" }

    $localMachineId    = Get-MachineFingerprint
    $ragEnabledChecked = if ($config.rag -and $config.rag.enabled -eq $true) { "checked" } else { "" }
    $apiUrl            = if ($config.rag -and $config.rag.apiUrl) { [System.Net.WebUtility]::HtmlEncode($config.rag.apiUrl) } else { "http://localhost:11434/v1" }
    $model             = if ($config.rag -and $config.rag.model) { [System.Net.WebUtility]::HtmlEncode($config.rag.model) } else { "qwen2.5-coder-7b-instruct" }
    $userEmail         = if ($config.rag -and $config.rag.userEmail) { [System.Net.WebUtility]::HtmlEncode($config.rag.userEmail) } else { "" }

    $cachedCount = if ($null -ne $script:WikiIndex) { $script:WikiIndex.Count } else { 0 }
    $notRunText  = Get-LocalizedStr -Key "settings_not_run" -Lang $Lang
    $lastScanStr = if ($script:WikiIndexLastScan -and $script:WikiIndexLastScan -gt [DateTime]::MinValue) { $script:WikiIndexLastScan.ToString("yyyy-MM-dd HH:mm:ss") } else { $notRunText }

    $rawIndexingInProg = Get-LocalizedStr -Key "indexing_in_progress" -Lang $Lang -FormatArgs @("__INDEX_CURR__", "__INDEX_TOTAL__")

    return [PSCustomObject]@{
        Lang              = $Lang
        EditorEnabledChecked = $editorEnabledChecked
        EditorType           = $editorType
        EditorMaxBackups     = $editorMaxBackups
        PrebuildChecked   = $prebuildChecked
        UseCacheChecked   = $useCacheChecked
        CacheFolder       = $cacheFolder
        LocalMachineId    = $localMachineId
        RagEnabledChecked = $ragEnabledChecked
        ApiUrl            = $apiUrl
        Model             = $model
        UserEmail         = $userEmail

        TitleLbl          = Get-LocalizedStr -Key "settings_title" -Lang $Lang
        DescLbl           = Get-LocalizedStr -Key "settings_desc" -Lang $Lang
        EditorTitleLbl    = Get-LocalizedStr -Key "settings_editor_title" -Lang $Lang
        EditorEnableLbl   = Get-LocalizedStr -Key "settings_editor_enable" -Lang $Lang
        EditorDescLbl     = Get-LocalizedStr -Key "settings_editor_desc" -Lang $Lang
        EditorTypeLbl     = Get-LocalizedStr -Key "settings_editor_type" -Lang $Lang
        EditorTypeDescLbl = Get-LocalizedStr -Key "settings_editor_type_desc" -Lang $Lang
        EditorTypeToastUiLbl  = Get-LocalizedStr -Key "settings_editor_type_toastui" -Lang $Lang
        EditorTypeTextAreaLbl = Get-LocalizedStr -Key "settings_editor_type_textarea" -Lang $Lang
        EditorMaxBackupsLbl = Get-LocalizedStr -Key "settings_editor_max_backups" -Lang $Lang
        SearchTitleLbl    = Get-LocalizedStr -Key "settings_search_title" -Lang $Lang
        PrebuildLbl       = Get-LocalizedStr -Key "settings_prebuild_label" -Lang $Lang
        DefOffLbl         = Get-LocalizedStr -Key "settings_default_off" -Lang $Lang
        PrebuildDesc      = Get-LocalizedStr -Key "settings_prebuild_desc" -Lang $Lang
        CacheLbl          = Get-LocalizedStr -Key "settings_cache_label" -Lang $Lang
        CacheDesc         = Get-LocalizedStr -Key "settings_cache_desc" -Lang $Lang
        CacheFoldLbl      = Get-LocalizedStr -Key "settings_cache_folder" -Lang $Lang
        CachedStatLbl     = Get-LocalizedStr -Key "settings_cached_status" -Lang $Lang -FormatArgs @($cachedCount, $lastScanStr)
        RebuildBtnLbl     = Get-LocalizedStr -Key "settings_rebuild_btn" -Lang $Lang
        RagTitleLbl       = Get-LocalizedStr -Key "settings_rag_title" -Lang $Lang
        RagEnableLbl      = Get-LocalizedStr -Key "settings_rag_enable" -Lang $Lang
        MachineIdLbl      = Get-LocalizedStr -Key "settings_machine_id" -Lang $Lang
        CopyMachineLbl    = Get-LocalizedStr -Key "settings_copy_machine_id" -Lang $Lang
        CopiedLbl         = Get-LocalizedStr -Key "settings_copied" -Lang $Lang
        ActCodeLbl        = Get-LocalizedStr -Key "settings_act_code" -Lang $Lang
        ActHolderLbl      = Get-LocalizedStr -Key "settings_act_code_holder" -Lang $Lang
        ActDescLbl        = Get-LocalizedStr -Key "settings_act_desc" -Lang $Lang
        ApiUrlLbl         = Get-LocalizedStr -Key "settings_api_url" -Lang $Lang
        ModelLbl          = Get-LocalizedStr -Key "settings_model" -Lang $Lang
        SaveBtnLbl        = Get-LocalizedStr -Key "settings_save_btn" -Lang $Lang
        ServerTitleLbl    = Get-LocalizedStr -Key "settings_server_title" -Lang $Lang
        ServerDescLbl     = Get-LocalizedStr -Key "settings_shutdown_desc" -Lang $Lang
        ShutdownBtnLbl    = Get-LocalizedStr -Key "settings_shutdown_btn" -Lang $Lang
        SavedSuccessJs    = ConvertTo-JsString (Get-LocalizedStr -Key "settings_saved_success" -Lang $Lang)
        SavedErrorJs      = ConvertTo-JsString (Get-LocalizedStr -Key "settings_saved_error" -Lang $Lang)
        CommErrorJs       = ConvertTo-JsString (Get-LocalizedStr -Key "settings_comm_error" -Lang $Lang)
        RebuildRunJs      = ConvertTo-JsString (Get-LocalizedStr -Key "settings_rebuild_running" -Lang $Lang)
        RebuildStartJs    = ConvertTo-JsString (Get-LocalizedStr -Key "settings_rebuild_start" -Lang $Lang)
        RebuildFailJs     = ConvertTo-JsString (Get-LocalizedStr -Key "settings_rebuild_failed" -Lang $Lang)
        ClearAllBtnLbl    = Get-LocalizedStr -Key "settings_clear_all_cache" -Lang $Lang
        ClearAllDesc      = Get-LocalizedStr -Key "settings_clear_all_desc" -Lang $Lang
        ClearAllConfJs    = ConvertTo-JsString (Get-LocalizedStr -Key "settings_clear_all_confirm" -Lang $Lang)
        ClearAllRunJs     = ConvertTo-JsString (Get-LocalizedStr -Key "settings_clear_all_running" -Lang $Lang)
        ClearAllFailJs    = ConvertTo-JsString (Get-LocalizedStr -Key "settings_clear_all_failed" -Lang $Lang)
        IndexingInProgJs  = ConvertTo-JsString $rawIndexingInProg
    }
}

function Render-SettingsEditorCard {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    param ([PSCustomObject]$Data)

    $selToastUi  = if ($Data.EditorType -eq "toastui") { "selected" } else { "" }
    $selTextarea = if ($Data.EditorType -eq "textarea") { "selected" } else { "" }

    return @"
        <div class="okf-card">
            <div class="okf-card-header">$($Data.EditorTitleLbl)</div>
            <div style="margin-top: 15px; display: flex; flex-direction: column; gap: 12px;">
                <label style="display: flex; align-items: center; gap: 10px; cursor: pointer;">
                    <input type="checkbox" id="editorEnabled" name="editorEnabled" $($Data.EditorEnabledChecked)>
                    <span><strong>$($Data.EditorEnableLbl)</strong></span>
                </label>
                <div style="font-size: 13px; color: #586069; margin-left: 24px;">
                    $($Data.EditorDescLbl)
                </div>

                <div style="margin-left: 24px; margin-top: 5px;">
                    <label for="editorType" style="font-size: 13px; font-weight: bold;">$($Data.EditorTypeLbl)</label><br>
                    <select id="editorType" name="editorType" style="padding: 6px; border: 1px solid #ccc; border-radius: 4px; margin-top: 4px; font-size: 13px;">
                        <option value="toastui" $selToastUi>$($Data.EditorTypeToastUiLbl)</option>
                        <option value="textarea" $selTextarea>$($Data.EditorTypeTextAreaLbl)</option>
                    </select>
                    <div style="font-size: 12px; color: #666; margin-top: 2px;">$($Data.EditorTypeDescLbl)</div>
                </div>

                <div style="margin-left: 24px; margin-top: 5px;">
                    <label for="editorMaxBackups" style="font-size: 13px; font-weight: bold;">$($Data.EditorMaxBackupsLbl)</label><br>
                    <input type="number" id="editorMaxBackups" name="editorMaxBackups" value="$($Data.EditorMaxBackups)" min="0" max="100" style="width: 120px; padding: 6px; border: 1px solid #ccc; border-radius: 4px; margin-top: 4px;" required>
                </div>
            </div>
        </div>
"@
}

function Render-SettingsSearchCard {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    param ([PSCustomObject]$Data)

    return @"
        <div class="okf-card">
            <div class="okf-card-header">$($Data.SearchTitleLbl)</div>
            <div style="margin-top: 15px; display: flex; flex-direction: column; gap: 12px;">
                <label style="display: flex; align-items: center; gap: 10px; cursor: pointer;">
                    <input type="checkbox" id="prebuildIndex" name="prebuildIndex" $($Data.PrebuildChecked)>
                    <span><strong>$($Data.PrebuildLbl)</strong> $($Data.DefOffLbl)</span>
                </label>
                <div style="font-size: 13px; color: #586069; margin-left: 24px;">
                    $($Data.PrebuildDesc)
                </div>

                <label style="display: flex; align-items: center; gap: 10px; cursor: pointer; margin-top: 8px;">
                    <input type="checkbox" id="useCache" name="useCache" $($Data.UseCacheChecked)>
                    <span><strong>$($Data.CacheLbl)</strong> $($Data.DefOffLbl)</span>
                </label>
                <div style="font-size: 13px; color: #586069; margin-left: 24px;">
                    $($Data.CacheDesc)
                </div>

                <div style="margin-left: 24px; margin-top: 5px;">
                    <label for="cacheFolder" style="font-size: 13px; font-weight: bold;">$($Data.CacheFoldLbl)</label><br>
                    <input type="text" id="cacheFolder" name="cacheFolder" value="$($Data.CacheFolder)" style="width: 250px; padding: 6px; border: 1px solid #ccc; border-radius: 4px; margin-top: 4px;" required>
                </div>
            </div>

            <div style="margin-top: 15px; padding-top: 15px; border-top: 1px solid #eaecef; font-size: 13px; color: #586069; display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px;">
                <div>
                    <strong>$($Data.CachedStatLbl)</strong>
                </div>
                <div style="display: flex; gap: 8px;">
                    <button type="button" id="clearAllCacheBtn" onclick="clearAllCachesNow()" style="padding: 6px 12px; background: #fff; color: #d73a49; border: 1px solid #d1d5da; border-radius: 4px; cursor: pointer; font-weight: bold; display: inline-flex; align-items: center; gap: 4px;">
                        $($Data.ClearAllBtnLbl)
                    </button>
                    <button type="button" id="rebuildBtn" onclick="rebuildIndexNow()" style="padding: 6px 12px; background: #6c757d; color: white; border: none; border-radius: 4px; cursor: pointer; font-weight: bold;">
                        $($Data.RebuildBtnLbl)
                    </button>
                </div>
            </div>
            <div style="font-size: 12px; color: #6a737d; margin-top: 8px;">
                $($Data.ClearAllDesc)
            </div>
        </div>
"@
}

function Render-SettingsRagCard {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    param ([PSCustomObject]$Data)

    return @"
        <div class="okf-card">
            <div class="okf-card-header">$($Data.RagTitleLbl)</div>
            <div style="margin-top: 15px; display: flex; flex-direction: column; gap: 14px;">
                <label style="display: flex; align-items: center; gap: 10px; cursor: pointer;">
                    <input type="checkbox" id="ragEnabled" name="ragEnabled" $($Data.RagEnabledChecked)>
                    <span><strong>$($Data.RagEnableLbl)</strong></span>
                </label>

                <!-- マシン ID 表示 ＆ コピー -->
                <div style="background: #f6f8fa; border: 1px solid #e1e4e8; border-radius: 6px; padding: 12px; margin-left: 24px;">
                    <div style="font-size: 12px; font-weight: bold; color: #586069; margin-bottom: 6px;">$($Data.MachineIdLbl)</div>
                    <div style="display: flex; align-items: center; gap: 10px;">
                        <code id="machineIdText" style="font-family: monospace; font-size: 14px; font-weight: bold; background: #fff; border: 1px solid #d1d5da; padding: 6px 12px; border-radius: 4px; color: #0366d6;">$($Data.LocalMachineId)</code>
                        <button type="button" onclick="copyMachineId(this)" style="padding: 6px 12px; font-size: 12px; background: #fff; border: 1px solid #d1d5da; border-radius: 4px; cursor: pointer; color: #24292e;">
                            $($Data.CopyMachineLbl)
                        </button>
                    </div>
                </div>

                <!-- アクティベーションコード入力欄 -->
                <div style="margin-left: 24px;">
                    <label for="activationCode" style="font-size: 13px; font-weight: bold;">$($Data.ActCodeLbl)</label><br>
                    <input type="text" id="activationCode" name="activationCode" placeholder="$($Data.ActHolderLbl)" style="width: 100%; max-width: 500px; padding: 7px 10px; font-family: monospace; font-size: 13px; border: 1px solid #ccc; border-radius: 4px; margin-top: 4px;">
                    <div style="font-size: 12px; color: #586069; margin-top: 4px;">
                        $($Data.ActDescLbl)
                    </div>
                </div>

                <div style="margin-left: 24px;">
                    <label for="userEmail" style="font-size: 13px; font-weight: bold;">メールアドレス (登録時に入力した場合のみ):</label><br>
                    <input type="email" id="userEmail" name="userEmail" value="$($Data.UserEmail)" placeholder="user@example.com" style="width: 100%; max-width: 350px; padding: 6px 10px; font-size: 13px; border: 1px solid #ccc; border-radius: 4px; margin-top: 4px;">
                </div>

                <div style="margin-left: 24px; display: flex; flex-direction: column; gap: 10px; margin-top: 4px;">
                    <div>
                        <label for="apiUrl" style="font-size: 13px; font-weight: bold;">$($Data.ApiUrlLbl)</label><br>
                        <input type="text" id="apiUrl" name="apiUrl" value="$($Data.ApiUrl)" style="width: 100%; max-width: 400px; padding: 6px; border: 1px solid #ccc; border-radius: 4px; margin-top: 4px;">
                    </div>
                    <div>
                        <label for="model" style="font-size: 13px; font-weight: bold;">$($Data.ModelLbl)</label><br>
                        <input type="text" id="model" name="model" value="$($Data.Model)" style="width: 100%; max-width: 400px; padding: 6px; border: 1px solid #ccc; border-radius: 4px; margin-top: 4px;">
                    </div>
                </div>
            </div>
        </div>
"@
}

function Render-SettingsServerCard {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    param ([PSCustomObject]$Data)

    return @"
    <div class="okf-card" style="margin-top: 30px; border-color: #f5c6cb;">
        <div class="okf-card-header" style="color: #721c24;">$($Data.ServerTitleLbl)</div>
        <div style="margin-top: 12px; font-size: 13px; color: #586069;">
            $($Data.ServerDescLbl)
        </div>
        <div style="margin-top: 15px;">
            <button type="button" onclick="shutdownWikiServer()" style="padding: 8px 18px; background: #dc3545; color: white; border: none; border-radius: 6px; font-size: 13px; font-weight: bold; cursor: pointer;">
                $($Data.ShutdownBtnLbl)
            </button>
        </div>
    </div>
"@
}

function Render-SettingsScript {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    param ([PSCustomObject]$Data)

    return @"
<script>
function copyMachineId(btn) {
    var mid = document.getElementById('machineIdText').innerText.trim();
    if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(mid).then(function() {
            var orig = btn.innerText;
            btn.innerText = '$($Data.CopiedLbl)';
            setTimeout(function() { btn.innerText = orig; }, 2000);
        });
    }
}
var toastTimer = null;
function showToast(msg, isError, duration) {
    var toast = document.getElementById('settingsToast');
    var toastMsg = document.getElementById('settingsToastMsg');
    if (toastTimer) {
        clearTimeout(toastTimer);
        toastTimer = null;
    }
    toast.style.display = 'block';
    toast.style.borderColor = isError ? '#dc3545' : '#28a745';
    toastMsg.style.color = isError ? '#721c24' : '#155724';
    toastMsg.innerText = msg;
    var dur = (typeof duration === 'number') ? duration : 4000;
    if (dur > 0) {
        toastTimer = setTimeout(function() {
            toast.style.display = 'none';
            toastTimer = null;
        }, dur);
    }
}

function saveSettings(e) {
    e.preventDefault();
    var saveBtn = document.getElementById('saveBtn');
    saveBtn.disabled = true;
    saveBtn.innerText = '...';

    var actCodeInput = document.getElementById('activationCode');
    var userEmailInput = document.getElementById('userEmail');

    var payload = {
        editor: {
            enabled: document.getElementById('editorEnabled').checked,
            type: document.getElementById('editorType').value,
            maxBackups: parseInt(document.getElementById('editorMaxBackups').value, 10) || 0
        },
        search: {
            prebuildIndex: document.getElementById('prebuildIndex').checked,
            useCache: document.getElementById('useCache').checked,
            cacheFolder: document.getElementById('cacheFolder').value.trim()
        },
        rag: {
            enabled: document.getElementById('ragEnabled').checked,
            apiUrl: document.getElementById('apiUrl').value.trim(),
            model: document.getElementById('model').value.trim(),
            userEmail: userEmailInput ? userEmailInput.value.trim() : ""
        }
    };
    if (actCodeInput && actCodeInput.value.trim()) {
        payload.rag.activationCode = actCodeInput.value.trim();
    }

    fetch('/api/config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
    })
    .then(function(res) { return res.json(); })
    .then(function(data) {
        saveBtn.disabled = false;
        saveBtn.innerText = '$($Data.SaveBtnLbl)';
        if (data.success) {
            showToast('$($Data.SavedSuccessJs)', false);
        } else {
            showToast('$($Data.SavedErrorJs)' + (data.message || ''), true);
        }
    })
    .catch(function(err) {
        saveBtn.disabled = false;
        saveBtn.innerText = '$($Data.SaveBtnLbl)';
        showToast('$($Data.CommErrorJs)', true);
    });
}

function rebuildIndexNow() {
    var rebuildBtn = document.getElementById('rebuildBtn');
    if (rebuildBtn) {
        rebuildBtn.disabled = true;
        rebuildBtn.innerText = '$($Data.RebuildRunJs)';
    }
    showToast('$($Data.RebuildStartJs)', false, 0);

    var pollTimer = setInterval(function() {
        fetch('/api/indexing-status')
        .then(function(r) { return r.json(); })
        .then(function(st) {
            if (st && st.IsBuilding && st.Total > 0) {
                var txt = '$($Data.IndexingInProgJs)'.replace('__INDEX_CURR__', st.Current).replace('__INDEX_TOTAL__', st.Total);
                showToast(txt, false, 0);
            }
        })
        .catch(function() {});
    }, 400);

    fetch('/api/config?action=rebuild_index', { method: 'POST' })
    .then(function(res) { return res.json(); })
    .then(function(data) {
        clearInterval(pollTimer);
        if (rebuildBtn) {
            rebuildBtn.disabled = false;
            rebuildBtn.innerText = '$($Data.RebuildBtnLbl)';
        }
        if (data.success) {
            showToast('✅ ' + data.message, false, 3000);
            setTimeout(function() { location.reload(); }, 1200);
        } else {
            showToast('$($Data.RebuildFailJs)' + (data.message || ''), true, 5000);
        }
    })
    .catch(function(err) {
        clearInterval(pollTimer);
        if (rebuildBtn) {
            rebuildBtn.disabled = false;
            rebuildBtn.innerText = '$($Data.RebuildBtnLbl)';
        }
        showToast('$($Data.CommErrorJs)', true, 5000);
    });
}

function clearAllCachesNow() {
    if (!confirm('$($Data.ClearAllConfJs)')) {
        return;
    }
    var clearBtn = document.getElementById('clearAllCacheBtn');
    if (clearBtn) {
        clearBtn.disabled = true;
        clearBtn.innerText = '$($Data.ClearAllRunJs)';
    }
    showToast('$($Data.ClearAllRunJs)', false, 0);

    fetch('/api/config?action=clear_all_caches', { method: 'POST' })
    .then(function(res) { return res.json(); })
    .then(function(data) {
        if (clearBtn) {
            clearBtn.disabled = false;
            clearBtn.innerText = '$($Data.ClearAllBtnLbl)';
        }
        if (data.success) {
            showToast('✅ ' + data.message, false, 3000);
            setTimeout(function() { location.reload(); }, 1200);
        } else {
            showToast('$($Data.ClearAllFailJs)' + (data.message || ''), true, 5000);
        }
    })
    .catch(function(err) {
        if (clearBtn) {
            clearBtn.disabled = false;
            clearBtn.innerText = '$($Data.ClearAllBtnLbl)';
        }
        showToast('$($Data.CommErrorJs)', true, 5000);
    });
}
</script>
"@
}

function Get-SettingsViewHtml {
    param (
        [string]$Lang = "ja"
    )

    $data = Get-SettingsViewData -Lang $Lang

    $editorCardHtml = Render-SettingsEditorCard -Data $data
    $searchCardHtml = Render-SettingsSearchCard -Data $data
    $ragCardHtml    = Render-SettingsRagCard -Data $data
    $serverCardHtml = Render-SettingsServerCard -Data $data
    $scriptHtml     = Render-SettingsScript -Data $data

    return @"
<div class="settings-container">
    <h2>$($data.TitleLbl)</h2>
    <p>$($data.DescLbl)</p>

    <div id="settingsToast" class="okf-card" style="display:none; border-left: 4px solid #28a745; margin-bottom: 20px;">
        <span id="settingsToastMsg" style="font-weight: bold;"></span>
    </div>

    <form id="settingsForm" onsubmit="saveSettings(event)" style="display: flex; flex-direction: column; gap: 20px;">
$editorCardHtml

$searchCardHtml

$ragCardHtml

        <div>
            <button type="submit" id="saveBtn" style="padding: 10px 24px; background: #28a745; color: white; border: none; border-radius: 6px; font-size: 15px; font-weight: bold; cursor: pointer;">
                $($data.SaveBtnLbl)
            </button>
        </div>
    </form>

$serverCardHtml
</div>

$scriptHtml
"@
}
