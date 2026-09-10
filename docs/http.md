# http

Fetch and post over HTTP and HTTPS with Windows' own client, WinHTTP: the
machine's proxy settings and certificate store, TLS serviced by Windows
Update, nothing vendored.

```lua
local http = require("http")
local r, e = http.get("https://example.org/tool.zip", { to = ".tools/tool.zip", timeout = "5m" })
local r, e = http.post(url, body, { type = "application/json" })
local r, e = http.request { method = "PUT", url = url, body = bytes, headers = { Authorization = token } }
```

`r` is the response:

| field | meaning |
|---|---|
| `status` | the status code as an integer; a 404 is a result, not an error |
| `headers` | names lowercased, repeats joined with `, ` |
| `rawheaders` | the header block verbatim, for the repeats that must not be joined, such as `Set-Cookie` |
| `body` | the bytes, or `""` when `to` streamed them to a file |
| `bytes` | the body length received |
| `path` | the file written, when `to` was given |

Bodies are bytes until something says otherwise; decode deliberately.
Compressed responses (gzip, deflate) are decompressed transparently.

## Options

| option | default | meaning |
|---|---|---|
| `timeout` | `"30s"` | the whole request, from connect to the last byte; `HTTP timeout` when exceeded; zero is refused because WinHTTP reads it as infinite |
| `maxbody` | `"64M"`, `"8G"` with `to` | the body is refused as `HTTP toobig` beyond this, never truncated |
| `to` | | stream the body into this file; written beside it as a temporary and renamed into place, so a failed download leaves the previous file untouched |
| `sha256` | | 64 hex digits the body must hash to, checked as it arrives; otherwise `HTTP mismatch`, and a `to` file is never placed. A non-2xx answer is then `HTTP status`, because specific bytes were asked for |
| `headers` | | a table of name = value; names and values may not contain control characters, and names no colon or space |
| `type` | `application/octet-stream` when there is a body | the `Content-Type`; wins over a `Content-Type` header |
| `redirect` | followed | `"none"` returns the first 3xx with its `location` and makes zero further requests |
| `method` | `GET` | `request` only: GET, POST, PUT, DELETE, HEAD, PATCH |

Redirects from HTTPS down to HTTP are never followed. There is no insecure
option of any kind, because such flags end up left on in something that
matters. URL fragments are client-side and are not sent. Each request runs on
its own worker thread and posts one completion to the loop, so a slow download
stalls no other task and no timer.

Requests are independent of each other: kuu keeps one WinHTTP session for the
process, because a session per request was measured to leak a handle each
time, but cookies are disabled on every request, so nothing set by one answer
is sent with the next. A caller who wants a cookie sends the `Cookie` header.

## Errors

| HTTP code | when |
|---|---|
| `timeout` | the request did not complete within `timeout` |
| `notfound` | the host name does not resolve |
| `connect` | the host refused or dropped the connection |
| `tls` | the certificate or the secure channel was rejected |
| `toobig` | the body exceeded `maxbody` |
| `mismatch` | the body did not hash to `sha256`; the message carries both digests |
| `status` | a non-2xx answer to a request that gave `sha256` |
| `badvalue` | raised: a malformed url, header, timeout, size, or redirect value |
| `encoding` | raised: a URL or header is not valid UTF-8 |
| `usage` | raised: an unknown option, or no url |
| `oserror` | anything else, with the Windows message |

A refused download destination path keeps the path helper's `FS` domain
(`badvalue`, `encoding`, or `oserror`) and is raised before the request starts.
An enclosing `sched.deadline` propagates `SCHED deadline` while cancelling the
request, independently of the request's own `HTTP timeout`.

TLS client-certificate errors 12185/12186 and proxy TLS errors 12187/12188 are
`HTTP tls`. Their messages include the Windows error symbol, number, and the
certificate, private-key permission, or proxy setting to inspect. For example,
12185 means the client-certificate context has no associated private key; it
does not by itself prove a network ban. See Microsoft's
[WinHTTP error reference](https://learn.microsoft.com/en-us/windows/win32/winhttp/error-messages).
An execution sandbox or a different account can change available credentials;
the diagnostic describes the reported failure without bypassing TLS validation.
