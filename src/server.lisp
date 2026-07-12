(in-package #:crafterbin/server)

;;; ============================================================
;;; HTTP Server
;;; ============================================================

(defvar *acceptor* nil "The Hunchentoot acceptor instance.")

;;; ============================================================
;;; Helpers
;;; ============================================================

(defun client-ip ()
  "Get the client IP, respecting X-Forwarded-For for reverse proxies."
  (or (hunchentoot:header-in* :x-forwarded-for)
      (hunchentoot:real-remote-addr)))

(defun client-ua ()
  "Get the client User-Agent."
  (or (hunchentoot:header-in* :user-agent) ""))

(defun file-url (entry)
  "Construct the public URL for a file entry."
  (let ((base (or (config-base-url *config*)
                  (format nil "http://~A:~A"
                          (config-host *config*)
                          (config-port *config*)))))
    (format nil "~A/~A" (string-right-trim "/" base) (entry-id entry))))

(defun format-size (bytes)
  "Format a byte count as a human-readable string."
  (cond ((>= bytes (* 1024 1024 1024))
         (format nil "~,1f GiB" (/ bytes (* 1024.0 1024 1024))))
        ((>= bytes (* 1024 1024))
         (format nil "~,1f MiB" (/ bytes (* 1024.0 1024))))
        ((>= bytes 1024)
         (format nil "~,1f KiB" (/ bytes 1024.0)))
        (t (format nil "~D B" bytes))))

;;; ============================================================
;;; Landing page
;;; ============================================================

(defun landing-page ()
  "Generate the plaintext landing page."
  (format nil "CRAFTERBIN
==========
Temporary file sharing service.

min_age  = ~D days
max_age  = ~D days
max_size = ~A

retention = min_age + (max_age - min_age) * pow((1 - file_size / max_size), 3)

Uploading files
---------------
Send HTTP POST requests with data encoded as multipart/form-data.

  field    | content     | remarks
  ---------+-------------+-----------------------------------------------
  file     | data        |
  url      | remote URL  | Mutually exclusive with \"file\".
  secret   | (ignored)   | If present, generates a longer, hard-to-guess URL.
  expires  | hours OR    | Sets maximum lifetime in hours OR expiration
           | ms epoch    | as milliseconds since UNIX epoch.

cURL examples
-------------
  Upload a file:
    curl -F'file=@yourfile.png' ~A

  Copy from URL:
    curl -F'url=http://example.com/image.jpg' ~A

  Secret URL:
    curl -F'file=@yourfile.png' -Fsecret= ~A

  Set expiry (24 hours):
    curl -F'file=@yourfile.png' -Fexpires=24 ~A

Managing files
--------------
  The X-Token response header contains a management token.
  Use -i with cURL to see it.

  Delete a file:
    curl -Ftoken=TOKEN -Fdelete= ~A/ID

  Update expiry:
    curl -Ftoken=TOKEN -Fexpires=72 ~A/ID

Powered by CrafterBin (Common Lisp)
"
          (floor (config-min-age *config*) (* 24 3600))
          (floor (config-max-age *config*) (* 24 3600))
          (format-size (config-max-size *config*))
          ;; URL placeholders
          (or (config-base-url *config*) "THIS_URL")
          (or (config-base-url *config*) "THIS_URL")
          (or (config-base-url *config*) "THIS_URL")
          (or (config-base-url *config*) "THIS_URL")
          (or (config-base-url *config*) "THIS_URL")
          (or (config-base-url *config*) "THIS_URL")))

(defun wants-html-p ()
  "Return T when the requesting client (a browser) prefers an HTML response."
  (let ((accept (hunchentoot:header-in* :accept)))
    (and accept (search "text/html" accept :test #'char-equal) t)))

(defun landing-page-html ()
  "Generate the styled HTML landing page for browsers."
  (let ((base (or (config-base-url *config*) "https://crafterbin.glennstack.dev")))
    (format nil "<!DOCTYPE html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<title>Crafterbin</title>
<style>
  :root {
    --bg: #292d3e;
    --panel: #232635;
    --panel-2: #2b2f44;
    --border: #3a3f58;
    --text: #eeffff;
    --muted: #a6accd;
    --accent: #c3e88d;
    --accent-2: #82aaff;
    --orange: #f78c6c;
    --code-bg: #1c1f26;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    background: var(--bg);
    color: var(--text);
    font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif;
    line-height: 1.6;
  }
  .wrap { max-width: 860px; margin: 0 auto; padding: 0 24px 80px; }
  header.hero {
    background:
      radial-gradient(900px 400px at 15% -10%, rgba(195,232,141,0.12), transparent 60%),
      radial-gradient(800px 400px at 85% -20%, rgba(130,170,255,0.16), transparent 55%),
      linear-gradient(180deg, #2f3450, var(--bg));
    border-bottom: 1px solid var(--border);
    padding: 64px 24px 56px;
    text-align: center;
  }
  .brand {
    display: inline-flex; align-items: center; gap: 14px;
    margin: 0 auto;
  }
  .logo {
    width: 52px; height: 52px; border-radius: 14px;
    display: grid; place-items: center;
    background: linear-gradient(135deg, var(--accent), var(--accent-2));
    color: #1c1f26; font-weight: 800; font-size: 26px;
    box-shadow: 0 10px 30px rgba(195,232,141,0.22);
  }
  h1 {
    margin: 0;
    font-size: clamp(2.4rem, 6vw, 3.4rem);
    letter-spacing: -0.02em;
    background: linear-gradient(90deg, var(--accent), var(--accent-2));
    -webkit-background-clip: text; background-clip: text; color: transparent;
  }
  .tagline { margin: 14px 0 0; color: var(--muted); font-size: 1.1rem; }
  .stats {
    display: flex; flex-wrap: wrap; gap: 12px; justify-content: center;
    margin-top: 28px;
  }
  .stat {
    background: var(--panel); border: 1px solid var(--border);
    border-radius: 12px; padding: 12px 18px; min-width: 120px;
  }
  .stat .k { display: block; font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.08em; color: var(--muted); }
  .stat .v { font-size: 1.15rem; font-weight: 700; color: var(--text); }
  section { margin-top: 44px; }
  h2 {
    font-size: 1.3rem; margin: 0 0 16px;
    padding-bottom: 8px; border-bottom: 1px solid var(--border);
  }
  p { color: var(--muted); }
  .formula {
    background: var(--panel-2); border: 1px solid var(--border);
    border-radius: 10px; padding: 14px 18px; color: var(--accent);
    font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 0.92rem; overflow-x: auto;
  }
  table { width: 100%; border-collapse: collapse; margin-top: 8px; font-size: 0.92rem; }
  th, td { text-align: left; padding: 10px 14px; border-bottom: 1px solid var(--border); }
  th { color: var(--accent); font-weight: 600; }
  td:first-child { font-family: ui-monospace, monospace; color: var(--accent-2); white-space: nowrap; }
  td { color: var(--muted); vertical-align: top; }
  .cmd {
    position: relative;
    background: var(--code-bg); border: 1px solid var(--border);
    border-radius: 10px; padding: 16px 18px; margin: 14px 0;
    overflow-x: auto;
  }
  .cmd .label {
    display: block; color: var(--muted); font-size: 0.78rem;
    text-transform: uppercase; letter-spacing: 0.07em; margin-bottom: 8px;
  }
  .copy-btn {
    position: absolute; top: 12px; right: 12px;
    background: var(--panel); color: var(--muted);
    border: 1px solid var(--border); border-radius: 8px;
    padding: 5px 12px; font-size: 0.74rem; font-weight: 600;
    text-transform: uppercase; letter-spacing: 0.06em;
    cursor: pointer; transition: all 0.15s ease;
  }
  .copy-btn:hover { color: var(--text); border-color: var(--accent); }
  .copy-btn.copied { color: #1c1f26; background: var(--accent); border-color: var(--accent); }
  .cmd pre {
    margin: 0; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 0.92rem; color: var(--text); white-space: pre;
  }
  .cmd .tok-cmd { color: var(--accent); }
  .cmd .tok-flag { color: var(--accent-2); }
  .cmd .tok-url { color: var(--orange); }
  footer {
    margin-top: 56px; padding-top: 24px; border-top: 1px solid var(--border);
    color: var(--muted); font-size: 0.88rem; text-align: center;
  }
  footer a { color: var(--accent); text-decoration: none; }
  footer a:hover { text-decoration: underline; }
</style>
</head>
<body>
<header class=\"hero\">
  <div class=\"brand\">
    <div class=\"logo\">CB</div>
    <h1>Crafterbin</h1>
  </div>
  <p class=\"tagline\">Temporary file sharing service.</p>
  <div class=\"stats\">
    <div class=\"stat\"><span class=\"k\">Min age</span><span class=\"v\">~D days</span></div>
    <div class=\"stat\"><span class=\"k\">Max age</span><span class=\"v\">~D days</span></div>
    <div class=\"stat\"><span class=\"k\">Max size</span><span class=\"v\">~A</span></div>
  </div>
</header>

<div class=\"wrap\">
  <section>
    <h2>Retention</h2>
    <p>Small files live longer, large files expire sooner. Lifetime is computed from this curve:</p>
    <div class=\"formula\">retention = min_age + (max_age - min_age) * pow((1 - file_size / max_size), 3)</div>
  </section>

  <section>
    <h2>Uploading files</h2>
    <p>Send HTTP POST requests with data encoded as <code>multipart/form-data</code>.</p>
    <table>
      <thead><tr><th>Field</th><th>Content</th><th>Remarks</th></tr></thead>
      <tbody>
        <tr><td>file</td><td>data</td><td></td></tr>
        <tr><td>url</td><td>remote URL</td><td>Mutually exclusive with &quot;file&quot;.</td></tr>
        <tr><td>secret</td><td>(ignored)</td><td>If present, generates a longer, hard-to-guess URL.</td></tr>
        <tr><td>expires</td><td>hours or ms epoch</td><td>Maximum lifetime in hours, or expiration as milliseconds since UNIX epoch.</td></tr>
      </tbody>
    </table>
  </section>

  <section>
    <h2>cURL examples</h2>
    <div class=\"cmd\"><span class=\"label\">Upload a file</span><button class=\"copy-btn\" type=\"button\">Copy</button><pre><span class=\"tok-cmd\">curl</span> <span class=\"tok-flag\">-F</span>'file=@yourfile.png' <span class=\"tok-url\">~A</span></pre></div>
    <div class=\"cmd\"><span class=\"label\">Copy from URL</span><button class=\"copy-btn\" type=\"button\">Copy</button><pre><span class=\"tok-cmd\">curl</span> <span class=\"tok-flag\">-F</span>'url=http://example.com/image.jpg' <span class=\"tok-url\">~A</span></pre></div>
    <div class=\"cmd\"><span class=\"label\">Secret URL</span><button class=\"copy-btn\" type=\"button\">Copy</button><pre><span class=\"tok-cmd\">curl</span> <span class=\"tok-flag\">-F</span>'file=@yourfile.png' <span class=\"tok-flag\">-Fsecret=</span> <span class=\"tok-url\">~A</span></pre></div>
    <div class=\"cmd\"><span class=\"label\">Set expiry (24 hours)</span><button class=\"copy-btn\" type=\"button\">Copy</button><pre><span class=\"tok-cmd\">curl</span> <span class=\"tok-flag\">-F</span>'file=@yourfile.png' <span class=\"tok-flag\">-Fexpires=24</span> <span class=\"tok-url\">~A</span></pre></div>
  </section>

  <section>
    <h2>Managing files</h2>
    <p>The <code>X-Token</code> response header contains a management token. Use <code>-i</code> with cURL to see it.</p>
    <div class=\"cmd\"><span class=\"label\">Delete a file</span><button class=\"copy-btn\" type=\"button\">Copy</button><pre><span class=\"tok-cmd\">curl</span> <span class=\"tok-flag\">-Ftoken=TOKEN</span> <span class=\"tok-flag\">-Fdelete=</span> <span class=\"tok-url\">~A/ID</span></pre></div>
    <div class=\"cmd\"><span class=\"label\">Update expiry</span><button class=\"copy-btn\" type=\"button\">Copy</button><pre><span class=\"tok-cmd\">curl</span> <span class=\"tok-flag\">-Ftoken=TOKEN</span> <span class=\"tok-flag\">-Fexpires=72</span> <span class=\"tok-url\">~A/ID</span></pre></div>
  </section>

  <footer>Powered by CrafterBin &middot; built with <a href=\"https://common-lisp.net/\">Common Lisp</a></footer>
</div>
<script>
  document.querySelectorAll('.copy-btn').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var pre = btn.parentElement.querySelector('pre');
      var text = pre.innerText.trim();
      var done = function () {
        var original = btn.textContent;
        btn.textContent = 'Copied';
        btn.classList.add('copied');
        setTimeout(function () {
          btn.textContent = original;
          btn.classList.remove('copied');
        }, 1500);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done).catch(function () {});
      } else {
        var ta = document.createElement('textarea');
        ta.value = text;
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand('copy'); done(); } catch (e) {}
        document.body.removeChild(ta);
      }
    });
  });
</script>
</body>
</html>
"
            (floor (config-min-age *config*) (* 24 3600))
            (floor (config-max-age *config*) (* 24 3600))
            (format-size (config-max-size *config*))
            base base base base base base)))

;;; ============================================================
;;; Upload page (hidden UI)
;;; ============================================================

(defun upload-page-css ()
  "Return shared CSS for upload pages, matching the site theme."
  ":root {
    --bg: #292d3e;
    --panel: #232635;
    --panel-2: #2b2f44;
    --border: #3a3f58;
    --text: #eeffff;
    --muted: #a6accd;
    --accent: #c3e88d;
    --accent-2: #82aaff;
    --orange: #f78c6c;
    --code-bg: #1c1f26;
    --danger: #f07178;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    background: var(--bg);
    color: var(--text);
    font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif;
    line-height: 1.6;
  }
  .wrap { max-width: 600px; margin: 0 auto; padding: 24px; }
  header {
    border-bottom: 1px solid var(--border);
    padding: 32px 24px 24px;
    text-align: center;
  }
  header a { color: var(--accent); text-decoration: none; font-size: 1.5rem; font-weight: 700; }
  .field { margin-bottom: 20px; }
  label { display: block; margin-bottom: 6px; color: var(--muted); font-size: 0.9rem; }
  input[type=\"file\"] {
    width: 100%; padding: 12px; background: var(--panel);
    border: 1px solid var(--border); border-radius: 10px;
    color: var(--text); font-size: 0.95rem;
  }
  input[type=\"text\"], input[type=\"number\"] {
    width: 100%; padding: 12px; background: var(--panel);
    border: 1px solid var(--border); border-radius: 10px;
    color: var(--text); font-size: 0.95rem; outline: none;
  }
  input:focus { border-color: var(--accent-2); }
  .checkbox-row { display: flex; align-items: center; gap: 10px; }
  input[type=\"checkbox\"] { width: 18px; height: 18px; accent-color: var(--accent); }
  .hint { font-size: 0.8rem; color: var(--muted); margin-top: 4px; }
  .btn {
    display: block; width: 100%; padding: 14px;
    background: linear-gradient(135deg, var(--accent), var(--accent-2));
    color: #1c1f26; border: none; border-radius: 10px;
    font-size: 1rem; font-weight: 700; cursor: pointer;
    transition: opacity 0.15s ease;
  }
  .btn:hover { opacity: 0.9; }
  .result-box {
    background: var(--code-bg); border: 1px solid var(--border);
    border-radius: 10px; padding: 16px; margin: 16px 0;
    position: relative; word-break: break-all;
    font-family: ui-monospace, monospace; font-size: 0.92rem;
    color: var(--accent);
  }
  .copy-btn {
    position: absolute; top: 12px; right: 12px;
    background: var(--panel); color: var(--muted);
    border: 1px solid var(--border); border-radius: 8px;
    padding: 5px 12px; font-size: 0.74rem; font-weight: 600;
    text-transform: uppercase; letter-spacing: 0.06em;
    cursor: pointer; transition: all 0.15s ease;
  }
  .copy-btn:hover { color: var(--text); border-color: var(--accent); }
  .copy-btn.copied { color: #1c1f26; background: var(--accent); border-color: var(--accent); }
  .token-box {
    background: var(--panel-2); border: 1px solid var(--border);
    border-radius: 10px; padding: 14px; margin: 16px 0;
  }
  .token-box code {
    font-family: ui-monospace, monospace; color: var(--orange);
    font-size: 0.85rem; word-break: break-all;
  }
  .error-msg {
    background: rgba(240,113,120,0.1); border: 1px solid var(--danger);
    border-radius: 10px; padding: 16px; color: var(--danger);
    margin: 16px 0;
  }
  .actions { display: flex; gap: 12px; margin-top: 24px; }
  .actions a {
    flex: 1; text-align: center; padding: 12px;
    background: var(--panel); border: 1px solid var(--border);
    border-radius: 10px; color: var(--text); text-decoration: none;
    font-size: 0.9rem; transition: all 0.15s ease;
  }
  .actions a:hover { border-color: var(--accent); color: var(--accent); }
  .or-divider {
    text-align: center; color: var(--muted); margin: 20px 0;
    font-size: 0.85rem; position: relative;
  }
  .or-divider::before, .or-divider::after {
    content: ''; position: absolute; top: 50%; width: 40%;
    height: 1px; background: var(--border);
  }
  .or-divider::before { left: 0; }
  .or-divider::after { right: 0; }")

(defun upload-page-html ()
  "Generate the HTML upload form page."
  (let ((base (or (config-base-url *config*) "/")))
    (format nil "<!DOCTYPE html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<title>Crafterbin - Upload</title>
<style>
~A</style>
</head>
<body>
<header><a href=\"~A\">Crafterbin</a></header>
<div class=\"wrap\">
  <form action=\"/upload\" method=\"POST\" enctype=\"multipart/form-data\">
    <div class=\"field\">
      <label for=\"file\">File</label>
      <input type=\"file\" name=\"file\" id=\"file\">
    </div>
    <div class=\"or-divider\">or paste a URL</div>
    <div class=\"field\">
      <label for=\"url\">Remote URL</label>
      <input type=\"text\" name=\"url\" id=\"url\" placeholder=\"https://example.com/image.png\">
    </div>
    <div class=\"field\">
      <label for=\"expires\">Expiry (hours, optional)</label>
      <input type=\"number\" name=\"expires\" id=\"expires\" min=\"1\" placeholder=\"e.g. 24\">
    </div>
    <div class=\"field\">
      <div class=\"checkbox-row\">
        <input type=\"checkbox\" name=\"secret\" id=\"secret\" value=\"1\">
        <label for=\"secret\" style=\"margin:0\">Secret URL (longer, harder to guess)</label>
      </div>
    </div>
    <button type=\"submit\" class=\"btn\">Upload</button>
  </form>
</div>
</body>
</html>"
            (upload-page-css)
            base)))

(defun upload-result-html (url token)
  "Generate the HTML result page after a successful upload."
  (format nil "<!DOCTYPE html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<title>Crafterbin - Uploaded</title>
<style>
~A</style>
</head>
<body>
<header><a href=\"/upload\">Crafterbin</a></header>
<div class=\"wrap\">
  <h2 style=\"color:var(--accent)\">Upload successful</h2>
  <p>Your file is available at:</p>
  <div class=\"result-box\">
    <button class=\"copy-btn\" type=\"button\" onclick=\"copyUrl()\">Copy</button>
    <span id=\"url-text\">~A</span>
  </div>
  <div class=\"token-box\">
    <strong style=\"color:var(--muted)\">Management token</strong><br>
    <code>~A</code>
    <p class=\"hint\">Save this token to delete the file or change its expiry later.</p>
  </div>
  <div class=\"actions\">
    <a href=\"~A\" target=\"_blank\">View file</a>
    <a href=\"/upload\">Upload another</a>
  </div>
</div>
<script>
  function copyUrl() {
    var text = document.getElementById('url-text').textContent;
    var btn = document.querySelector('.copy-btn');
    var done = function() {
      btn.textContent = 'Copied';
      btn.classList.add('copied');
      setTimeout(function() {
        btn.textContent = 'Copy';
        btn.classList.remove('copied');
      }, 1500);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done).catch(function() {});
    } else {
      var ta = document.createElement('textarea');
      ta.value = text;
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand('copy'); done(); } catch (e) {}
      document.body.removeChild(ta);
    }
  }
</script>
</body>
</html>"
            (upload-page-css)
            url
            token
            url))

(defun upload-error-html (message)
  "Generate the HTML error page for a failed upload."
  (format nil "<!DOCTYPE html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<title>Crafterbin - Error</title>
<style>
~A</style>
</head>
<body>
<header><a href=\"/upload\">Crafterbin</a></header>
<div class=\"wrap\">
  <h2 style=\"color:var(--danger)\">Upload failed</h2>
  <div class=\"error-msg\">~A</div>
  <div class=\"actions\">
    <a href=\"/upload\">Try again</a>
  </div>
</div>
</body>
</html>"
            (upload-page-css)
            message))

;;; ============================================================
;;; Handlers
;;; ============================================================

(defun perform-upload ()
  "Core upload logic shared by handle-upload and handle-upload-ui.
   Returns (values :ok url token) on success,
   or (values :error message code) on failure."
  (let* ((file-param (hunchentoot:post-parameter "file"))
         (url-param (hunchentoot:post-parameter "url"))
         (secret-param (hunchentoot:post-parameter "secret"))
         (expires-param (hunchentoot:post-parameter "expires"))
         (secret-p (not (null secret-param)))
         (expires (when (and expires-param (plusp (length expires-param)))
                   (parse-integer expires-param :junk-allowed t))))
    ;; Rate limit check
    (unless (check-rate-limit (client-ip))
      (return-from perform-upload
        (values :error
                (format nil "Rate limit exceeded (max ~D uploads per ~D minutes)"
                        *max-requests* (floor *window-seconds* 60))
                429)))
    (cond
      ;; File upload
      ((and file-param (listp file-param))
       (destructuring-bind (tmp-path original-name content-type) file-param
         (let ((size (with-open-file (f tmp-path) (file-length f))))
           ;; Size check
           (when (> size (config-max-size *config*))
             (return-from perform-upload
               (values :error
                       (format nil "File too large (~A, max ~A)"
                               (format-size size) (format-size (config-max-size *config*)))
                       413)))
           ;; ClamAV scan
           (handler-case (scan-file tmp-path)
             (virus-detected (v)
               (return-from perform-upload
                 (values :error
                         (format nil "Virus detected (~A)" (virus-signature v))
                         403))))
           (let* ((expiry (compute-expiry-time size :expires expires))
                  (entry (with-open-file (in tmp-path :element-type '(unsigned-byte 8))
                           (store-upload in original-name content-type size expiry
                                         :ip (client-ip)
                                         :user-agent (client-ua)
                                         :secret-p secret-p))))
             (values :ok (file-url entry) (entry-token entry))))))

      ;; URL fetch
      ((and url-param (plusp (length url-param)))
       (handler-case
           (let* ((expiry-default (compute-expiry-time 0 :expires expires))
                  (entry (store-from-url url-param expiry-default
                                         :ip (client-ip)
                                         :user-agent (client-ua)
                                         :secret-p secret-p)))
             ;; ClamAV scan the stored file
             (handler-case (scan-file (file-data-path (entry-id entry)))
               (virus-detected (v)
                 (delete-entry (entry-id entry))
                 (return-from perform-upload
                   (values :error
                           (format nil "Virus detected (~A)" (virus-signature v))
                           403))))
             ;; Recompute expiry with actual size
             (let ((real-expiry (compute-expiry-time (entry-size entry) :expires expires)))
               (unless (= real-expiry (entry-expires-at entry))
                 (update-entry-expiry (entry-id entry) real-expiry)))
             (values :ok (file-url entry) (entry-token entry)))
         (error (e)
           (values :error (format nil "Error fetching URL: ~A" e) 400))))

      ;; Nothing provided
      (t
       (values :error "No file or URL provided" 400)))))

(defun handle-upload ()
  "Handle POST to / - file upload or URL fetch (plain text response)."
  (multiple-value-bind (status data info) (perform-upload)
    (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
    (case status
      (:ok
       (setf (hunchentoot:header-out :x-token) info)
       (format nil "~A~%" data))
      (:error
       (setf (hunchentoot:return-code*) info)
       (format nil "Error: ~A~%" data)))))

(defun handle-upload-ui ()
  "Handle POST to /upload - file upload with HTML response."
  (multiple-value-bind (status data info) (perform-upload)
    (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
    (case status
      (:ok
       (upload-result-html data info))
      (:error
       (setf (hunchentoot:return-code*) info)
       (upload-error-html data)))))

(defun handle-manage (id)
  "Handle POST to /<id> - delete or update expiry."
  (let* ((token (hunchentoot:post-parameter "token"))
         (delete-param (hunchentoot:post-parameter "delete"))
         (expires-param (hunchentoot:post-parameter "expires"))
         (entry (lookup-entry id)))
    (cond
      ((null entry)
       (setf (hunchentoot:return-code*) 404)
       (format nil "Not found~%"))
      ((or (null token) (not (string= token (entry-token entry))))
       (setf (hunchentoot:return-code*) 403)
       (format nil "Invalid token~%"))
      ;; Delete
      (delete-param
       (delete-entry id)
       (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
       (format nil "Deleted~%"))
      ;; Update expiry
      ((and expires-param (plusp (length expires-param)))
       (let* ((expires (parse-integer expires-param :junk-allowed t))
              (new-expiry (when expires
                            (compute-expiry-time (entry-size entry) :expires expires))))
         (if new-expiry
             (progn
               (update-entry-expiry id new-expiry)
               (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
               (format nil "Expiry updated~%"))
             (progn
               (setf (hunchentoot:return-code*) 400)
               (format nil "Invalid expiry value~%")))))
      (t
       (setf (hunchentoot:return-code*) 400)
       (format nil "No action specified (use 'delete' or 'expires')~%")))))

(defun handle-download (id)
  "Handle GET to /<id> - serve the file."
  (let ((entry (lookup-entry id)))
    (cond
      ((null entry)
       (setf (hunchentoot:return-code*) 404)
       (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
       (format nil "Not found~%"))
      ;; Check if expired
      ((and (entry-expires-at entry)
            (<= (entry-expires-at entry) (get-universal-time)))
       (delete-entry id)
       (setf (hunchentoot:return-code*) 404)
       (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
       (format nil "Expired~%"))
      (t
       (let ((path (file-data-path id)))
         (setf (hunchentoot:header-out :content-disposition) "inline")
         (hunchentoot:handle-static-file path (entry-content-type entry)))))))

;;; ============================================================
;;; Dispatcher
;;; ============================================================

(defclass crafterbin-acceptor (hunchentoot:easy-acceptor) ()
  (:documentation "Custom acceptor for CrafterBin."))

(defmethod hunchentoot:acceptor-dispatch-request ((acceptor crafterbin-acceptor)
                                                   request)
  (let* ((uri (hunchentoot:request-uri request))
         (method (hunchentoot:request-method request))
         ;; Strip leading slash, and any trailing custom filename
         ;; (e.g. /abcd/image.png -> abcd)
         (path (string-left-trim "/" uri))
         (id (let ((slash (position #\/ path)))
               (if slash (subseq path 0 slash) path))))
    (cond
      ;; Root
      ((or (string= path "") (string= path "/"))
       (case method
         (:get
          (if (wants-html-p)
              (progn
                (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
                (landing-page-html))
              (progn
                (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
                (landing-page))))
         (:post
          (handle-upload))
         (t
          (setf (hunchentoot:return-code*) 405)
          "Method not allowed")))

      ;; Upload UI
      ((string= path "upload")
       (case method
         (:get
          (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
          (upload-page-html))
         (:post
          (handle-upload-ui))
         (t
          (setf (hunchentoot:return-code*) 405)
          "Method not allowed")))

      ;; File endpoint
      ((plusp (length id))
       (case method
         (:get (handle-download id))
         (:post (handle-manage id))
         (t
          (setf (hunchentoot:return-code*) 405)
          "Method not allowed")))

      (t
       (setf (hunchentoot:return-code*) 404)
       "Not found"))))

;;; ============================================================
;;; Server lifecycle
;;; ============================================================

(defun start-server ()
  "Start the HTTP server."
  (setf *acceptor*
        (make-instance 'crafterbin-acceptor
                       :address (config-host *config*)
                       :port (config-port *config*)
                       :access-log-destination nil
                       :message-log-destination *error-output*))
  (hunchentoot:start *acceptor*)
  (format *error-output* "~&[server] Listening on ~A:~D~%"
          (config-host *config*) (config-port *config*)))

(defun stop-server ()
  "Stop the HTTP server."
  (when *acceptor*
    (hunchentoot:stop *acceptor*)
    (setf *acceptor* nil))
  (format *error-output* "~&[server] Stopped~%"))
