local M = {}

-- Your original HTML, with a tiny pre-boot snippet that reads:
--   #src=<base64url>&b64=1[&packs=logos,devicon][&theme=dark][&autorender=1]
-- and seeds localStorage so the page renders immediately.
function M.index_html()
	return [[
<!doctype html>
<html lang="en">

<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Mermaid Architecture Playground (textarea edition)</title>
    <style>
        /* Default = DARK theme */
        :root {
            --bg: #0b1020;
            --panel: #0f172a;
            --stroke: #1f2937;
            --fg: #e5e7eb;
            --muted: #9ca3af;
            --warn: #f59e0b;
            --danger: #ef4444;
            --field-bg: #0b1229;
            --field-border: #233052;
            --kbd-bg: #0b1229;
            --kbd-border: #233052;
        }

        html,
        body {
            height: 100%;
        }

        body {
            margin: 0;
            background: var(--bg);
            color: var(--fg);
            font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial;
        }

        header {
            padding: .9rem 1rem;
            display: flex;
            gap: .5rem;
            align-items: center;
            border-bottom: 1px solid var(--stroke);
            background: rgba(255, 255, 255, 0.02);
            position: sticky;
            top: 0;
            backdrop-filter: blur(6px);
        }

        header h1 {
            margin: 0;
            font-size: 1rem;
            letter-spacing: .2px;
        }

        .spacer {
            flex: 1;
        }

        .btn {
            background: #1d4ed8;
            color: white;
            border: none;
            padding: .55rem .9rem;
            border-radius: 10px;
            cursor: pointer;
            font-weight: 600;
        }

        .btn.secondary {
            background: #334155;
        }

        .btn.ghost {
            background: transparent;
            border: 1px solid var(--stroke);
            color: var(--fg);
        }

        .btn.ghost.active {
            border-color: #1d4ed8;
            box-shadow: 0 0 0 2px rgba(29, 78, 216, .25) inset;
        }

        .wrap {
            max-width: 1400px;
            margin: 0 auto;
            padding: 1rem;
        }

        .grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 1rem;
            transition: grid-template-columns .2s ease;
        }

        .grid.collapsed {
            grid-template-columns: 1fr;
        }

        .card {
            background: var(--panel);
            border: 1px solid var(--stroke);
            border-radius: 14px;
            overflow: hidden;
            box-shadow: 0 10px 30px rgba(0, 0, 0, .25);
        }

        .card h2 {
            font-size: .95rem;
            font-weight: 600;
            margin: 0;
            padding: .8rem 1rem;
            border-bottom: 1px solid var(--stroke);
            color: var(--muted);
        }

        .body {
            padding: .75rem;
        }

        /* Textarea editor */
        textarea,
        input[type="text"] {
            width: 100%;
            background: var(--field-bg);
            color: var(--fg);
            border: 1px solid var(--field-border);
            border-radius: 10px;
            padding: .75rem .85rem;
            font-size: .95rem;
            line-height: 1.45;
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
            caret-color: var(--fg);
        }

        textarea {
            min-height: 520px;
            resize: vertical;
        }

        .controls {
            display: flex;
            flex-wrap: wrap;
            gap: .5rem;
            align-items: center;
            margin-bottom: .5rem;
        }

        .controls input[type="text"] {
            flex: 1 1 320px;
            min-width: 220px;
        }

        textarea::placeholder,
        input::placeholder {
            color: var(--muted);
            opacity: .85;
        }

        .hint {
            font-size: .85rem;
            color: var(--muted);
            margin-top: .4rem;
        }

        /* Preview & zoom */
        #preview {
            padding: .5rem;
        }

        .toolbar {
            display: flex;
            gap: .4rem;
            align-items: center;
            padding: .5rem .5rem .0rem;
            flex-wrap: wrap;
        }

        .toolbar .sep {
            width: 1px;
            height: 28px;
            background: var(--stroke);
            margin: 0 .25rem;
        }

        #panzoom {
            position: relative;
            overflow: auto;
            border: 1px dashed var(--stroke);
            border-radius: 10px;
            background: rgba(255, 255, 255, 0.02);
            max-height: 70vh;
        }

        #previewHost {
            position: relative;
        }

        .mermaid svg {
            display: block;
        }

        code.kbd {
            background: var(--kbd-bg);
            border: 1px solid var(--kbd-border);
            padding: .15rem .4rem;
            border-radius: 6px;
            font-size: .85em;
            color: var(--fg);
        }

        @media (max-width: 980px) {
            .grid {
                grid-template-columns: 1fr;
            }
        }

        .hidden {
            display: none !important;
        }

        /* LIGHT theme overrides */
        body[data-theme="light"] {
            --bg: #f7fafc;
            --panel: #ffffff;
            --stroke: #e5e7eb;
            --fg: #0b1020;
            --muted: #4b5563;
            --field-bg: #ffffff;
            --field-border: #d1d5db;
            --kbd-bg: #f3f4f6;
            --kbd-border: #e5e7eb;
        }

        /* Error & status panels */
        #errors {
            background: rgba(239, 68, 68, 0.12);
            border: 1px solid rgba(239, 68, 68, 0.35);
            color: #fecaca;
            padding: .75rem .9rem;
            border-radius: 10px;
            font-size: .9rem;
            white-space: pre-wrap;
        }

        body[data-theme="light"] #errors {
            background: rgba(239, 68, 68, 0.08);
            color: #7f1d1d;
            border-color: #fecaca;
        }

        #status {
            font-size: .85rem;
            color: var(--muted);
        }
    </style>
