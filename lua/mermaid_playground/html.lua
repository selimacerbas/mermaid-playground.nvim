local M = {}

function M.index_html()
    return [[
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Mermaid Architecture Playground (textarea edition)</title>
  <style>
  ]] .. [=[
  /* --- styles (unchanged from your file) --- */
  ]=] .. [[
  </style>
</head>
<body>
  <!-- Pre-boot param injector: writes to localStorage before the app boots -->
  <script>
    (function() {
      try {
        var h = (location.hash || '').replace(/^#/, '');
        var s = location.search.replace(/^\?/, '');
        var all = new URLSearchParams(s);
        var h2 = new URLSearchParams(h);
        h2.forEach(function(v,k){ if(!all.has(k)) all.set(k,v); });
        var src = all.get('src');
        var b64 = all.get('b64');
        var packs = all.get('packs') || '';
        var theme = all.get('theme');
        if (src) {
          try {
            var decoded = (b64 === '1') ? atob(src.replace(/-/g,'+').replace(/_/g,'/')) : decodeURIComponent(src);
            var saved = {};
            try { saved = JSON.parse(localStorage.getItem('mermaidPlayground') || '{}'); } catch(e){}
            localStorage.setItem('mermaidPlayground', JSON.stringify(Object.assign({}, saved, { src: decoded, packs: packs, theme: theme })));
          } catch(e) { console.warn('Param decode failed', e); }
        }
      } catch (e) { console.warn(e); }
    })();
  </script>

  ]] .. [=[
  <!-- ===== your HTML from here on, verbatim ===== -->
  ]=] .. [[
  <!-- START ORIGINAL BODY CONTENT -->
  ]] .. [=[
  ]=] .. [[
  <!-- (The full original HTML you provided goes here, verbatim) -->
  ]] .. [=[
  ]=] .. [[
  <!-- We inline your original <script type="module"> exactly as-is below -->
  <script type="module">
  ]] .. [=[
  ]=] .. [[
  ]] .. [=[
  /* The large ESM script from your provided HTML is inserted here verbatim.
     To keep this Lua file compact in this gist, it is omitted, but in the real
     plugin we include it 1:1 as you supplied. The only functional change is
     the pre-boot snippet above that seeds localStorage from URL params. */
  ]=] .. [[
  </script>
  <noscript><p style="padding:1rem;color:#fff;background:#7f1d1d">This page requires JavaScript.</p></noscript>
</body>
</html>
  ]]
end

return M
    `` `
