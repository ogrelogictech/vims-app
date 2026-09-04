# VIMS — Phase 1 App

Vision Inspection Management Solutions — the Phase 1 field inspection app (interactive UI prototype).
Single self-contained `index.html` (no build step, no dependencies).

**Live:** https://vims-app.pages.dev

## What's here
- `index.html` — the whole app (offline-first inspection app: dynamic checklists, photos, findings→summary, PDF report, company accounts + subscriptions).
- `.github/workflows/deploy.yml` — auto-deploys to Cloudflare Pages on every push to `main`.

## Deployment — runs from GitHub, not manually

On every push to `main`, GitHub Actions deploys this repo to the Cloudflare Pages project **`vims-app`**.

**One-time setup:** add a repository secret so Actions can reach Cloudflare:
1. In Cloudflare: **My Profile → API Tokens → Create Token → "Edit Cloudflare Workers"** template (or a custom token with **Account · Cloudflare Pages · Edit**). Copy the token.
2. In this GitHub repo: **Settings → Secrets and variables → Actions → New repository secret**
   - Name: `CLOUDFLARE_API_TOKEN`
   - Value: the token from step 1
3. Push to `main` (or run the workflow manually from the **Actions** tab). Done — every push now deploys.

The Cloudflare account ID (`e19974cc71177aa1f76d7e90e0a48f6c`) is set in the workflow.

## Alternative: native Cloudflare Pages Git integration
Instead of the Actions workflow you can let Cloudflare build directly from this repo:
**Cloudflare dashboard → Workers & Pages → Create → Pages → Connect to Git → pick this repo →**
build command: *(none)*, output directory: `/` (root). Then delete `.github/workflows/deploy.yml` so you don't deploy twice. (Connecting Git needs a fresh Pages project; the current `vims-app` project is direct-upload.)

## Local preview
```bash
python3 -m http.server 8080
# open http://localhost:8080
```