</head>

<body>
    <!-- Pre-boot: read #src=&b64=1 etc. and seed localStorage so the page boots with your code -->
    <script>
      (function () {
        try {
          var h = (location.hash || '').replace(/^#/, '');
          var s = location.search.replace(/^\?/, '');
          var all = new URLSearchParams(s);
          var h2 = new URLSearchParams(h);
          h2.forEach(function (v, k) { if (!all.has(k)) all.set(k, v); });
          var src = all.get('src');
          var b64 = all.get('b64');
          var packs = all.get('packs') || '';
          var theme = all.get('theme');
          if (src) {
            var decoded;
            try {
              if (b64 === '1') {
                var s2 = src.replace(/-/g, '+').replace(/_/g, '/');
                while (s2.length % 4) s2 += '=';
                decoded = atob(s2);
              } else {
                decoded = decodeURIComponent(src);
              }
              var saved = {};
              try { saved = JSON.parse(localStorage.getItem('mermaidPlayground') || '{}'); } catch { }
              localStorage.setItem('mermaidPlayground', JSON.stringify(Object.assign({}, saved, { src: decoded, packs: packs, theme: theme })));
            } catch (e) {
              console.warn('Param decode failed', e);
            }
          }
        } catch (e) { console.warn(e); }
      })();
    </script>

    <header>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" aria-hidden="true">
            <path d="M4 7h16M4 12h16M4 17h16" stroke="#93c5fd" stroke-width="1.5" stroke-linecap="round" />
        </svg>
        <h1>Mermaid Architecture Playground</h1>
        <div class="spacer"></div>
        <button id="themeBtn" class="btn secondary" title="Toggle light/dark theme">Theme: Dark</button>
        <button id="toggleEditor" class="btn secondary" title="Hide/show the editor">Hide editor</button>
    </header>

    <div class="wrap">
        <div id="mainGrid" class="grid">
            <!-- EDITOR PANEL -->
            <div id="editorCard" class="card">
                <h2>Diagram source</h2>
                <div class="body">
                    <div class="controls">
                        <input id="packs" type="text"
                            placeholder="Icon packs (comma-separated): e.g. logos, simple-icons, https://.../icons.json" />
                        <button id="renderBtn" class="btn">Render</button>
                        <button id="saveBtn" class="btn secondary" title="Save to browser storage">Save</button>
                        <button id="exportSvgBtn" class="btn secondary" title="Export current preview as SVG">Export
                            SVG</button>
                        <button id="cleanIndentBtn" class="btn ghost" title="Trim common indentation">Clean
                            indent</button>
                    </div>
                    <textarea id="src" spellcheck="false"
                        placeholder="Write only the Mermaid diagram here (no ``` wrapper). Use packs like logos:google-cloud. Ctrl/Cmd+Enter = Render">architecture-beta
                        group proj(cloud)[GCP Project]
                        group net(cloud)[VPC] in proj
                        group dmz(cloud)[Public DMZ] in net
                        group appg(cloud)[App Tier] in net
                        group datag(cloud)[Data Tier] in net

                        service users(internet)[Users]
                        service lb(cloud)[HTTPS Load Balancer] in dmz
                        service cdn(cloud)[Cloud CDN] in dmz
                        service fe(disk)[Static Site] in dmz

                        service api(server)[Cloud Run API] in appg
                        service vpcx(server)[VPC Access] in appg

                        service sql(database)[Cloud SQL] in datag
                        service cache(server)[Memorystore] in datag
                        service bucket(disk)[Object Storage] in datag

                        users:R --> L:lb
                        lb:B --> T:cdn
                        cdn:R --> L:fe

                        lb:R --> L:api
                        api:R --> L:vpcx
                        vpcx:R -- L:sql
                        vpcx:R -- L:cache
                        api:B --> T:bucket</textarea>
                    <div id="errors" class="hidden"></div>
                    <div id="status"></div>
                    <p class="hint">Tips: Add icon packs by name (e.g. <code class="kbd">logos</code>) or full Iconify
                        <code class="kbd">icons.json</code> URLs. <code class="kbd">Ctrl/Cmd+Enter</code> to render.</p>
                </div>
            </div>

            <!-- PREVIEW PANEL -->
            <div class="card">
                <h2>Preview</h2>
                <div class="toolbar">
                    <span>Zoom:</span>
                    <button id="zoomOut" class="btn ghost" title="Zoom out">−</button>
                    <button id="zoomReset" class="btn ghost" title="Reset zoom">100%</button>
                    <button id="zoomIn" class="btn ghost" title="Zoom in">+</button>
                    <div class="sep"></div>
                    <button id="fitWidth" class="btn ghost" title="Fit to width">Fit width</button>
                    <button id="fitHeight" class="btn ghost" title="Fit to height">Fit height</button>
                </div>
                <div id="preview" class="body">
                    <div id="panzoom">
                        <div id="previewHost" class="mermaid"></div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script type="module">
        import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';

        const srcEl = document.getElementById('src');
        const packsEl = document.getElementById('packs');
        const renderBtn = document.getElementById('renderBtn');
        const saveBtn = document.getElementById('saveBtn');
        const exportSvgBtn = document.getElementById('exportSvgBtn');
        const cleanIndentBtn = document.getElementById('cleanIndentBtn');

        const toggleEditorBtn = document.getElementById('toggleEditor');
        const editorCard = document.getElementById('editorCard');
        const mainGrid = document.getElementById('mainGrid');
        const themeBtn = document.getElementById('themeBtn');
        const errorsEl = document.getElementById('errors');
        const statusEl = document.getElementById('status');

        const previewHost = document.getElementById('previewHost');
        const zoomOutBtn = document.getElementById('zoomOut');
        const zoomInBtn = document.getElementById('zoomIn');
        const zoomResetBtn = document.getElementById('zoomReset');
        const fitWidthBtn = document.getElementById('fitWidth');
        const fitHeightBtn = document.getElementById('fitHeight');
        const panzoom = document.getElementById('panzoom');

        let baseW = 0, baseH = 0; // intrinsic svg size
        let currentSVG = '';
        let zoom = 1;
        let fitMode = 'none'; // 'none' | 'width' | 'height'
        const loadedPacks = new Set();

        function tokens(value) {return value.split(',').map(s => s.trim()).filter(Boolean);}
        function showError(message) {errorsEl.textContent = typeof message === 'string' ? message : (message?.message || String(message)); errorsEl.classList.remove('hidden');}
        function clearError() {errorsEl.textContent = ''; errorsEl.classList.add('hidden');}

        function dedentBlock(text) {
            const lines = text.replace(/\r\n?/g, '\n').split('\n');
            const nonEmpty = lines.filter(l => l.trim().length);
            if (!nonEmpty.length) return text;
            const indents = nonEmpty.map(l => (l.match(/^\s*/)[0] || '').length);
            const minIndent = Math.min(...indents);
            if (minIndent === 0) return text;
            return lines.map(l => l.slice(Math.min(minIndent, l.length))).join('\n');
        }

        function detectPacksFromSource(src) {const re = /\b([a-z0-9-]+):[a-z0-9-]+\b/gi; const names = new Set(); let m; while ((m = re.exec(src))) names.add(m[1].toLowerCase()); return Array.from(names);}

        async function registerPack(nameOrUrl) {
            if (loadedPacks.has(nameOrUrl)) return;
            const isUrl = /^(https?:)?\/\//i.test(nameOrUrl);
            let name = nameOrUrl; let loader;
            if (isUrl) {
                loader = () => fetch(nameOrUrl).then(r => r.json()); try {name = new URL(nameOrUrl, location.href).pathname.split('/').filter(Boolean).slice(-2, -1)[0] || nameOrUrl;} catch { }
            } else {loader = () => fetch(`https://unpkg.com/@iconify-json/${nameOrUrl}@1/icons.json`).then(r => r.json());}
            try {await mermaid.registerIconPacks([{name, loader}]); loadedPacks.add(nameOrUrl);}
            catch (e) {console.warn('Icon pack failed:', nameOrUrl, e); showError(`Icon pack failed: ${nameOrUrl} — ${e?.message || e}`);}
        }
        async function ensurePacks(list) {for (const t of list) await registerPack(t);}

        function parseViewBox(svgEl) {const vb = svgEl.getAttribute('viewBox'); if (!vb) return null; const parts = vb.trim().split(/\s+/).map(Number); return parts.length === 4 ? {x: parts[0], y: parts[1], w: parts[2], h: parts[3]} : null;}

        function applyZoomToSVG() {
            const svg = previewHost.querySelector('svg'); if (!svg || !baseW || !baseH) return;
            svg.removeAttribute('style'); svg.removeAttribute('width'); svg.removeAttribute('height');
            svg.setAttribute('width', String(Math.max(1, Math.round(baseW * zoom))));
            svg.setAttribute('height', String(Math.max(1, Math.round(baseH * zoom))));
            zoomResetBtn.textContent = `${Math.round(zoom * 100)}%`;
        }
        function computeFitZoom() {
            if (!baseW || !baseH) return; const cw = panzoom.clientWidth || baseW; const ch = panzoom.clientHeight || baseH;
            if (fitMode === 'width') zoom = cw / baseW; else if (fitMode === 'height') zoom = ch / baseH;
            zoom = Math.min(8, Math.max(0.1, zoom)); applyZoomToSVG();
        }
        function setFitMode(mode) {
            fitMode = mode; try {const saved = JSON.parse(localStorage.getItem('mermaidPlayground') || '{}'); localStorage.setItem('mermaidPlayground', JSON.stringify({...saved, fitMode}));} catch { }
            fitWidthBtn.classList.toggle('active', fitMode === 'width'); fitHeightBtn.classList.toggle('active', fitMode === 'height');
            if (fitMode === 'none') applyZoomToSVG(); else computeFitZoom();
        }

        async function renderMain() {
            clearError(); const src = srcEl.value.trim();
            const userPacks = tokens(packsEl.value || ''); const autoPacks = detectPacksFromSource(src);
            const allPacks = Array.from(new Set([...userPacks, ...autoPacks])); statusEl.textContent = allPacks.length ? `Using icon packs: ${allPacks.join(', ')}` : '';
            await ensurePacks(allPacks);
            previewHost.innerHTML = '';
            try {
                const id = 'arch' + Math.random().toString(36).slice(2); const {svg} = await mermaid.render(id, src);
                currentSVG = svg; previewHost.innerHTML = svg; const svgEl = previewHost.querySelector('svg'); const vb = parseViewBox(svgEl);
                if (vb) {baseW = vb.w; baseH = vb.h;} else {baseW = Number(svgEl.getAttribute('width')) || 1200; baseH = Number(svgEl.getAttribute('height')) || 800;}
                if (fitMode === 'none') applyZoomToSVG(); else computeFitZoom();
            } catch (e) {showError(e);}
        }

        function saveState() {try {const saved = JSON.parse(localStorage.getItem('mermaidPlayground') || '{}'); localStorage.setItem('mermaidPlayground', JSON.stringify({...saved, src: srcEl.value, packs: packsEl.value, zoom, fitMode}));} catch { } }
        function downloadSvg(svg, name) {const blob = new Blob([svg], {type: 'image/svg+xml'}); const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 2000);}

        // Theme handling
        function applyTheme(theme) {
            try {const saved = JSON.parse(localStorage.getItem('mermaidPlayground') || '{}'); localStorage.setItem('mermaidPlayground', JSON.stringify({...saved, theme}));} catch { }
            document.body.setAttribute('data-theme', theme); themeBtn.textContent = `Theme: ${theme === 'dark' ? 'Dark' : 'Light'}`; const mTheme = theme === 'dark' ? 'dark' : 'default'; mermaid.initialize({startOnLoad: false, theme: mTheme, securityLevel: 'strict'});
        }
        function toggleTheme() {const current = document.body.getAttribute('data-theme') || 'dark'; const next = current === 'dark' ? 'light' : 'dark'; applyTheme(next); renderMain();}

        // Zoom controls
        function setZoom(next) {zoom = Math.min(8, Math.max(0.1, next)); try {const saved = JSON.parse(localStorage.getItem('mermaidPlayground') || '{}'); localStorage.setItem('mermaidPlayground', JSON.stringify({...saved, zoom}));} catch { } applyZoomToSVG();}
        zoomInBtn.addEventListener('click', () => {setFitMode('none'); setZoom(zoom * 1.2);});
        zoomOutBtn.addEventListener('click', () => {setFitMode('none'); setZoom(zoom / 1.2);});
        zoomResetBtn.addEventListener('click', () => {setFitMode('none'); setZoom(1);});
        fitWidthBtn.addEventListener('click', () => setFitMode(fitMode === 'width' ? 'none' : 'width'));
        fitHeightBtn.addEventListener('click', () => setFitMode(fitMode === 'height' ? 'none' : 'height'));

        // Ctrl/Cmd + wheel zoom
        panzoom.addEventListener('wheel', (e) => {if (e.ctrlKey || e.metaKey) {e.preventDefault(); const dir = e.deltaY > 0 ? -1 : 1; setFitMode('none'); setZoom(zoom * (dir > 0 ? 1.1 : 1 / 1.1));} }, {passive: false});
        // Drag to pan
        let isDragging = false, startX = 0, startY = 0, startScrollLeft = 0, startScrollTop = 0;
        panzoom.addEventListener('mousedown', (e) => {isDragging = true; panzoom.classList.add('dragging'); startX = e.clientX; startY = e.clientY; startScrollLeft = panzoom.scrollLeft; startScrollTop = panzoom.scrollTop;});
        window.addEventListener('mousemove', (e) => {if (!isDragging) return; panzoom.scrollLeft = startScrollLeft - (e.clientX - startX); panzoom.scrollTop = startScrollTop - (e.clientY - startY);});
        window.addEventListener('mouseup', () => {isDragging = false; panzoom.classList.remove('dragging');});

        // Resize responsiveness
        let resizeTimer; window.addEventListener('resize', () => {clearTimeout(resizeTimer); resizeTimer = setTimeout(() => {if (fitMode === 'none') applyZoomToSVG(); else computeFitZoom();}, 100);});

        // Buttons & keys
        renderBtn.addEventListener('click', renderMain);
        saveBtn.addEventListener('click', saveState);
        exportSvgBtn.addEventListener('click', async () => {try {const svgToSave = currentSVG || (await mermaid.render('tmp', srcEl.value)).svg; downloadSvg(svgToSave, 'diagram.svg');} catch (e) {showError(e);} });
        cleanIndentBtn.addEventListener('click', () => {srcEl.value = dedentBlock(srcEl.value);});
        document.addEventListener('keydown', (e) => {if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {e.preventDefault(); renderMain();} });

        // Editor collapse/expand
        function setEditorCollapsed(collapsed, rerender = true) {
            editorCard.classList.toggle('hidden', collapsed); mainGrid.classList.toggle('collapsed', collapsed);
            toggleEditorBtn.textContent = collapsed ? 'Show editor' : 'Hide editor';
            try {const saved = JSON.parse(localStorage.getItem('mermaidPlayground') || '{}'); localStorage.setItem('mermaidPlayground', JSON.stringify({...saved, editorCollapsed: collapsed}));} catch { }
            if (rerender) setTimeout(() => {if (fitMode === 'none') renderMain(); else computeFitZoom();}, 30);
        }
        toggleEditorBtn.addEventListener('click', () => {const nowHidden = !editorCard.classList.contains('hidden'); setEditorCollapsed(nowHidden, true);});

        // Boot
        (function boot() {
            let saved = {}; try {saved = JSON.parse(localStorage.getItem('mermaidPlayground') || '{}');} catch { }
            if (typeof saved.packs === 'string') packsEl.value = saved.packs;
            if (saved.zoom) zoom = saved.zoom; if (saved.fitMode) fitMode = saved.fitMode;
            applyTheme(saved.theme || 'dark');
            if (typeof saved.src === 'string' && saved.src.trim()) srcEl.value = saved.src;
            if (saved.editorCollapsed) setEditorCollapsed(!!saved.editorCollapsed, false);
            renderMain();
            setTimeout(() => {setFitMode(fitMode); if (fitMode === 'none') applyZoomToSVG();}, 40);
        })();
        themeBtn.addEventListener('click', toggleTheme);
    </script>

    <noscript>
        <p style="padding:1rem;color:#fff;background:#7f1d1d">This page requires JavaScript to render Mermaid diagrams.
        </p>
    </noscript>
</body>

</html>
  ]]
end

return M
