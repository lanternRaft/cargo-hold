# Sites compatibility probe

Owner-private Site ID: `appgprj_6aca4ce1d4f481918bf06d60ae905274`.
URL: https://magic-box-pastel-pocket.ecranston116442.chatgpt.site

This is a compatibility diagnostic, **not a playable deployment**.
On 2026-10-10 the authenticated deployed `/` returned HTTP 200 without
Cross-Origin-Opener-Policy or Cross-Origin-Embedder-Policy. `/_headers` returned
HTTP 200 with the literal configuration as application/octet-stream. Sites'
static hosting does not apply that configuration in this tested route.

The supported standalone Worker ESM starter copies only one JS entrypoint and
forbids standalone assets; it is not a supported delivery path for this exported
engine's 41 MiB side module plus separate addon module and other assets. No
asset-size limit for Sites static hosting is documented by the installed skill;
do not infer one from Cloudflare limits. A Sites route supporting arbitrary
export assets **and real response headers** must be established before publishing
the game. Authentication and top-level browser isolation also remain unverified.
Do not change sharing, hosts, engines, or inline the engine into a Worker.

The export preparation command is `python3 tools/export_web.py` from the parent
repository. The hosting manifest is retained for a future compatible deployment.
No credentials are stored here.
