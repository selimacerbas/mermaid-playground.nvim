local html = [[
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mermaid Playground</title>
<style>
  :root { color-scheme: light dark; }
  html,body { height:100%; margin:0; }
  body { font-family: system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, "Helvetica Neue", Arial, "Noto Sans", "Apple Color Emoji", "Segoe UI Emoji"; }
  #wrap { height:100%; width:100%; display:flex; align-items:center; justify-content:center; overflow:auto; }
  #container { padding:16px; max-width:100%; }
  #error { white-space:pre-wrap; color:crimson; font-size:14px; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace; }
  svg { max-width:100%; height:auto; }
  .topbar {
    position: fixed; top: 8px; right: 12px; display: flex; gap: 8px;
    font: 12px/1 ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace;
    opacity: .75; background: rgba(127,127,127,.12); padding: 8px 10px; border-radius: 10px;
  }
  .btn { cursor:pointer; user-select:none; padding:4px 8px; border-radius:8px; border:1px solid rgba(127,127,127,.25); }
</style>
<script>
function getQuery() {
  const q = new URLSearchParams(location.search);
  return {
    theme: q.get("theme") || "dark",
    fit: q.get("fit") || "width",
    packs: (q.get("packs") || "").split(",").filter(Boolean),
  };
}
</script>
<!-- Mermaid (latest) -->
<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
<!-- Iconify for icon packs -->
<script src="https://cdn.jsdelivr.net/npm/@iconify/iconify@3/dist/iconify.min.js"></script>
<body>
<div class="topbar">
  <span id="status">ready</span>
  <span class="btn" onclick="reloadDiagram()">Reload</span>
  <span class="btn" onclick="fitMode('none')">Fit: none</span>
  <span class="btn" onclick="fitMode('width')">Fit: width</span>
  <span class="btn" onclick="fitMode('height')">Fit: height</span>
</div>
<div id="wrap"><div id="container"></div></div>

<script>
let CFG = getQuery();
function fitMode(mode) {
  CFG.fit = mode;
  render(currentText);
}

function setStatus(msg){ document.getElementById('status').textContent = msg; }

let currentText = "";

function applyFit(svgEl) {
  if (!svgEl) return;
  svgEl.style.width = "";
  svgEl.style.height = "";
  if (CFG.fit === "width") {
    svgEl.style.width = "100%";
    svgEl.style.height = "auto";
  } else if (CFG.fit === "height") {
    const h = window.innerHeight - 48;
    svgEl.style.height = h + "px";
    svgEl.style.width = "auto";
  }
}

async function render(text) {
  currentText = text;
  const container = document.getElementById('container');
  container.innerHTML = "";
  if (!text || !text.trim()) {
    container.innerHTML = '<div id="error">No mermaid source received.</div>';
    return;
  }
  try {
    mermaid.initialize({
      startOnLoad: false,
      theme: CFG.theme === "dark" ? "dark" : "default",
      securityLevel: "loose",
      flowchart: { useMaxWidth: true }
    });
    const { svg } = await mermaid.render('mp_diagram', text);
    container.innerHTML = svg;
    applyFit(container.querySelector('svg'));
    setStatus('rendered ' + new Date().toLocaleTimeString());
  } catch (e) {
    container.innerHTML = '<div id="error">' + (e?.stack || e) + '</div>';
    setStatus('error');
  }
}

async function fetchText() {
  const ts = Date.now();
  const res = await fetch("diagram.mmd?ts=" + ts);
  if (!res.ok) throw new Error("Failed to load diagram.mmd");
  return await res.text();
}

async function reloadDiagram() {
  try {
    setStatus('loading...');
    const text = await fetchText();
    render(text);
  } catch (e) {
    document.getElementById('container').innerHTML =
      '<div id="error">Load error:\n' + (e?.stack || e) + '</div>';
    setStatus('error');
  }
}

window.addEventListener('resize', () => render(currentText));
window.addEventListener('load', reloadDiagram);
</script>
</body>
</html>
]]

return html
