# ==============================================================================
#  WikiViewsStella.ps1
#  SimpleWiki - 3D Stella & Spacetime Cosmos Views
#  Encoding: UTF-8 with BOM
# ==============================================================================

function Get-StellaControlPanelHtml {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSReviewUnusedParameter", "")]
    param (
        [string]$ActiveView = "stella",
        [string]$Lang = "ja"
    )

    Initialize-WikiIndex -TargetWikiDir $wikiDir

    $navStella    = Get-LocalizedStr -Key "stella_view_nav" -Lang $Lang
    $searchHolder = Get-LocalizedStr -Key "stella_search_holder" -Lang $Lang

    $stAll        = Get-LocalizedStr -Key "stella_status_all" -Lang $Lang
    $stActive     = Get-LocalizedStr -Key "stella_status_active" -Lang $Lang
    $stDraft      = Get-LocalizedStr -Key "stella_status_draft" -Lang $Lang
    $stDep        = Get-LocalizedStr -Key "stella_status_deprecated" -Lang $Lang
    $stArch       = Get-LocalizedStr -Key "stella_status_archived" -Lang $Lang
    $tagAll       = Get-LocalizedStr -Key "stella_tag_all" -Lang $Lang
    $resetBtnTxt  = Get-LocalizedStr -Key "stella_btn_reset" -Lang $Lang

    $preset3dTxt  = Get-LocalizedStr -Key "stella_preset_3d" -Lang $Lang
    $presetTopTxt = Get-LocalizedStr -Key "stella_preset_top" -Lang $Lang
    $presetTlTxt  = Get-LocalizedStr -Key "stella_preset_timeline" -Lang $Lang

    $allTags = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($item in $script:WikiIndex) {
        if ($item.Tags) {
            foreach ($t in $item.Tags) {
                if ($t -is [string] -and -not [string]::IsNullOrWhiteSpace($t)) { [void]$allTags.Add($t.Trim()) }
            }
        }
    }

    $tagOptions = foreach ($t in ($allTags | Sort-Object)) {
        $encT = [System.Net.WebUtility]::HtmlEncode($t)
        "<option value='$encT'>🏷️ $encT</option>"
    }
    $tagOptionsStr = $tagOptions -join ""

    return @"
<div class="stella-control-panel">
    <div class="stella-control-left">
        <span style="font-weight: bold; color: #58a6ff; font-size: 13px; margin-right: 4px;">$navStella</span>
        <div class="stella-preset-group">
            <button class="stella-preset-btn active" data-preset="3d" onclick="setStellaPreset('3d')" title="$preset3dTxt">$preset3dTxt</button>
            <button class="stella-preset-btn" data-preset="top" onclick="setStellaPreset('top')" title="$presetTopTxt">$presetTopTxt</button>
            <button class="stella-preset-btn" data-preset="timeline" onclick="setStellaPreset('timeline')" title="$presetTlTxt">$presetTlTxt</button>
        </div>
        <button class="stella-reset-btn" onclick="resetStellaView()" title="$resetBtnTxt">$resetBtnTxt</button>
    </div>
    <div class="stella-control-center">
        <input type="text" id="stellaSearchInput" placeholder="$searchHolder" class="stella-input">
        <select id="stellaStatusSelect" class="stella-select">
            <option value="all">$stAll</option>
            <option value="active">$stActive</option>
            <option value="draft">$stDraft</option>
            <option value="deprecated">$stDep</option>
            <option value="archived">$stArch</option>
        </select>
        <select id="stellaTagSelect" class="stella-select">
            <option value="all">$tagAll</option>
            $tagOptionsStr
        </select>
    </div>
</div>
<style>
    .stella-control-panel { display: flex; align-items: center; justify-content: space-between; background: #161b22; padding: 10px 16px; border-radius: 8px; border: 1px solid #30363d; margin-bottom: 20px; gap: 12px; flex-wrap: wrap; }
    .stella-control-left, .stella-control-center { display: flex; align-items: center; gap: 8px; }
    .stella-preset-group { display: inline-flex; border-radius: 6px; overflow: hidden; border: 1px solid #30363d; }
    .stella-preset-btn { background: #21262d; color: #8b949e; border: none; border-right: 1px solid #30363d; padding: 6px 12px; font-size: 12px; font-weight: bold; cursor: pointer; transition: all 0.2s; }
    .stella-preset-btn:last-child { border-right: none; }
    .stella-preset-btn:hover { background: #30363d; color: #c9d1d9; }
    .stella-preset-btn.active { background: #1f6feb; color: #ffffff; }
    .stella-reset-btn { color: #8b949e; background: #21262d; border: 1px solid #30363d; padding: 6px 12px; border-radius: 6px; font-size: 12px; font-weight: bold; cursor: pointer; transition: all 0.2s; }
    .stella-reset-btn:hover { color: #58a6ff; background: #30363d; border-color: #58a6ff; }
    .stella-input, .stella-select { background: #0d1117; border: 1px solid #30363d; color: #c9d1d9; font-size: 12px; padding: 6px 10px; border-radius: 6px; outline: none; }
    .stella-input { width: 200px; }
    .stella-input:focus, .stella-select:focus { border-color: #58a6ff; }
</style>
"@
}

function Get-StellaViewHtml {
    param (
        [string]$Lang = "ja"
    )

    Initialize-WikiIndex -TargetWikiDir $wikiDir
    $controlPanelHtml = Get-StellaControlPanelHtml -ActiveView "stella" -Lang $Lang

    $previewTitle   = Get-LocalizedStr -Key "stella_preview_title" -Lang $Lang
    $openDocTxt     = Get-LocalizedStr -Key "search_btn" -Lang $Lang
    $navStellaTitle = Get-LocalizedStr -Key "stella_view_nav" -Lang $Lang
    $helpDrag       = Get-LocalizedStr -Key "stella_help_drag" -Lang $Lang
    $helpWheel      = Get-LocalizedStr -Key "stella_help_zoom" -Lang $Lang
    $helpClick      = Get-LocalizedStr -Key "stella_help_click" -Lang $Lang
    $connectedTitle = Get-LocalizedStr -Key "stella_connected_nodes" -Lang $Lang
    $timePastTxt    = Get-LocalizedStr -Key "stella_time_past" -Lang $Lang
    $timePresTxt    = Get-LocalizedStr -Key "stella_time_present" -Lang $Lang

    # Index items serialization
    $indexJson = Get-ApiIndexJson -QueryParams @{ limit = "all" }

    return @"
$controlPanelHtml

<div class="stella-container" style="position: relative; width: 100%; height: calc(100vh - 180px); min-height: 580px; background: radial-gradient(circle at 50% 50%, #0d131f 0%, #06090e 100%); border-radius: 8px; border: 1px solid #30363d; overflow: hidden; display: flex; user-select: none;">
    <!-- Graphical Operation Guide Overlay -->
    <div class="stella-help-overlay" style="position: absolute; top: 12px; left: 12px; background: rgba(22, 27, 34, 0.88); backdrop-filter: blur(6px); padding: 10px 14px; border-radius: 8px; border: 1px solid #30363d; color: #8b949e; font-size: 11px; z-index: 50; pointer-events: none; line-height: 1.6; box-shadow: 0 4px 12px rgba(0,0,0,0.3);">
        <div style="font-weight: bold; color: #58a6ff; margin-bottom: 4px; display: flex; align-items: center; gap: 6px;">$navStellaTitle</div>
        <div>$helpDrag</div>
        <div>$helpWheel</div>
        <div>$helpClick</div>
    </div>

    <!-- Time Axis HUD Indicator -->
    <div id="stellaTimeHud" style="position: absolute; bottom: 12px; left: 12px; background: rgba(22, 27, 34, 0.82); backdrop-filter: blur(4px); padding: 6px 12px; border-radius: 6px; border: 1px solid #30363d; color: #8b949e; font-size: 11px; z-index: 50; pointer-events: none; display: flex; align-items: center; gap: 8px;">
        <span>⏳ 時間軸 (Z):</span>
        <span style="color: #79c0ff;">◀ $timePastTxt</span>
        <span style="color: #30363d;">──────────</span>
        <span style="color: #58a6ff; font-weight: bold;">$timePresTxt ▶</span>
    </div>

    <svg id="stellaCanvas" style="width: 100%; height: 100%; cursor: grab;" viewBox="0 0 1000 800">
        <g id="stellaLinksGroup"></g>
        <g id="stellaNodesGroup"></g>
    </svg>

    <!-- Slide-in preview pane -->
    <div id="stellaSlidePane" class="stella-slidein-pane" style="position: absolute; top: 0; right: -380px; width: 360px; height: 100%; background: #161b22; border-left: 1px solid #30363d; padding: 20px; box-shadow: -4px 0 16px rgba(0,0,0,0.5); transition: right 0.3s ease; color: #c9d1d9; overflow-y: auto; z-index: 100; box-sizing: border-box;">
        <button onclick="closeStellaPane()" style="position: absolute; top: 12px; right: 12px; background: none; border: none; color: #8b949e; font-size: 18px; cursor: pointer;">✕</button>
        <h3 id="stellaPaneTitle" style="margin-top: 0; font-size: 16px; color: #58a6ff; word-break: break-all;">$previewTitle</h3>
        <div id="stellaPaneMeta" style="font-size: 12px; color: #8b949e; margin-bottom: 12px; display: flex; flex-wrap: wrap; gap: 8px; align-items: center;"></div>
        <p id="stellaPaneDesc" style="font-size: 13px; line-height: 1.5; color: #8b949e; background: #0d1117; padding: 10px; border-radius: 6px; border: 1px solid #21262d; margin-bottom: 12px;"></p>

        <!-- Connected Stars (Metadata Affinity) -->
        <div id="stellaConnectedSection" style="margin-top: 14px; border-top: 1px solid #21262d; padding-top: 12px;">
            <div style="font-size: 12px; font-weight: bold; color: #58a6ff; margin-bottom: 8px;">$connectedTitle</div>
            <div id="stellaConnectedList" style="display: flex; flex-direction: column; gap: 6px; font-size: 12px;"></div>
        </div>

        <div style="margin-top: 18px;">
            <a id="stellaPaneLink" href="#" style="display: inline-block; padding: 8px 16px; background: #1f6feb; color: #fff; text-decoration: none; border-radius: 6px; font-size: 12px; font-weight: bold;">📄 $openDocTxt</a>
        </div>
    </div>
</div>

<script>
(function() {
    var rawData = $indexJson;
    var rawItems = (rawData && rawData.Items) ? rawData.Items : [];

    var nodes = rawItems.map(function(item) {
        var rel = item.RelPath || item.relPath || "";
        var rawTags = item.Tags || item.tags || [];
        var safeTags = [];
        if (Array.isArray(rawTags)) {
            safeTags = rawTags;
        } else if (typeof rawTags === "string") {
            safeTags = rawTags.split(",").map(function(t) { return t.trim(); }).filter(Boolean);
        }

        var rawRelated = item.Related || item.related || [];
        var safeRelated = [];
        if (Array.isArray(rawRelated)) {
            safeRelated = rawRelated;
        } else if (typeof rawRelated === "string") {
            safeRelated = rawRelated.split(",").map(function(r) { return r.trim(); }).filter(Boolean);
        }

        var rawLinks = item.Links || item.links || [];
        var safeLinks = [];
        if (Array.isArray(rawLinks)) {
            safeLinks = rawLinks;
        } else if (typeof rawLinks === "string") {
            safeLinks = rawLinks.split(",").map(function(l) { return l.trim(); }).filter(Boolean);
        }

        return {
            relPath: rel,
            title: item.Title || item.title || "Untitled",
            description: item.Description || item.description || "",
            status: (item.Status || item.status || "active").toLowerCase(),
            tags: safeTags,
            domain: item.Domain || item.domain || "root",
            lastUpdated: item.LastUpdated || item.lastUpdated || "",
            related: safeRelated,
            links: safeLinks,
            x: item.X !== undefined ? item.X : 500,
            y: item.Y !== undefined ? item.Y : 400,
            z: item.Z !== undefined ? item.Z : 0,
            screenX: 500,
            screenY: 400,
            projZ: 0,
            scale: 1,
            el: null,
            circleEl: null,
            textEl: null
        };
    });

    var svg = document.getElementById("stellaCanvas");
    var gLinks = document.getElementById("stellaLinksGroup");
    var gNodes = document.getElementById("stellaNodesGroup");
    var pane = document.getElementById("stellaSlidePane");

    // 3D カメラ状態変数 (Z軸 = 時間軸)
    var rotX = 0.38;       // ピッチ角 (上下)
    var rotY = 0.45;       // ヨー角 (左右)
    var panX = 0, panY = 0; // 平行移動
    var zoom = 1.0;        // ズーム倍率
    var centerWorldX = 500, centerWorldY = 400;

    // キャンバス基準サイズ
    if (nodes.length > 0) {
        var sumX = 0, sumY = 0;
        nodes.forEach(function(n) { sumX += n.x; sumY += n.y; });
        centerWorldX = sumX / nodes.length;
        centerWorldY = sumY / nodes.length;
    }

    var selectedNode = null;
    var allEdges = [];
    var fov = 950;
    var camDist = 1100;

    // 3D 透視投影関数 (Perspective 3D Projection)
    function project3D(wx, wy, wz) {
        var x0 = wx - centerWorldX;
        var y0 = wy - centerWorldY;
        var z0 = wz;

        // 1. Yaw (Y軸回転: 左右)
        var cosY = Math.cos(rotY), sinY = Math.sin(rotY);
        var x1 = x0 * cosY + z0 * sinY;
        var z1 = -x0 * sinY + z0 * cosY;

        // 2. Pitch (X軸回転: 上下)
        var cosX = Math.cos(rotX), sinX = Math.sin(rotX);
        var y2 = y0 * cosX - z1 * sinX;
        var z2 = y0 * sinX + z1 * cosX;

        // 3. 透視投影 (Perspective Projection)
        var depth = camDist + z2;
        if (depth < 80) depth = 80;
        var k = (fov / depth) * zoom;

        return {
            x: 500 + panX + (x1 * k),
            y: 400 + panY + (y2 * k),
            z: z2,
            k: k
        };
    }

    // 3D 空間位置の全体更新
    function update3DPositions() {
        // 1. ノードの画面投影
        nodes.forEach(function(n) {
            var p = project3D(n.x, n.y, n.z);
            n.screenX = p.x;
            n.screenY = p.y;
            n.projZ = p.z;
            n.scale = p.k;

            if (n.el) {
                n.el.setAttribute("transform", "translate(" + p.x.toFixed(1) + "," + p.y.toFixed(1) + ")");
                var isHub = (Array.isArray(n.tags) && n.tags.length >= 4);
                var baseR = isHub ? 8 : 6;
                var currentR = Math.max(3, Math.min(18, baseR * Math.pow(p.k, 0.85)));
                n.circleEl.setAttribute("r", currentR.toFixed(1));

                var depthFade = Math.max(0.2, Math.min(1.0, 0.35 + (0.65 * (p.k / Math.max(0.1, zoom)))));
                n.circleEl.setAttribute("opacity", (selectedNode ? n.circleEl.getAttribute("opacity") : depthFade.toFixed(2)));

                if (n.textEl && !selectedNode) {
                    var textAlpha = (p.k < 0.7 && !isHub) ? "0.15" : depthFade.toFixed(2);
                    n.textEl.style.opacity = textAlpha;
                    var fontSize = Math.max(9, Math.min(14, 11 * p.k));
                    n.textEl.setAttribute("font-size", fontSize.toFixed(1) + "px");
                    n.textEl.setAttribute("x", (currentR + 5).toFixed(1));
                }
            }
        });

        // 2. 星座線の画面投影
        allEdges.forEach(function(e) {
            if (e.lineEl) {
                e.lineEl.setAttribute("x1", e.source.screenX.toFixed(1));
                e.lineEl.setAttribute("y1", e.source.screenY.toFixed(1));
                e.lineEl.setAttribute("x2", e.target.screenX.toFixed(1));
                e.lineEl.setAttribute("y2", e.target.screenY.toFixed(1));
            }
        });

        // 3. Z-Sorting (Painter's Algorithm: 奥にある星から順に DOM を再配置)
        var sortedNodes = nodes.slice().sort(function(a, b) { return a.projZ - b.projZ; });
        sortedNodes.forEach(function(n) {
            if (n.el && n.el.parentNode === gNodes) {
                gNodes.appendChild(n.el);
            }
        });
    }

    // 視点プリセット切り替え (Smooth Tweening Animation)
    var animId = null;
    function tweenCameraTo(targetRotX, targetRotY, targetPanX, targetPanY, targetZoom) {
        if (animId) cancelAnimationFrame(animId);
        var sRotX = rotX, sRotY = rotY;
        var sPanX = panX, sPanY = panY;
        var sZoom = zoom;
        var startTime = performance.now();
        var duration = 550;

        function step(now) {
            var progress = Math.min(1, (now - startTime) / duration);
            var ease = progress < 0.5 ? 4 * progress * progress * progress : 1 - Math.pow(-2 * progress + 2, 3) / 2;

            rotX = sRotX + (targetRotX - sRotX) * ease;
            rotY = sRotY + (targetRotY - sRotY) * ease;
            panX = sPanX + (targetPanX - sPanX) * ease;
            panY = sPanY + (targetPanY - sPanY) * ease;
            zoom = sZoom + (targetZoom - sZoom) * ease;

            update3DPositions();

            if (progress < 1) {
                animId = requestAnimationFrame(step);
            } else {
                animId = null;
            }
        }
        animId = requestAnimationFrame(step);
    }

    window.setStellaPreset = function(mode) {
        var buttons = document.querySelectorAll(".stella-preset-btn");
        buttons.forEach(function(b) {
            b.classList.toggle("active", b.dataset.preset === mode);
        });

        if (mode === "3d") {
            tweenCameraTo(0.38, 0.45, 0, 0, 1.0);
        } else if (mode === "top") {
            tweenCameraTo(0.0, 0.0, 0, 0, 1.0);
        } else if (mode === "timeline") {
            tweenCameraTo(0.0, 1.57079, 0, 0, 0.95);
        }
    };

    window.resetStellaView = function() {
        window.setStellaPreset("3d");
        applyFilter();
        closeStellaPane();
    };

    function renderCanvas() {
        gLinks.innerHTML = "";
        gNodes.innerHTML = "";
        allEdges = [];

        var nodeCount = nodes.length;
        for (var i = 0; i < nodeCount; i++) {
            for (var j = i + 1; j < nodeCount; j++) {
                var n1 = nodes[i];
                var n2 = nodes[j];

                var sharedTags = [];
                if (Array.isArray(n1.tags) && Array.isArray(n2.tags)) {
                    n1.tags.forEach(function(t) {
                        if (typeof t === "string" && t.trim() !== "" && n2.tags.indexOf(t) !== -1 && sharedTags.indexOf(t) === -1) {
                            sharedTags.push(t);
                        }
                    });
                }

                var isRelated = false;
                var r1 = n1.relPath.replace(/\\/g, '/').toLowerCase();
                var r2 = n2.relPath.replace(/\\/g, '/').toLowerCase();
                if (Array.isArray(n1.related)) {
                    n1.related.forEach(function(rel) {
                        if (typeof rel === "string" && (rel.toLowerCase() === r2 || rel.toLowerCase() === n2.relPath.toLowerCase())) { isRelated = true; }
                    });
                }
                if (Array.isArray(n2.related)) {
                    n2.related.forEach(function(rel) {
                        if (typeof rel === "string" && (rel.toLowerCase() === r1 || rel.toLowerCase() === n1.relPath.toLowerCase())) { isRelated = true; }
                    });
                }

                if (sharedTags.length > 0 || isRelated) {
                    allEdges.push({
                        source: n1,
                        target: n2,
                        sharedTags: sharedTags,
                        isRelated: isRelated,
                        weight: (isRelated ? 6 : 0) + (sharedTags.length * 2),
                        lineEl: null
                    });
                }
            }
        }

        // 次数制限 k-NN フィルタ (毛糸玉防止)
        var nodeEdgeCount = {};
        var backboneEdgeMap = {};
        var sortedEdges = allEdges.slice().sort(function(a, b) { return b.weight - a.weight; });

        sortedEdges.forEach(function(e) {
            var sKey = e.source.relPath;
            var tKey = e.target.relPath;
            var countS = nodeEdgeCount[sKey] || 0;
            var countT = nodeEdgeCount[tKey] || 0;

            if (e.isRelated || (countS < 4 && countT < 4)) {
                var edgeId = sKey < tKey ? sKey + '|' + tKey : tKey + '|' + sKey;
                backboneEdgeMap[edgeId] = true;
                nodeEdgeCount[sKey] = countS + 1;
                nodeEdgeCount[tKey] = countT + 1;
            }
        });

        // 星座線の DOM 生成
        allEdges.forEach(function(e) {
            var sKey = e.source.relPath;
            var tKey = e.target.relPath;
            var edgeId = sKey < tKey ? sKey + '|' + tKey : tKey + '|' + sKey;
            var isBackbone = !!backboneEdgeMap[edgeId];

            var line = document.createElementNS("http://www.w3.org/2000/svg", "line");
            var strokeColor = e.isRelated ? "rgba(138, 180, 248, 0.55)" : (e.sharedTags.length > 1 ? "rgba(88, 166, 255, 0.4)" : "rgba(88, 166, 255, 0.2)");
            var strokeWidth = e.isRelated ? "2.2" : (e.sharedTags.length > 1 ? "1.6" : "1.1");
            line.setAttribute("stroke", strokeColor);
            line.setAttribute("stroke-width", strokeWidth);
            if (!e.isRelated && e.sharedTags.length === 1) {
                line.setAttribute("stroke-dasharray", "4,3");
            }
            line.dataset.isBackbone = isBackbone ? "true" : "false";
            line.dataset.isRelated = e.isRelated ? "true" : "false";
            line.dataset.sharedCount = e.sharedTags.length;

            if (!isBackbone) {
                line.style.display = "none";
            }

            e.lineEl = line;
            gLinks.appendChild(line);
        });

        // 星ノードの DOM 生成
        nodes.forEach(function(n) {
            var g = document.createElementNS("http://www.w3.org/2000/svg", "g");
            g.setAttribute("class", "stella-node");
            g.dataset.relpath = n.relPath;
            var isHub = (n.tags && n.tags.length >= 4);
            g.dataset.isHub = isHub ? "true" : "false";
            g.style.cursor = "pointer";

            var dotColor = (n.status === 'stable' || n.status === 'active') ? '#58a6ff' : (n.status === 'draft' ? '#d29922' : '#f85149');

            var circle = document.createElementNS("http://www.w3.org/2000/svg", "circle");
            circle.setAttribute("r", isHub ? "8" : "6");
            circle.setAttribute("fill", dotColor);
            circle.setAttribute("opacity", "0.85");
            circle.setAttribute("class", "stella-dot");
            circle.style.transition = "fill 0.2s ease, r 0.2s ease";

            var text = document.createElementNS("http://www.w3.org/2000/svg", "text");
            text.setAttribute("x", (isHub ? 13 : 11).toString());
            text.setAttribute("y", "4");
            text.setAttribute("fill", "#c9d1d9");
            text.setAttribute("font-size", "11px");
            text.setAttribute("font-weight", isHub ? "bold" : "500");
            text.setAttribute("opacity", "0.85");
            text.textContent = n.title;

            g.appendChild(circle);
            g.appendChild(text);

            n.el = g;
            n.circleEl = circle;
            n.textEl = text;

            g.addEventListener("click", function(e) {
                e.stopPropagation();
                flyToNode(n);
                highlightConstellation(n);
                openStellaPane(n);
            });

            gNodes.appendChild(g);
        });

        update3DPositions();
    }

    // マウスドラッグによる 3D Orbit 回転 & パン
    var isDragging = false;
    var isPanMode = false;
    var lastMouseX = 0, lastMouseY = 0;

    svg.addEventListener("mousedown", function(e) {
        if (e.button !== 0 && e.button !== 2) return;
        isDragging = true;
        isPanMode = (e.shiftKey || e.button === 2);
        lastMouseX = e.clientX;
        lastMouseY = e.clientY;
        svg.style.cursor = isPanMode ? "move" : "grabbing";
        e.preventDefault();
    });

    window.addEventListener("mousemove", function(e) {
        if (!isDragging) return;
        var dx = e.clientX - lastMouseX;
        var dy = e.clientY - lastMouseY;
        lastMouseX = e.clientX;
        lastMouseY = e.clientY;

        if (isPanMode) {
            panX += dx;
            panY += dy;
        } else {
            rotY += dx * 0.006;
            rotX -= dy * 0.006;
            // ピッチ角をクランプ (-85度〜+85度)
            rotX = Math.max(-1.48, Math.min(1.48, rotX));
        }

        update3DPositions();
    });

    window.addEventListener("mouseup", function() {
        if (isDragging) {
            isDragging = false;
            svg.style.cursor = "grab";
        }
    });

    svg.addEventListener("contextmenu", function(e) {
        e.preventDefault();
    });

    // マウスホイールによるズーム
    svg.addEventListener("wheel", function(e) {
        e.preventDefault();
        var factor = e.deltaY < 0 ? 1.12 : 0.89;
        zoom = Math.max(0.35, Math.min(3.2, zoom * factor));
        update3DPositions();
    }, { passive: false });

    function flyToNode(n) {
        selectedNode = n;
        // 選択ノードが中央に来るように panX, panY を計算
        var p = project3D(n.x, n.y, n.z);
        var targetPanX = panX + (500 - p.x);
        var targetPanY = panY + (400 - p.y);
        tweenCameraTo(rotX, rotY, targetPanX, targetPanY, 1.25);
    }

    window.flyToRelPath = function(rel) {
        var target = nodes.filter(function(n) { return n.relPath === rel; })[0];
        if (target) {
            flyToNode(target);
            highlightConstellation(target);
            openStellaPane(target);
        }
    };

    // 星座発光 (Constellation Lighting)
    function highlightConstellation(centerNode) {
        var connectedRels = {};
        connectedRels[centerNode.relPath] = true;

        allEdges.forEach(function(e) {
            if (e.source.relPath === centerNode.relPath) { connectedRels[e.target.relPath] = true; }
            if (e.target.relPath === centerNode.relPath) { connectedRels[e.source.relPath] = true; }
        });

        // ノード発光
        nodes.forEach(function(n) {
            if (n.relPath === centerNode.relPath) {
                n.circleEl.setAttribute("fill", "#58a6ff");
                n.circleEl.setAttribute("opacity", "1");
                if (n.textEl) { n.textEl.style.opacity = "1"; n.textEl.setAttribute("font-weight", "bold"); }
            } else if (connectedRels[n.relPath]) {
                n.circleEl.setAttribute("fill", "#79c0ff");
                n.circleEl.setAttribute("opacity", "1");
                if (n.textEl) { n.textEl.style.opacity = "0.95"; }
            } else {
                n.circleEl.setAttribute("opacity", "0.18");
                if (n.textEl) { n.textEl.style.opacity = "0.12"; }
            }
        });

        // 星座線発光
        allEdges.forEach(function(e) {
            if (e.lineEl) {
                var s = e.source.relPath;
                var t = e.target.relPath;
                var isConn = (s === centerNode.relPath || t === centerNode.relPath);

                if (isConn) {
                    e.lineEl.style.display = "block";
                    e.lineEl.setAttribute("stroke", "rgba(88, 166, 255, 0.95)");
                    e.lineEl.setAttribute("stroke-width", "2.8");
                    e.lineEl.style.filter = "drop-shadow(0 0 5px #388bfd)";
                } else {
                    var isBackbone = e.lineEl.dataset.isBackbone === "true";
                    if (isBackbone) {
                        e.lineEl.style.display = "block";
                        e.lineEl.setAttribute("stroke", "rgba(88, 166, 255, 0.08)");
                        e.lineEl.setAttribute("stroke-width", "1");
                        e.lineEl.style.filter = "none";
                    } else {
                        e.lineEl.style.display = "none";
                    }
                }
            }
        });
    }

    function openStellaPane(n) {
        document.getElementById("stellaPaneTitle").textContent = n.title;
        var statusBadge = "<span style='padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: bold; background: " + (n.status === 'active' || n.status === 'stable' ? '#238636' : n.status === 'draft' ? '#d29922' : '#f85149') + "; color: #fff;'>" + n.status.toUpperCase() + "</span>";
        var domainBadge = "<span style='padding: 2px 8px; border-radius: 10px; font-size: 11px; background: #21262d; color: #8b949e; border: 1px solid #30363d;'>📁 " + (n.domain || "root") + "</span>";
        var dateStr = n.lastUpdated ? n.lastUpdated.substring(0, 10) : "";
        document.getElementById("stellaPaneMeta").innerHTML = statusBadge + " " + domainBadge + " <span>📅 " + dateStr + "</span>";
        document.getElementById("stellaPaneDesc").textContent = n.description || "概要はありません。";
        document.getElementById("stellaPaneLink").href = "/" + encodeURIComponent(n.relPath.replace(/\\/g, '/')).replace(/%2F/g, '/');

        var connectedListEl = document.getElementById("stellaConnectedList");
        var connectedItems = [];
        allEdges.forEach(function(e) {
            var other = null;
            if (e.source.relPath === n.relPath) other = e.target;
            else if (e.target.relPath === n.relPath) other = e.source;

            if (other) {
                var reason = e.isRelated ? "🔗 関連指定" : ("🏷️ " + e.sharedTags.join(", "));
                connectedItems.push("<div onclick=\"flyToRelPath('" + other.relPath.replace(/'/g, "\\'") + "')\" style='cursor: pointer; padding: 6px 10px; background: #0d1117; border-radius: 6px; border: 1px solid #21262d; display: flex; justify-content: space-between; align-items: center; transition: all 0.2s;' onmouseover=\"this.style.borderColor='#58a6ff'\" onmouseout=\"this.style.borderColor='#21262d'\"><span style='color: #c9d1d9; font-weight: 500;'>🌟 " + other.title + "</span><span style='color: #8b949e; font-size: 11px;'>" + reason + "</span></div>");
            }
        });

        if (connectedItems.length > 0) {
            connectedListEl.innerHTML = connectedItems.join("");
            document.getElementById("stellaConnectedSection").style.display = "block";
        } else {
            connectedListEl.innerHTML = "<span style='color: #6e7681; font-size: 11px;'>関連する星はありません</span>";
        }

        pane.style.right = "0px";
    }

    window.closeStellaPane = function() {
        pane.style.right = "-380px";
        if (selectedNode) {
            selectedNode = null;
            applyFilter();
        }
    };

    function applyFilter() {
        var query = (document.getElementById("stellaSearchInput").value || "").toLowerCase().trim();
        var statusVal = document.getElementById("stellaStatusSelect").value;
        var tagVal = document.getElementById("stellaTagSelect").value;

        var matchingRels = {};
        nodes.forEach(function(n) {
            var matchQ = !query || (n.title.toLowerCase().indexOf(query) !== -1 || n.description.toLowerCase().indexOf(query) !== -1);
            var matchS = statusVal === "all" || n.status === statusVal || (statusVal === "active" && n.status === "stable");
            var matchT = tagVal === "all" || (Array.isArray(n.tags) && n.tags.indexOf(tagVal) !== -1);

            if (matchQ && matchS && matchT && (query || statusVal !== "all" || tagVal !== "all")) {
                matchingRels[n.relPath] = true;
            }
        });

        var isActiveFilter = (query !== "" || statusVal !== "all" || tagVal !== "all");

        nodes.forEach(function(n) {
            var isHub = (Array.isArray(n.tags) && n.tags.length >= 4);
            if (!isActiveFilter) {
                var dotColor = (n.status === 'stable' || n.status === 'active') ? '#58a6ff' : (n.status === 'draft' ? '#d29922' : '#f85149');
                n.circleEl.setAttribute("fill", dotColor);
            } else if (matchingRels[n.relPath]) {
                n.circleEl.setAttribute("fill", "#388bfd");
                n.circleEl.setAttribute("opacity", "1");
                if (n.textEl) n.textEl.style.opacity = "1";
            } else {
                n.circleEl.setAttribute("fill", "#21262d");
                n.circleEl.setAttribute("opacity", "0.2");
                if (n.textEl) n.textEl.style.opacity = "0.15";
            }
        });

        allEdges.forEach(function(e) {
            if (e.lineEl) {
                var s = e.source.relPath;
                var t = e.target.relPath;
                var isBackbone = e.lineEl.dataset.isBackbone === "true";
                e.lineEl.style.filter = "none";

                if (isActiveFilter) {
                    if (matchingRels[s] && matchingRels[t]) {
                        e.lineEl.style.display = "block";
                        e.lineEl.setAttribute("stroke", "rgba(56, 139, 253, 0.85)");
                        e.lineEl.setAttribute("stroke-width", "2.2");
                    } else {
                        e.lineEl.style.display = "none";
                    }
                } else {
                    if (isBackbone) {
                        e.lineEl.style.display = "block";
                        var isRelated = e.lineEl.dataset.isRelated === "true";
                        var sharedCount = parseInt(e.lineEl.dataset.sharedCount || "0", 10);
                        e.lineEl.setAttribute("stroke", isRelated ? "rgba(138, 180, 248, 0.55)" : (sharedCount > 1 ? "rgba(88, 166, 255, 0.4)" : "rgba(88, 166, 255, 0.2)"));
                        e.lineEl.setAttribute("stroke-width", isRelated ? "2.2" : (sharedCount > 1 ? "1.6" : "1.1"));
                    } else {
                        e.lineEl.style.display = "none";
                    }
                }
            }
        });

        update3DPositions();
    }

    document.getElementById("stellaSearchInput").addEventListener("input", applyFilter);
    document.getElementById("stellaStatusSelect").addEventListener("change", applyFilter);
    document.getElementById("stellaTagSelect").addEventListener("change", applyFilter);

    renderCanvas();
})();
</script>
"@
}
