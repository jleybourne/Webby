//
//  PageScripts.swift
//  Webby
//
//  JavaScript that Webby injects into pages. The legacy engine only offers
//  synchronous string evaluation, so every script returns a string (often JSON),
//  and the page talks back by loading `webby://` URLs in a hidden iframe.
//

import Foundation

enum PageScripts {

    static let bridgeScheme = "webby"

    /// Installed after every load. Routes popups and target=_blank links to new tabs,
    /// and adds TV-friendly focus styling.
    static let bootstrap = #"""
    (function(){
      if (window.__webbyInstalled) { return 'ok'; }
      window.__webbyInstalled = true;
      function send(cmd, value) {
        var f = document.createElement('iframe');
        f.style.display = 'none';
        f.src = 'webby://' + cmd + '?v=' + encodeURIComponent(value || '');
        (document.body || document.documentElement).appendChild(f);
        setTimeout(function(){ if (f.parentNode) { f.parentNode.removeChild(f); } }, 50);
      }
      window.__webbySend = send;
      window.open = function(u) {
        if (u) { var a = document.createElement('a'); a.href = u; send('open', a.href); }
        return null;
      };
      document.addEventListener('click', function(e) {
        var t = e.target;
        var a = t && t.closest ? t.closest('a[target]') : null;
        if (a && a.href && a.target !== '_self' && a.target !== '_parent' && a.target !== '_top' &&
            a.href.indexOf('javascript:') !== 0) {
          e.preventDefault();
          send('open', a.href);
        }
      }, true);
      var style = document.createElement('style');
      style.textContent = '.__webby-focus{outline:4px solid rgba(10,132,255,.9)!important;outline-offset:2px!important;border-radius:4px}';
      (document.head || document.documentElement).appendChild(style);
      return 'ok';
    })();
    """#

    /// "documentWidth,scrollX,scrollY" in CSS pixels, used to map screen points into the page.
    static let layoutMetrics = "document.documentElement.scrollWidth + ',' + window.scrollX + ',' + window.scrollY"

    /// Returns "1" when the element under (x, y) is interactive.
    static func hoverTest(x: Double, y: Double) -> String {
        """
        (function(x,y){
          var e = document.elementFromPoint(x,y);
          if (!e) { return '0'; }
          if (e.closest && e.closest('a[href],button,input,select,textarea,label,summary,[onclick],[role=button],[role=link],[role=tab],[role=menuitem],[contenteditable=true],[tabindex]')) { return '1'; }
          try { if (window.getComputedStyle(e).cursor === 'pointer') { return '1'; } } catch (err) {}
          return '0';
        })(\(x),\(y));
        """
    }

    /// Simulates a full mouse click at (x, y). Returns JSON describing what was hit so
    /// native code can present a keyboard or picker for form controls.
    static func click(x: Double, y: Double) -> String {
        """
        (function(x,y){
          // A sign-in form: the clicked field is its only visible password field, or the
          // text field just before it. Returns the username (may be null) and password inputs.
          function __webbyLoginFields(field) {
            function visible(el) { return el.offsetParent !== null && !el.disabled && !el.readOnly; }
            var scope = field.form || document;
            var inputs = Array.prototype.filter.call(scope.querySelectorAll('input'), visible);
            var passwords = inputs.filter(function(el) { return (el.type || '').toLowerCase() === 'password'; });
            if (passwords.length !== 1) { return null; }
            var pass = passwords[0];
            var user = null;
            var userTypes = ['text','email','tel',''];
            for (var i = inputs.indexOf(pass) - 1; i >= 0; i--) {
              if (userTypes.indexOf((inputs[i].getAttribute('type') || '').toLowerCase()) >= 0) { user = inputs[i]; break; }
            }
            if (field !== pass && field !== user) { return null; }
            return {user: user, pass: pass};
          }
          var e = document.elementFromPoint(x,y);
          if (!e) { return JSON.stringify({kind:'none'}); }
          var textTypes = ['text','search','email','url','tel','password','number',''];
          var field = e.closest ? e.closest('input,textarea,select,[contenteditable=true]') : null;
          if (field) {
            var tag = field.tagName.toLowerCase();
            var type = (field.getAttribute('type') || '').toLowerCase();
            if (tag === 'select') {
              window.__webbyFocused = field;
              var opts = [];
              for (var i = 0; i < field.options.length; i++) { opts.push(field.options[i].text); }
              return JSON.stringify({kind:'select', options:opts, selected:field.selectedIndex});
            }
            if (tag === 'input' && textTypes.indexOf(type) >= 0) {
              var login = __webbyLoginFields(field);
              if (login) {
                window.__webbyLogin = login;
                return JSON.stringify({kind:'login', username: login.user ? login.user.value : null,
                                       newPassword: (login.pass.getAttribute('autocomplete') || '') === 'new-password'});
              }
            }
            if (tag === 'textarea' || field.isContentEditable || (tag === 'input' && textTypes.indexOf(type) >= 0)) {
              window.__webbyFocused = field;
              try { field.focus(); } catch (err) {}
              var label = field.getAttribute('aria-label') || field.getAttribute('placeholder') || field.getAttribute('name') || field.getAttribute('title') || '';
              if (!label && field.id) { var l = document.querySelector('label[for="' + field.id + '"]'); if (l) { label = l.innerText; } }
              var value = field.isContentEditable ? field.innerText : field.value;
              return JSON.stringify({kind:'text', value:value || '', inputType: field.isContentEditable ? 'text' : (tag === 'textarea' ? 'textarea' : type || 'text'), label:label || '', hasForm: !!field.form, autocomplete: (field.getAttribute('autocomplete') || '').toLowerCase()});
            }
          }
          var opts = {bubbles:true, cancelable:true, view:window, clientX:x, clientY:y, button:0};
          try {
            if (window.PointerEvent) {
              e.dispatchEvent(new PointerEvent('pointerover', opts));
              e.dispatchEvent(new PointerEvent('pointerdown', opts));
            }
            e.dispatchEvent(new MouseEvent('mouseover', opts));
            e.dispatchEvent(new MouseEvent('mousedown', opts));
            if (e.focus) { e.focus(); }
            if (window.PointerEvent) { e.dispatchEvent(new PointerEvent('pointerup', opts)); }
            e.dispatchEvent(new MouseEvent('mouseup', opts));
          } catch (err) {}
          if (e.click) { e.click(); } else { e.dispatchEvent(new MouseEvent('click', opts)); }
          if (field && field.tagName.toLowerCase() === 'input') { return JSON.stringify({kind:'toggle'}); }
          return JSON.stringify({kind:'click'});
        })(\(x),\(y));
        """
    }

    /// Writes text into the field that was last clicked and fires the events frameworks listen for.
    static func setFocusedValue(_ value: String, submit: Bool) -> String {
        """
        (function(v, submit){
          var f = window.__webbyFocused;
          if (!f) { return '0'; }
          if (f.isContentEditable) { f.innerText = v; }
          else {
            var proto = f.tagName.toLowerCase() === 'textarea' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
            var setter = Object.getOwnPropertyDescriptor(proto, 'value');
            if (setter && setter.set) { setter.set.call(f, v); } else { f.value = v; }
          }
          f.dispatchEvent(new Event('input', {bubbles:true}));
          f.dispatchEvent(new Event('change', {bubbles:true}));
          if (submit) {
            var kd = {bubbles:true, cancelable:true, key:'Enter', code:'Enter', keyCode:13, which:13};
            var proceed = f.dispatchEvent(new KeyboardEvent('keydown', kd));
            f.dispatchEvent(new KeyboardEvent('keypress', kd));
            f.dispatchEvent(new KeyboardEvent('keyup', kd));
            if (proceed && f.form) {
              if (f.form.requestSubmit) { f.form.requestSubmit(); } else { f.form.submit(); }
            }
          }
          return '1';
        })(\(jsString(value)), \(submit ? "true" : "false"));
        """
    }

    /// Fills the sign-in form found by `click`, then optionally submits it.
    static func setLogin(username: String?, password: String, submit: Bool) -> String {
        """
        (function(u, p, submit){
          var login = window.__webbyLogin;
          if (!login) { return '0'; }
          function set(f, v) {
            var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
            if (setter && setter.set) { setter.set.call(f, v); } else { f.value = v; }
            f.dispatchEvent(new Event('input', {bubbles:true}));
            f.dispatchEvent(new Event('change', {bubbles:true}));
          }
          if (login.user && u !== null) { set(login.user, u); }
          set(login.pass, p);
          if (submit) {
            var f = login.pass;
            var kd = {bubbles:true, cancelable:true, key:'Enter', code:'Enter', keyCode:13, which:13};
            var proceed = f.dispatchEvent(new KeyboardEvent('keydown', kd));
            f.dispatchEvent(new KeyboardEvent('keypress', kd));
            f.dispatchEvent(new KeyboardEvent('keyup', kd));
            if (proceed && f.form) {
              if (f.form.requestSubmit) { f.form.requestSubmit(); } else { f.form.submit(); }
            }
          }
          return '1';
        })(\(username.map(jsString) ?? "null"), \(jsString(password)), \(submit ? "true" : "false"));
        """
    }

    /// Dark Pages: inverts light pages (and inverts media back) so they read light-on-dark.
    /// Pages that are already dark are left alone.
    static func darkPages(_ enabled: Bool) -> String {
        """
        (function(on){
          var id = '__webby-dark', el = document.getElementById(id);
          if (!on) { if (el) { el.parentNode.removeChild(el); } return '0'; }
          if (el) { return '1'; }
          function lum(c) {
            var m = (c || '').match(/[\\d.]+/g);
            if (!m || m.length < 3 || (m.length > 3 && parseFloat(m[3]) === 0)) { return null; }
            return (0.299 * m[0] + 0.587 * m[1] + 0.114 * m[2]) / 255;
          }
          var bg = document.body ? lum(getComputedStyle(document.body).backgroundColor) : null;
          if (bg === null) { bg = lum(getComputedStyle(document.documentElement).backgroundColor); }
          if (bg !== null && bg < 0.4) { return 'dark'; }
          var s = document.createElement('style');
          s.id = id;
          s.textContent = 'html{filter:invert(1) hue-rotate(180deg)!important;background:#fff!important}' +
            'img,video,picture,canvas,iframe,embed,object,[style*="background-image"],mark.__webby-find{filter:invert(1) hue-rotate(180deg)!important}';
          (document.head || document.documentElement).appendChild(s);
          return '1';
        })(\(enabled ? "true" : "false"));
        """
    }

    /// Highlights every match of `query` on the page and scrolls to the first. Returns the count.
    static func find(_ query: String) -> String {
        """
        (function(q){
          \(findClearBody)
          q = q.toLowerCase();
          if (!q) { return '0'; }
          if (!document.getElementById('__webby-find-style')) {
            var st = document.createElement('style');
            st.id = '__webby-find-style';
            st.textContent = 'mark.__webby-find{background:#ffd60a!important;color:#000!important;border-radius:3px}' +
              'mark.__webby-find.__webby-current{background:#ff9f0a!important;outline:4px solid #ff9f0a}';
            (document.head || document.documentElement).appendChild(st);
          }
          // Room below the content, so the last matches can scroll clear of the find bar.
          document.documentElement.style.paddingBottom = '45vh';
          var skip = {SCRIPT:1, STYLE:1, NOSCRIPT:1, TEXTAREA:1, INPUT:1, SELECT:1};
          var walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT, {
            acceptNode: function(n) {
              var p = n.parentNode;
              if (!p || skip[p.nodeName] || !n.nodeValue || n.nodeValue.toLowerCase().indexOf(q) < 0) { return NodeFilter.FILTER_REJECT; }
              return p.offsetParent !== null || p === document.body ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
            }
          });
          var nodes = [], n;
          while ((n = walker.nextNode())) { nodes.push(n); }
          var marks = [];
          for (var i = 0; i < nodes.length && marks.length < 500; i++) {
            var node = nodes[i];
            var idx;
            while (node && (idx = node.nodeValue.toLowerCase().indexOf(q)) >= 0 && marks.length < 500) {
              var match = node.splitText(idx);
              node = match.splitText(q.length);
              var mark = document.createElement('mark');
              mark.className = '__webby-find';
              match.parentNode.replaceChild(mark, match);
              mark.appendChild(match);
              marks.push(mark);
            }
          }
          window.__webbyFind = {marks: marks, index: -1};
          return String(marks.length);
        })(\(jsString(query)));
        """
    }

    /// Moves to the next (1) or previous (-1) match and scrolls it into view. Returns "current/total".
    static func findStep(_ delta: Int) -> String {
        """
        (function(d){
          var f = window.__webbyFind;
          if (!f || !f.marks.length) { return '0/0'; }
          if (f.index >= 0) { f.marks[f.index].className = '__webby-find'; }
          f.index = (f.index + d + f.marks.length) % f.marks.length;
          var m = f.marks[f.index];
          m.className = '__webby-find __webby-current';
          m.scrollIntoView({block: 'center', inline: 'center'});
          return (f.index + 1) + '/' + f.marks.length;
        })(\(delta));
        """
    }

    static let findClear = "(function(){ \(findClearBody) return '1'; })();"

    private static let findClearBody = """
          var old = document.querySelectorAll('mark.__webby-find');
          for (var oi = 0; oi < old.length; oi++) {
            var om = old[oi], parent = om.parentNode;
            while (om.firstChild) { parent.insertBefore(om.firstChild, om); }
            parent.removeChild(om);
            parent.normalize();
          }
          window.__webbyFind = null;
          document.documentElement.style.paddingBottom = '';
    """

    static func selectOption(_ index: Int) -> String {
        """
        (function(i){
          var f = window.__webbyFocused;
          if (!f || f.tagName.toLowerCase() !== 'select') { return '0'; }
          f.selectedIndex = i;
          f.dispatchEvent(new Event('input', {bubbles:true}));
          f.dispatchEvent(new Event('change', {bubbles:true}));
          return '1';
        })(\(index));
        """
    }

    static func setZoom(_ zoom: Double) -> String {
        "(function(){ document.documentElement.style.zoom = '\(zoom)'; return '1'; })();"
    }

    /// Collects playable <video>/<source> URLs (blob: streams can't be handed to AVPlayer).
    static let findVideos = #"""
    (function(){
      var out = [];
      function add(u){ if (u && u.indexOf('blob:') !== 0 && out.indexOf(u) < 0) { out.push(u); } }
      var vids = document.querySelectorAll('video');
      for (var i = 0; i < vids.length; i++) {
        var v = vids[i];
        add(v.currentSrc || v.src);
        var srcs = v.querySelectorAll('source');
        for (var j = 0; j < srcs.length; j++) { add(srcs[j].src); }
        try { v.pause(); } catch (e) {}
      }
      var metas = document.querySelectorAll('meta[property="og:video"],meta[property="og:video:url"],meta[property="og:video:secure_url"]');
      for (var k = 0; k < metas.length; k++) {
        var c = metas[k].content || '';
        if (/\.(mp4|m4v|mov|m3u8)(\?|$)/i.test(c)) { add(c); }
      }
      return JSON.stringify(out);
    })();
    """#

    static let pageInfo = #"""
    (function(){ return JSON.stringify({title: document.title || '', href: location.href}); })();
    """#

    /// A lightweight "readability" pass: picks the densest text container and returns clean HTML.
    static let extractArticle = #"""
    (function(){
      var candidates = document.querySelectorAll('article, main, [role=main], .post, .entry-content, .article-body, #content, .content, body');
      var best = null, bestScore = 0;
      for (var i = 0; i < candidates.length; i++) {
        var c = candidates[i];
        var ps = c.querySelectorAll('p');
        var score = 0;
        for (var j = 0; j < ps.length; j++) { var len = (ps[j].innerText || '').trim().length; if (len > 40) { score += len; } }
        if (c.tagName.toLowerCase() === 'article') { score *= 1.3; }
        if (score > bestScore) { bestScore = score; best = c; }
      }
      if (!best || bestScore < 300) { return ''; }
      var clone = best.cloneNode(true);
      var junk = clone.querySelectorAll('script,style,noscript,iframe,form,nav,aside,footer,header,button,svg,.ad,.ads,.advert,.share,.social,.related,.comments,[aria-hidden=true]');
      for (var k = 0; k < junk.length; k++) { if (junk[k].parentNode) { junk[k].parentNode.removeChild(junk[k]); } }
      var all = clone.querySelectorAll('*');
      for (var m = 0; m < all.length; m++) {
        var el = all[m];
        var keep = {href:1, src:1, alt:1};
        for (var n = el.attributes.length - 1; n >= 0; n--) {
          var name = el.attributes[n].name;
          if (!keep[name]) { el.removeAttribute(name); }
        }
        if (el.tagName.toLowerCase() === 'img') {
          var lazy = el.getAttribute('data-src');
          if (lazy) { el.setAttribute('src', lazy); }
        }
      }
      var h1 = document.querySelector('h1');
      var byline = document.querySelector('[rel=author], .author, .byline, [itemprop=author]');
      return JSON.stringify({
        title: (h1 && h1.innerText.trim()) || document.title || '',
        byline: byline ? byline.innerText.trim().slice(0, 120) : '',
        site: location.hostname.replace(/^www\./, ''),
        html: clone.innerHTML
      });
    })();
    """#

    static func readerDocument(title: String, byline: String, site: String, body: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(htmlEscape(title))</title>
        <style>
          :root { color-scheme: dark; }
          body { margin: 0; background: #121214; color: #e9e9ee; font: 34px/1.6 -apple-system, "SF Pro Text", "Helvetica Neue", sans-serif; }
          main { max-width: 1300px; margin: 0 auto; padding: 90px 80px 160px; }
          .site { color: #0a84ff; font-size: 26px; letter-spacing: .08em; text-transform: uppercase; font-weight: 600; }
          h1 { font-size: 64px; line-height: 1.15; margin: 18px 0 12px; font-weight: 700; }
          .byline { color: #9a9aa3; font-size: 26px; margin-bottom: 56px; }
          img, video, figure { max-width: 100%; height: auto; border-radius: 14px; }
          figure { margin: 40px 0; } figcaption { color: #9a9aa3; font-size: 24px; margin-top: 10px; }
          a { color: #64b5ff; text-decoration: none; }
          h2, h3 { line-height: 1.25; margin-top: 1.6em; }
          blockquote { border-left: 6px solid #0a84ff; margin: 1.2em 0; padding: .2em 1em; color: #c7c7cf; }
          pre, code { font-family: "SF Mono", Menlo, monospace; font-size: 26px; background: #1e1e22; border-radius: 8px; }
          pre { padding: 24px; overflow-x: auto; }
          table { border-collapse: collapse; } td, th { border: 1px solid #333; padding: 8px 14px; }
        </style></head>
        <body><main>
          <div class="site">\(htmlEscape(site))</div>
          <h1>\(htmlEscape(title))</h1>
          <div class="byline">\(htmlEscape(byline))</div>
          \(body)
        </main></body></html>
        """
    }

    // MARK: Helpers

    static func jsString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let array = String(data: data, encoding: .utf8) else { return "''" }
        // Strip the surrounding [ ] to leave a JSON (and therefore JS) string literal.
        return String(array.dropFirst().dropLast())
    }

    static func htmlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
