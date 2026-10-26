# Bundled syntax highlighting

- Component: highlight.js 11.11.1, official common browser build, BSD-3-Clause.
- Source: https://github.com/highlightjs/cdn-release/blob/11.11.1/build/highlight.min.js
- License: https://github.com/highlightjs/highlight.js/blob/11.11.1/LICENSE
- SHA-256 (`highlight.min.js`): `c4a399dd6f488bc97a3546e3476747b3e714c99c57b9473154c6fb8d259b9381`

The unmodified bundle and license ship inside the app. The app injects it only into its isolated WebKit content world; no CDN requests are made at reading time. Grammar selection requires an explicit supported language. Code blocks above 20,000 characters remain plain text.

MATLAB grammar is additionally bundled from the same official 11.11.1 release:
- Source: https://github.com/highlightjs/cdn-release/blob/11.11.1/build/languages/matlab.min.js
- SHA-256 (`matlab.min.js`): `03b56d633e41ef2bfec8c1c005fe4290ae4583f444e9ffd0065e9ec9091ec6fc`
- Same BSD-3-Clause license. Loaded after the common build, before reader.js, in the same isolated content world.
- Markdown fences must specify `matlab` (case-insensitive at rendering). Unspecified/unsupported languages and blocks over 20,000 characters remain plain text.
