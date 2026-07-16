# workflow- : Self-hosted n8n (Render first, portable to Oracle Cloud)

A production-oriented, self-hosted [n8n](https://n8n.io) deployment. Built to run on
[Render](https://render.com) first, with an architecture that doesn't lock you into it --
the same Docker image and the same external Postgres database work unchanged on
Oracle Cloud Always Free (or any other Docker host) later.

## Architecture, and why it's built this way

```
                        HTTPS
                          |
                          v
                 +-----------------+
                 |     Render      |   <- Docker web service, built from ./Dockerfile
                 |  (n8n container)|      Ephemeral filesystem -- nothing important
                 +--------+--------+      is stored here.
                          |
                          | Postgres (SSL, port 5432)
                          v
                 +-----------------+
                 |    Supabase     |   <- All workflows, credentials (encrypted),
                 |   (Postgres)    |      and execution history actually live here.
                 +-----------------+
```

**Why an external database (Supabase) instead of the SQLite n8n uses by default?**
Render's filesystem is ephemeral outside of a paid persistent disk -- every redeploy
or restart wipes local files. Render's own free Postgres add-on is worse for this
specific case: it's auto-deleted 30 days after creation. Supabase's Postgres persists
independently of whatever's running n8n, which is also exactly what makes the later
move to Oracle Cloud a non-event: point the same `DB_POSTGRESDB_*` variables at the
same Supabase project, and every workflow, credential, and execution record is already
there.

**Why Docker/Docker Compose specifically?** Docker Compose (`docker-compose.yml`) is
for local development only -- Render does not run Compose files. Render builds and
runs a single container from `Dockerfile`, configured by `render.yaml`. Keeping both
means you can develop and test locally with full parity to what actually deploys.

## Repository structure

```
.
├── Dockerfile              # Production image: extends the official n8n image
├── docker-compose.yml       # LOCAL dev/test only (n8n + throwaway local Postgres)
├── render.yaml              # Render Blueprint -- this is what deploys on Render
├── .env.example             # Every environment variable, explained, no real values
├── .gitignore                # Keeps secrets and local data out of git
├── .dockerignore             # Keeps secrets and local data out of the image build
└── README.md                 # This file
```

This is intentionally minimal. There's no application code to review because n8n
itself is the application -- what you're versioning here is the *deployment
configuration*, which is the correct thing to keep in git for this kind of project.

---

## 1. Local development

```bash
git clone <your-repo-url>
cd workflow-
cp .env.example .env
# edit .env: at minimum set N8N_ENCRYPTION_KEY, DB_POSTGRESDB_PASSWORD,
# GENERIC_TIMEZONE, and TZ. Leave DB_POSTGRESDB_HOST unset/ignored locally --
# docker-compose.yml points it at the local "postgres" service automatically.

docker compose up -d
# n8n is now at http://localhost:5678
```

Generate the encryption key once:
```bash
openssl rand -hex 32
```
Save this value somewhere durable (a password manager). You'll use the *same* key
in every environment this instance ever runs in -- losing it makes every stored
credential unreadable.

---

## 2. Deploying to Render

### Step 1 -- push this repo to GitHub

From your own machine (not from this chat -- see the security note at the end of
this README for why):
```bash
git add .
git commit -m "Add n8n deployment configuration"
git push origin main
```

### Step 2 -- create the Render Blueprint

1. Go to the Render Dashboard -> **New** -> **Blueprint**.
2. Connect and select this repository. Render detects `render.yaml` automatically.
3. Render will list every environment variable marked `sync: false` in
   `render.yaml` and prompt you to fill each one in -- this is the point where
   you paste in real secrets, directly into Render's dashboard, never into git.

### Step 3 -- set up Supabase first (you'll need its values for Step 2)

1. Create a project at [supabase.com](https://supabase.com).
2. Go to **Project Settings > Database > Connection info** for the host, port,
   database name, and user.
3. Go to **Project Settings > Database > Database password** for the password
   (or reset it there if you don't have it).
4. Use the **direct connection** (port 5432), not the connection pooler --
   n8n's Postgres client works most reliably against the direct connection.

### Step 4 -- fill in the remaining variables and deploy

Everything else is documented inline in `.env.example` and `render.yaml`. Two
that depend on each other: `N8N_HOST` and `WEBHOOK_URL` both need your Render
service's actual `.onrender.com` URL -- which only exists *after* your first
deploy. Common pattern: deploy once with placeholder values, copy the real URL
Render assigns, update those two variables, and Render will redeploy.

### Step 5 -- first login

Visit your service's URL. n8n's setup wizard will ask you to create the owner
account (email + password) on first visit -- this replaces the older
basic-auth-only setup, and is where your actual login lives going forward.

---

## 3. Environment variables -- what each one is and where it comes from

| Variable | Purpose | Where you get the value |
|---|---|---|
| `N8N_ENCRYPTION_KEY` | Encrypts all stored credentials | Generate once: `openssl rand -hex 32` |
| `N8N_PROTOCOL` | Tells n8n to generate `https://` links | Fixed value: `https` |
| `N8N_HOST` | Public hostname n8n considers itself at | Your Render `.onrender.com` URL (after first deploy) |
| `N8N_PORT` / `PORT` | Port n8n listens on / Render's routing port | Fixed value: `5678` (must match each other) |
| `WEBHOOK_URL` | Explicit base URL for generated webhooks | `https://<your-service>.onrender.com/` |
| `N8N_PROXY_HOPS` | Reverse-proxy hop count | `1` on Render, `0` on a bare VM with no proxy |
| `N8N_SECURE_COOKIE` | Requires HTTPS for auth cookies | `true` (Render provides HTTPS at its edge) |
| `GENERIC_TIMEZONE` / `TZ` | Timezone for schedule triggers / logs | Your IANA timezone, e.g. `America/New_York` |
| `N8N_RUNNERS_ENABLED` | Isolates Code-node execution | Fixed value: `true` |
| `DB_TYPE` | Selects Postgres over default SQLite | Fixed value: `postgresdb` |
| `DB_POSTGRESDB_HOST/PORT/DATABASE/USER/PASSWORD` | Supabase connection details | Supabase dashboard -> Project Settings -> Database |
| `DB_POSTGRESDB_SCHEMA` | Postgres schema n8n uses | Fixed value: `public` (unless you set up a custom schema) |
| `DB_POSTGRESDB_SSL_ENABLED` / `_SSL_REJECT_UNAUTHORIZED` | Supabase requires SSL | Fixed value: `true` / `true` |
| `EXECUTIONS_DATA_PRUNE` / `_MAX_AGE` | Auto-clean old execution history | Your retention preference (default here: 14 days) |
| `N8N_LOG_LEVEL` | Log verbosity | `info` for production, `debug` when troubleshooting |

**Credentials you'll add later, inside the n8n editor UI (not as env vars):**
GitHub, Telegram, Gmail, Google Drive, RSS, Supabase (as a workflow data
source), and any AI provider. Full detail on where to obtain each value is in
the bottom section of `.env.example` -- summarized:

| Service | Where to get it |
|---|---|
| GitHub | github.com/settings/tokens (fine-grained PAT) or a registered OAuth App |
| Telegram | @BotFather on Telegram -> `/newbot` |
| Gmail / Google Drive | console.cloud.google.com -> enable the API -> OAuth 2.0 Client ID |
| RSS | No credential -- just the feed URL |
| Supabase (workflow node) | Project Settings -> API -> Project URL + key |
| AI providers | Provider's own API console (e.g. platform.openai.com, console.anthropic.com) |

---

## 4. Security practices already built into this repo

- No secrets are hardcoded anywhere in `Dockerfile`, `docker-compose.yml`, or
  `render.yaml` -- every secret is `sync: false` (Render) or left blank in
  `.env.example` (local), meaning it only ever lives in Render's encrypted
  environment store or your local, git-ignored `.env` file.
- `.gitignore` and `.dockerignore` both explicitly exclude `.env`, common key
  file extensions (`.pem`, `.key`, `.p12`), and typical credential JSON file
  name patterns, in addition to the usual OS/editor noise.
- The base image runs as a non-root user, and we don't override that.
- `N8N_ENCRYPTION_KEY` is never regenerated across environments in these
  instructions -- doing so silently would strand every stored credential.

**A note on GitHub tokens generally, unrelated to any specific token:** a
Personal Access Token is a bearer credential -- anyone who has the string can
act as you against everything it's scoped to, with no additional proof of
identity. Treat any PAT you generate the way you'd treat a password: create it
scoped as narrowly as possible (fine-grained tokens can be limited to a single
repo), give it an expiration date, and never paste it into a chat window, a
Slack message, or a screenshot.

---

## 5. Migrating to Oracle Cloud Always Free later

Because the architecture keeps all state in Supabase and all configuration in
environment variables, migration is mechanical, not a rebuild:

1. Provision an Oracle Cloud Always Free compute instance, install Docker.
2. Copy `Dockerfile` and `docker-compose.yml` to the instance (or just `docker
   run` the same image directly).
3. Set the same environment variables -- same `N8N_ENCRYPTION_KEY`, same
   `DB_POSTGRESDB_*` values pointing at the same Supabase project.
4. Update only the environment-specific values: `N8N_HOST`, `WEBHOOK_URL`, and
   `N8N_PROXY_HOPS` (likely `0` if you're not putting a reverse proxy in front
   of it, or `1` if you add one, e.g. Caddy or nginx for your own TLS).
5. Point your DNS/traffic at the new instance; decommission the Render service.

Nothing in your workflows, credentials, or execution history needs to move,
because none of it was ever stored on Render in the first place.

---

## 6. Before you actually deploy this to real production -- recommended improvements

- **Pin the n8n image version** in `Dockerfile` (currently `latest`, see the
  comment there) so upgrades are a deliberate choice, not something that
  happens silently on your next rebuild.
- **Create a dedicated Postgres role for n8n in Supabase** rather than using
  the default `postgres` superuser -- grant it only what it needs on its own
  schema.
- **Decide on a real backup story for Supabase** beyond Supabase's own
  defaults if this instance will hold anything you can't afford to lose.
- **Consider Render's Starter-or-above plan** (already set in `render.yaml`)
  rather than Free -- explained above, this matters specifically because n8n
  exists to receive webhooks at unpredictable times.
- **Set a custom domain and review `N8N_SECURE_COOKIE`/cookie settings** once
  you're past the `.onrender.com` default hostname, since some browsers treat
  third-party-style subdomains more strictly.
- **Revisit `EXECUTIONS_DATA_MAX_AGE`** based on your actual compliance/debug
  needs -- 14 days is a reasonable starting default, not a requirement.
- **Rotate `DB_POSTGRESDB_PASSWORD` and any credential typed into this chat
  session** -- see the note below.

---

## A note on how this project got pushed (or didn't) to GitHub

This README and every file in this repo were generated without ever using a
GitHub token pasted into a chat conversation, by design: any credential typed
into an AI chat interface should be treated as exposed the moment it's typed,
regardless of what the assistant does with it afterward. If a token for this
repository was shared during the conversation that produced these files,
**revoke it** (GitHub -> Settings -> Developer settings -> Personal access
tokens -> find it -> Revoke) and generate a fresh one before using it anywhere,
including to push these very files.

To push safely from here on: authenticate from your own machine, using
whichever of these you're already comfortable with -- the GitHub CLI
(`gh auth login`), an SSH key registered to your GitHub account, or a freshly
generated PAT entered directly into your local git credential manager (not
into any chat).
