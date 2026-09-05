# ==============================================================================
#  SimpleWiki Editor HTML/JS Template Module
#  Encoding: UTF-8 with BOM
# ==============================================================================

function Get-WikiEditorModalHtml {
    param (
        [string]$Lang = "ja"
    )

    $todayStr           = (Get-Date).ToString("yyyy-MM-dd")
    $edTitle            = Get-LocalizedStr -Key "editor_title" -Lang $Lang
    $edLatest           = Get-LocalizedStr -Key "editor_latest_version" -Lang $Lang
    $edCancel           = Get-LocalizedStr -Key "editor_cancel_btn" -Lang $Lang
    $edSave             = Get-LocalizedStr -Key "editor_save_btn" -Lang $Lang
    $edMetaSectionTitle = Get-LocalizedStr -Key "editor_meta_section_title" -Lang $Lang
    $edMetaToggleHint   = Get-LocalizedStr -Key "editor_meta_toggle_hint" -Lang $Lang
    $edModeForm         = Get-LocalizedStr -Key "editor_mode_form" -Lang $Lang
    $edModeRaw          = Get-LocalizedStr -Key "editor_mode_raw" -Lang $Lang
    $edFieldType        = Get-LocalizedStr -Key "editor_field_type" -Lang $Lang
    $edFieldTitle       = Get-LocalizedStr -Key "editor_field_title" -Lang $Lang
    $edFieldStatus      = Get-LocalizedStr -Key "editor_field_status" -Lang $Lang
    $edStatusDraft      = Get-LocalizedStr -Key "editor_status_draft" -Lang $Lang
    $edStatusStable     = Get-LocalizedStr -Key "editor_status_stable" -Lang $Lang
    $edStatusDeprecated = Get-LocalizedStr -Key "editor_status_deprecated" -Lang $Lang
    $edFieldVersion     = Get-LocalizedStr -Key "editor_field_version" -Lang $Lang
    $edFieldDomain      = Get-LocalizedStr -Key "editor_field_domain" -Lang $Lang
    $edFieldAuthor      = Get-LocalizedStr -Key "editor_field_author" -Lang $Lang
    $edFieldReviewer    = Get-LocalizedStr -Key "editor_field_reviewer" -Lang $Lang
    $edFieldLastUpdated = Get-LocalizedStr -Key "editor_field_last_updated" -Lang $Lang
    $edSetToday         = Get-LocalizedStr -Key "editor_set_today" -Lang $Lang
    $edFieldDesc        = Get-LocalizedStr -Key "editor_field_desc" -Lang $Lang
    $edFieldTags        = Get-LocalizedStr -Key "editor_field_tags" -Lang $Lang
    $edFieldRelated     = Get-LocalizedStr -Key "editor_field_related" -Lang $Lang
    $edFieldSuperseded  = Get-LocalizedStr -Key "editor_field_superseded" -Lang $Lang
    $edAutoDate         = Get-LocalizedStr -Key "editor_auto_date" -Lang $Lang -FormatArgs @($todayStr)
    $edBodyPlaceholder  = Get-LocalizedStr -Key "editor_body_placeholder" -Lang $Lang
    $edShortcutHint     = Get-LocalizedStr -Key "editor_shortcut_hint" -Lang $Lang

    $edLoadingJs        = ConvertTo-JsString (Get-LocalizedStr -Key "editor_loading" -Lang $Lang)
    $edHistoryLoadingJs = ConvertTo-JsString (Get-LocalizedStr -Key "editor_history_loading" -Lang $Lang)
    $edLoadErrorJs      = ConvertTo-JsString (Get-LocalizedStr -Key "editor_load_error" -Lang $Lang)
    $edBackupLoadErrJs  = ConvertTo-JsString (Get-LocalizedStr -Key "editor_backup_load_err" -Lang $Lang)
    $edSavedWarningJs   = ConvertTo-JsString (Get-LocalizedStr -Key "editor_saved_warning" -Lang $Lang)
    $edSavedJs          = ConvertTo-JsString (Get-LocalizedStr -Key "editor_saved" -Lang $Lang)

    $html = @'
    <!-- Wiki Editor Modal -->
    <div id="wikiEditorModal" class="wiki-editor-modal">
        <div class="wiki-editor-container">
            <div class="wiki-editor-header">
                <div style="display: flex; align-items: center; gap: 12px;">
                    <span>$edTitle</span>
                    <select id="wikiEditorHistorySelect" onchange="loadWikiHistoryVersion(this)" style="background: #24292e; color: #fff; border: 1px solid #444; border-radius: 4px; padding: 2px 6px; font-size: 12px; cursor: pointer;">
                        <option value="">$edLatest</option>
                    </select>
                </div>
                <span style="font-size: 12px; color: #ccc;" id="wikiEditorPath"></span>
            </div>

            <!-- Metadata Section Accordion -->
            <div class="wiki-meta-accordion">
                <div class="wiki-meta-header" onclick="toggleMetaAccordion()" title="$edMetaToggleHint">
                    <div style="display: flex; align-items: center; gap: 8px;">
                        <span id="metaAccordionIcon" style="font-size: 11px; font-weight: bold; color: #586069;">▶</span>
                        <span style="font-weight: bold; font-size: 13px; color: #24292e;">$edMetaSectionTitle</span>
                        <span style="font-size: 11px; color: #6a737d;">$edMetaToggleHint</span>
                        <span id="metaAccordionSummary" style="font-size: 11px; color: #0366d6; background: #e1e4e8; padding: 1px 6px; border-radius: 10px; display: none;"></span>
                    </div>
                    <div style="display: flex; gap: 4px;" onclick="event.stopPropagation()">
                        <button id="btnModeForm" type="button" class="wiki-meta-toggle-btn active" onclick="switchYamlMode(false)">$edModeForm</button>
                        <button id="btnModeRaw" type="button" class="wiki-meta-toggle-btn" onclick="switchYamlMode(true)">$edModeRaw</button>
                    </div>
                </div>

                <!-- Collapsible Body Container -->
                <div id="wikiMetaBody" class="wiki-meta-body" style="display: none;">
                    <!-- Form Container -->
                    <div id="yamlFormContainer" class="wiki-meta-grid">
                        <div class="wiki-form-group">
                            <label for="metaType">$edFieldType</label>
                            <input type="text" id="metaType" placeholder="Guide, Concept, Service...">
                        </div>
                        <div class="wiki-form-group">
                            <label for="metaTitle">$edFieldTitle</label>
                            <input type="text" id="metaTitle" oninput="updateMetaSummary()">
                        </div>
                        <div class="wiki-form-group">
                            <label for="metaStatus">$edFieldStatus</label>
                            <select id="metaStatus" onchange="onStatusChange(); updateMetaSummary();">
                                <option value="draft">$edStatusDraft</option>
                                <option value="stable" selected>$edStatusStable</option>
                                <option value="deprecated">$edStatusDeprecated</option>
                            </select>
                        </div>
                        <div class="wiki-form-group">
                            <label for="metaVersion">$edFieldVersion</label>
                            <input type="text" id="metaVersion" placeholder="1.0.0">
                        </div>
                        <div class="wiki-form-group">
                            <label for="metaDomain">$edFieldDomain</label>
                            <input type="text" id="metaDomain" placeholder="infrastructure, api...">
                        </div>
                        <div class="wiki-form-group">
                            <label for="metaAuthor">$edFieldAuthor</label>
                            <input type="text" id="metaAuthor">
                        </div>
                        <div class="wiki-form-group">
                            <label for="metaReviewer">$edFieldReviewer</label>
                            <input type="text" id="metaReviewer">
                        </div>
                        <div class="wiki-form-group">
                            <label for="metaLastUpdated">$edFieldLastUpdated</label>
                            <div style="display: flex; gap: 4px;">
                                <input type="text" id="metaLastUpdated" placeholder="YYYY-MM-DD" style="flex: 1;">
                                <button type="button" onclick="setEditorDateToday()" style="padding: 2px 8px; font-size: 11px; background: #e1e4e8; border: 1px solid #ccc; border-radius: 4px; cursor: pointer;">$edSetToday</button>
                            </div>
                        </div>
                        <div class="wiki-form-group full-width">
                            <label for="metaDesc">$edFieldDesc</label>
                            <input type="text" id="metaDesc">
                        </div>
                        <div class="wiki-form-group full-width">
                            <label for="metaTags">$edFieldTags</label>
                            <input type="text" id="metaTags" list="glossaryTagDatalist" placeholder="tag1, tag2 (カンマ区切り)">
                            <datalist id="glossaryTagDatalist"></datalist>
                        </div>
                        <div class="wiki-form-group full-width">
                            <label for="metaRelated">$edFieldRelated</label>
                            <input type="text" id="metaRelated" placeholder="docs/api/index.md, guides/setup.md (カンマ区切り)">
                        </div>
                        <div id="supersededByGroup" class="wiki-form-group full-width" style="display: none;">
                            <label for="metaSupersededBy" style="color: #856404;">$edFieldSuperseded</label>
                            <input type="text" id="metaSupersededBy" placeholder="docs/new-version.md" style="border-color: #ffeeba; background: #fff3cd;">
                        </div>
                        <div class="wiki-form-group full-width" style="display: flex; align-items: center; gap: 6px; margin-top: 2px;">
                            <input type="checkbox" id="metaAutoDate" checked>
                            <label for="metaAutoDate" style="font-weight: normal; font-size: 12px; color: #586069; cursor: pointer;">$edAutoDate</label>
                        </div>
                    </div>

                    <!-- RAW YAML Container -->
                    <div id="yamlRawContainer" style="display: none; padding: 10px 14px;">
                        <textarea id="rawYamlTextarea" class="wiki-raw-yaml-textarea" placeholder="key: value..."></textarea>
                    </div>
                </div>
            </div>

            <!-- Markdown Body Editor (TOAST UI Editor Container & Fallback Textarea) -->
            <div id="wikiEditorToastUiContainer" style="flex: 1; height: 100%; min-height: 0; display: none; overflow: hidden;"></div>
            <textarea id="wikiEditorBodyTextarea" class="wiki-editor-textarea" placeholder="$edBodyPlaceholder"></textarea>

            <div class="wiki-editor-footer">
                <div style="font-size: 12px; color: #586069;">
                    <span>$edShortcutHint</span>
                </div>
                <div style="display: flex; gap: 8px;">
                    <button class="wiki-editor-cancel-btn" onclick="closeWikiEditor()">$edCancel</button>
                    <button class="wiki-editor-save-btn" onclick="saveWikiMarkdown()">$edSave</button>
                </div>
            </div>
        </div>
    </div>
    <script>
        var isYamlRawMode = false;
        var toastEditorInstance = null;
        var currentEditorType = "toastui";

        function toggleMetaAccordion(forceOpen) {
            var body = document.getElementById("wikiMetaBody");
            var icon = document.getElementById("metaAccordionIcon");
            var isCurrentlyOpen = (body.style.display !== "none");
            var targetOpen = (typeof forceOpen === "boolean") ? forceOpen : !isCurrentlyOpen;

            if (targetOpen) {
                body.style.display = "block";
                icon.textContent = "▼";
                var summaryEl = document.getElementById("metaAccordionSummary");
                if (summaryEl) summaryEl.style.display = "none";
            } else {
                body.style.display = "none";
                icon.textContent = "▶";
                updateMetaSummary();
            }
        }

        function updateMetaSummary() {
            var title = (document.getElementById("metaTitle").value || "").trim();
            var status = document.getElementById("metaStatus").value;
            var summaryEl = document.getElementById("metaAccordionSummary");
            if (!summaryEl) return;
            if (title || status) {
                summaryEl.textContent = (status ? "[" + status + "] " : "") + (title || "Untitled");
                summaryEl.style.display = "inline-block";
            } else {
                summaryEl.style.display = "none";
            }
        }

        function initToastEditor(initialContent) {
            var toastContainer = document.getElementById("wikiEditorToastUiContainer");
            var textareaContainer = document.getElementById("wikiEditorBodyTextarea");

            if (currentEditorType === "toastui" && window.toastui && window.toastui.Editor) {
                textareaContainer.style.display = "none";
                toastContainer.style.display = "block";

                if (!toastEditorInstance) {
                    toastEditorInstance = new toastui.Editor({
                        el: toastContainer,
                        height: '100%',
                        initialEditType: 'markdown',
                        previewStyle: 'vertical',
                        initialValue: initialContent || ""
                    });
                } else {
                    toastEditorInstance.setMarkdown(initialContent || "");
                }
            } else {
                toastContainer.style.display = "none";
                textareaContainer.style.display = "block";
                textareaContainer.value = initialContent || "";
            }
        }

        function getEditorContent() {
            if (currentEditorType === "toastui" && toastEditorInstance) {
                return toastEditorInstance.getMarkdown();
            }
            return document.getElementById("wikiEditorBodyTextarea").value;
        }

        function setEditorContent(text) {
            initToastEditor(text);
        }

        function parseMarkdownWithYaml(mdText) {
            var result = {
                rawYaml: "",
                bodyText: mdText,
                hasYaml: false,
                meta: {}
            };
            if (!mdText) return result;

            var match = mdText.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/);
            if (match) {
                result.hasYaml = true;
                result.rawYaml = match[1].trim();
                result.bodyText = match[2];
            } else {
                var titleMatch = mdText.match(/^#\s+(.+)$/m);
                if (titleMatch) {
                    result.meta.title = titleMatch[1].trim();
                }
                return result;
            }

            var lines = result.rawYaml.split(/\r?\n/);
            var currentListKey = null;
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i];
                if (!line || line.trim().startsWith("#")) continue;

                var listMatch = line.match(/^\s*-\s+(.*)$/);
                if (currentListKey && listMatch) {
                    var itemVal = listMatch[1].trim().replace(/^["']|["']$/g, '');
                    if (!Array.isArray(result.meta[currentListKey])) {
                        result.meta[currentListKey] = [];
                    }
                    result.meta[currentListKey].push(itemVal);
                    continue;
                }

                var kvMatch = line.match(/^([a-zA-Z0-9_\-]+)\s*:\s*(.*)$/);
                if (kvMatch) {
                    var key = kvMatch[1].trim();
                    var keyLower = key.toLowerCase();
                    var val = kvMatch[2].trim();
                    currentListKey = keyLower;

                    if (val.startsWith("[") && val.endsWith("]")) {
                        var arr = val.slice(1, -1).split(",").map(function(s) {
                            return s.trim().replace(/^["']|["']$/g, '');
                        }).filter(Boolean);
                        result.meta[keyLower] = arr;
                    } else if (val) {
                        result.meta[keyLower] = val.replace(/^["']|["']$/g, '');
                    } else {
                        result.meta[keyLower] = "";
                    }
                }
            }
            return result;
        }

        function populateYamlForm(meta) {
            meta = meta || {};
            document.getElementById("metaType").value = meta.type || "";
            document.getElementById("metaTitle").value = meta.title || "";

            var statusSelect = document.getElementById("metaStatus");
            var statusVal = (meta.status || "stable").toLowerCase();
            var found = false;
            for (var i = 0; i < statusSelect.options.length; i++) {
                if (statusSelect.options[i].value === statusVal) {
                    statusSelect.selectedIndex = i;
                    found = true;
                    break;
                }
            }
            if (!found) {
                var opt = document.createElement("option");
                opt.value = statusVal;
                opt.textContent = statusVal;
                statusSelect.appendChild(opt);
                statusSelect.value = statusVal;
            }

            document.getElementById("metaVersion").value = meta.version || "";
            document.getElementById("metaDomain").value = meta.domain || "";
            document.getElementById("metaAuthor").value = meta.author || "";
            document.getElementById("metaReviewer").value = meta.reviewer || "";
            document.getElementById("metaLastUpdated").value = meta.last_updated || meta.lastupdated || "";
            document.getElementById("metaDesc").value = meta.description || "";

            var tagsVal = Array.isArray(meta.tags) ? meta.tags.join(", ") : (meta.tags || "");
            document.getElementById("metaTags").value = tagsVal;

            var relVal = Array.isArray(meta.related) ? meta.related.join(", ") : (meta.related || "");
            document.getElementById("metaRelated").value = relVal;

            document.getElementById("metaSupersededBy").value = meta.superseded_by || meta.supersededby || "";

            var autoDateCheckbox = document.getElementById("metaAutoDate");
            if (autoDateCheckbox) {
                autoDateCheckbox.checked = true;
            }

            window._currentCustomProps = {};
            for (var k in meta) {
                var kLower = k.toLowerCase();
                var stdKeys = ["type", "title", "status", "version", "domain", "author", "reviewer", "last_updated", "lastupdated", "description", "tags", "related", "superseded_by", "supersededby"];
                if (stdKeys.indexOf(kLower) === -1) {
                    window._currentCustomProps[k] = meta[k];
                }
            }

            onStatusChange();
            updateMetaSummary();
        }

        function setEditorDateToday() {
            var d = new Date();
            var y = d.getFullYear();
            var m = String(d.getMonth() + 1).padStart(2, '0');
            var dt = String(d.getDate()).padStart(2, '0');
            document.getElementById("metaLastUpdated").value = y + "-" + m + "-" + dt;
        }

        function generateMarkdownWithYaml(isRawMode) {
            var bodyText = getEditorContent();

            if (isRawMode) {
                var rawYaml = document.getElementById("rawYamlTextarea").value.trim();
                if (!rawYaml) {
                    return bodyText;
                }
                var cleanRawYaml = rawYaml.replace(/^---\r?\n?/, '').replace(/\r?\n?---\r?$/, '');
                return "---\n" + cleanRawYaml + "\n---\n\n" + bodyText;
            }

            var type = document.getElementById("metaType").value.trim();
            var title = document.getElementById("metaTitle").value.trim();
            var status = document.getElementById("metaStatus").value;
            var version = document.getElementById("metaVersion").value.trim();
            var domain = document.getElementById("metaDomain").value.trim();
            var author = document.getElementById("metaAuthor").value.trim();
            var reviewer = document.getElementById("metaReviewer").value.trim();
            var lastUpdated = document.getElementById("metaLastUpdated").value.trim();
            var desc = document.getElementById("metaDesc").value.trim();
            var tagsStr = document.getElementById("metaTags").value.trim();
            var relatedStr = document.getElementById("metaRelated").value.trim();
            var supersededBy = document.getElementById("metaSupersededBy").value.trim();
            var autoDate = document.getElementById("metaAutoDate").checked;

            var yamlLines = [];
            if (title) yamlLines.push("title: \"" + title.replace(/"/g, '\\"') + "\"");
            if (type) yamlLines.push("type: \"" + type.replace(/"/g, '\\"') + "\"");
            if (status) yamlLines.push("status: " + status);
            if (version) yamlLines.push("version: \"" + version.replace(/"/g, '\\"') + "\"");
            if (domain) yamlLines.push("domain: \"" + domain.replace(/"/g, '\\"') + "\"");
            if (author) yamlLines.push("author: \"" + author.replace(/"/g, '\\"') + "\"");
            if (reviewer) yamlLines.push("reviewer: \"" + reviewer.replace(/"/g, '\\"') + "\"");

            if (autoDate) {
                var d = new Date();
                var y = d.getFullYear();
                var m = String(d.getMonth() + 1).padStart(2, '0');
                var dt = String(d.getDate()).padStart(2, '0');
                yamlLines.push("last_updated: " + y + "-" + m + "-" + dt);
            } else if (lastUpdated) {
                yamlLines.push("last_updated: " + lastUpdated);
            }

            if (desc) yamlLines.push("description: \"" + desc.replace(/"/g, '\\"') + "\"");

            if (tagsStr) {
                var tags = tagsStr.split(",").map(function(t) { return t.trim(); }).filter(Boolean);
                if (tags.length > 0) {
                    yamlLines.push("tags: [" + tags.map(function(t) { return "\"" + t.replace(/"/g, '\\"') + "\""; }).join(", ") + "]");
                }
            }

            if (relatedStr) {
                var rels = relatedStr.split(",").map(function(r) { return r.trim(); }).filter(Boolean);
                if (rels.length > 0) {
                    yamlLines.push("related: [" + rels.map(function(r) { return "\"" + r.replace(/"/g, '\\"') + "\""; }).join(", ") + "]");
                }
            }

            if ((status === "deprecated" || status === "archived") && supersededBy) {
                yamlLines.push("superseded_by: \"" + supersededBy.replace(/"/g, '\\"') + "\"");
            }

            if (window._currentCustomProps) {
                for (var k in window._currentCustomProps) {
                    var v = window._currentCustomProps[k];
                    if (Array.isArray(v)) {
                        yamlLines.push(k + ": [" + v.map(function(x) { return "\"" + String(x).replace(/"/g, '\\"') + "\""; }).join(", ") + "]");
                    } else if (typeof v === "object" && v !== null) {
                        yamlLines.push(k + ": " + JSON.stringify(v));
                    } else {
                        yamlLines.push(k + ": \"" + String(v).replace(/"/g, '\\"') + "\"");
                    }
                }
            }

            if (yamlLines.length === 0) {
                return bodyText;
            }

            var yamlHeader = "---\n" + yamlLines.join("\n") + "\n---\n\n";
            return yamlHeader + bodyText;
        }

        function switchYamlMode(toRaw) {
            isYamlRawMode = toRaw;
            var formEl = document.getElementById("yamlFormContainer");
            var rawEl = document.getElementById("yamlRawContainer");
            var btnForm = document.getElementById("btnModeForm");
            var btnRaw = document.getElementById("btnModeRaw");

            if (toRaw) {
                var tempMd = generateMarkdownWithYaml(false);
                var parsed = parseMarkdownWithYaml(tempMd);
                document.getElementById("rawYamlTextarea").value = parsed.rawYaml;

                formEl.style.display = "none";
                rawEl.style.display = "block";
                btnForm.classList.remove("active");
                btnRaw.classList.add("active");
                toggleMetaAccordion(true);
            } else {
                var rawText = document.getElementById("rawYamlTextarea").value.trim();
                var cleanRawText = rawText.replace(/^---\r?\n?/, '').replace(/\r?\n?---\r?$/, '');
                var fullMd = cleanRawText ? ("---\n" + cleanRawText + "\n---\n") : "";
                var parsedFromRaw = parseMarkdownWithYaml(fullMd);
                populateYamlForm(parsedFromRaw.meta);

                rawEl.style.display = "none";
                formEl.style.display = "grid";
                btnRaw.classList.remove("active");
                btnForm.classList.add("active");
            }
        }

        function onStatusChange() {
            var st = (document.getElementById("metaStatus").value || "").toLowerCase();
            var supGroup = document.getElementById("supersededByGroup");
            if (st === "deprecated" || st === "archived") {
                supGroup.style.display = "flex";
            } else {
                supGroup.style.display = "none";
            }
        }

        function openWikiEditor(btn) {
            const relPath = btn.getAttribute("data-relpath");
            if (!relPath) return;

            document.getElementById("wikiEditorPath").textContent = relPath;
            toggleMetaAccordion(false);
            setEditorContent("$edLoadingJs");
            document.getElementById("rawYamlTextarea").value = "";
            switchYamlMode(false);

            const selectEl = document.getElementById("wikiEditorHistorySelect");
            selectEl.innerHTML = '<option value="">' + "$edLatest" + '</option>';

            fetch("/api/config")
                .then(r => r.json())
                .then(cfg => {
                    if (cfg && cfg.editor && cfg.editor.type) {
                        currentEditorType = cfg.editor.type;
                    }
                }).catch(() => {})
                .finally(() => {
                    fetch("/api/raw?relPath=" + encodeURIComponent(relPath))
                        .then(r => r.json())
                        .then(data => {
                            const mdVal = (typeof data.markdown === "object" && data.markdown !== null) ? (data.markdown.value || "") : (data.markdown || "");
                            var parsed = parseMarkdownWithYaml(mdVal);
                            populateYamlForm(parsed.meta);
                            setEditorContent(parsed.bodyText);
                            document.getElementById("rawYamlTextarea").value = parsed.rawYaml;
                        })
                        .catch(err => {
                            setEditorContent("$edLoadErrorJs" + err);
                        });
                });

            fetch("/api/history?relPath=" + encodeURIComponent(relPath))
                .then(r => r.json())
                .then(data => {
                    if (data.history && data.history.length > 0) {
                        data.history.forEach(h => {
                            const opt = document.createElement("option");
                            opt.value = h.version;
                            opt.textContent = h.version + " (" + h.timestamp + ")";
                            selectEl.appendChild(opt);
                        });
                    }
                }).catch(() => {});

            fetch("/api/config?action=glossary")
                .then(r => r.json())
                .then(data => {
                    const datalistEl = document.getElementById("glossaryTagDatalist");
                    if (datalistEl && data.terms) {
                        datalistEl.innerHTML = "";
                        data.terms.forEach(t => {
                            const opt = document.createElement("option");
                            opt.value = t;
                            datalistEl.appendChild(opt);
                        });
                    }
                }).catch(() => {});

            document.getElementById("wikiEditorModal").style.display = "flex";
        }

        function loadWikiHistoryVersion(selectEl) {
            const relPath = document.getElementById("wikiEditorPath").textContent;
            const version = selectEl.value;
            if (!relPath) return;

            let url = "/api/raw?relPath=" + encodeURIComponent(relPath);
            if (version) {
                url += "&version=" + encodeURIComponent(version);
            }

            setEditorContent("$edHistoryLoadingJs");
            fetch(url)
                .then(r => r.json())
                .then(data => {
                    const mdVal = (typeof data.markdown === "object" && data.markdown !== null) ? (data.markdown.value || "") : (data.markdown || "");
                    var parsed = parseMarkdownWithYaml(mdVal);
                    populateYamlForm(parsed.meta);
                    setEditorContent(parsed.bodyText);
                    document.getElementById("rawYamlTextarea").value = parsed.rawYaml;
                })
                .catch(err => {
                    setEditorContent("$edBackupLoadErrJs" + err);
                });
        }

        function switchWikiLanguage(lang) {
            document.cookie = "lang=" + lang + "; path=/; max-age=31536000";
            location.reload();
        }

        function closeWikiEditor() {
            document.getElementById("wikiEditorModal").style.display = "none";
        }

        function saveWikiMarkdown() {
            const relPath = document.getElementById("wikiEditorPath").textContent;
            const finalMarkdown = generateMarkdownWithYaml(isYamlRawMode);

            if (!relPath) return;

            fetch("/api/save", {
                method: "POST",
                headers: { "Content-Type": "application/json; charset=utf-8" },
                body: JSON.stringify({ relPath: relPath, markdown: finalMarkdown })
            })
            .then(r => r.json())
            .then(data => {
                if (data.success) {
                    alert(data.warning ? "$edSavedWarningJs" + data.warning : "$edSavedJs");
                    closeWikiEditor();
                    location.reload();
                } else {
                    alert("Error: " + (data.error || "Save failed"));
                }
            })
            .catch(err => {
                alert("Error saving document: " + err);
            });
        }

        document.addEventListener("DOMContentLoaded", function() {
            var modal = document.getElementById("wikiEditorModal");
            if (modal) {
                window.addEventListener("keydown", function(e) {
                    if (modal.style.display === "flex") {
                        if ((e.ctrlKey || e.metaKey) && e.key === "s") {
                            e.preventDefault();
                            saveWikiMarkdown();
                        } else if (e.key === "Escape") {
                            closeWikiEditor();
                        }
                    }
                });
            }
        });
    </script>
'@

    $tokens = [ordered]@{
        '$edTitle'            = $edTitle
        '$edLatest'           = $edLatest
        '$edCancel'           = $edCancel
        '$edSave'             = $edSave
        '$edMetaSectionTitle' = $edMetaSectionTitle
        '$edMetaToggleHint'   = $edMetaToggleHint
        '$edModeForm'         = $edModeForm
        '$edModeRaw'          = $edModeRaw
        '$edFieldType'        = $edFieldType
        '$edFieldTitle'       = $edFieldTitle
        '$edFieldStatus'      = $edFieldStatus
        '$edStatusDraft'      = $edStatusDraft
        '$edStatusStable'     = $edStatusStable
        '$edStatusDeprecated' = $edStatusDeprecated
        '$edFieldVersion'     = $edFieldVersion
        '$edFieldDomain'      = $edFieldDomain
        '$edFieldAuthor'      = $edFieldAuthor
        '$edFieldReviewer'    = $edFieldReviewer
        '$edFieldLastUpdated' = $edFieldLastUpdated
        '$edSetToday'         = $edSetToday
        '$edFieldDesc'        = $edFieldDesc
        '$edFieldTags'        = $edFieldTags
        '$edFieldRelated'     = $edFieldRelated
        '$edFieldSuperseded'  = $edFieldSuperseded
        '$edAutoDate'         = $edAutoDate
        '$edBodyPlaceholder'  = $edBodyPlaceholder
        '$edShortcutHint'     = $edShortcutHint
        '$edLoadingJs'        = $edLoadingJs
        '$edHistoryLoadingJs' = $edHistoryLoadingJs
        '$edLoadErrorJs'      = $edLoadErrorJs
        '$edBackupLoadErrJs'  = $edBackupLoadErrJs
        '$edSavedWarningJs'   = $edSavedWarningJs
        '$edSavedJs'          = $edSavedJs
    }

    foreach ($entry in $tokens.GetEnumerator()) {
        $html = $html.Replace($entry.Key, [string]$entry.Value)
    }

    return $html
}
