# Free hosting on Render

The game and the online server both run on [Render](https://render.com)'s free plan, which works with private GitHub repos.

| Piece | Where | Address (by default) |
| --- | --- | --- |
| The game | Render static site, served from the `web-build` branch | `https://quick-fight.onrender.com` |
| Online server | Render free web service, from the `server/` folder | `wss://quick-fight-server.onrender.com/ws` |

Every merge to `main` runs CI. If the tests pass, it pushes a fresh web build to `web-build`, and Render republishes it.

## One-time setup (about 10 minutes)

1. Merge the pull request that adds `render.yaml`, then wait for CI on `main` to finish. That creates the `web-build` branch.
2. Sign up at https://render.com with **"Sign up with GitHub"**. No credit card is needed.
3. In Render: **New → Blueprint**. Connect GitHub when asked, and give Render access to `teamquickcopy-dev/quick-fight`.
4. Pick the repo. Render reads `render.yaml` and shows two services, `quick-fight-server` and `quick-fight`. It asks for `TURN_URLS`, `TURN_USERNAME` and `TURN_CREDENTIAL`: leave them empty for now.
5. Click **Apply** and wait for both to say **Live**, which takes a few minutes.
6. Check the addresses Render gave each service. If the server's address is **not** `quick-fight-server.onrender.com` (Render adds a suffix when a name is taken), send it to Claude or set it yourself:
   - In GitHub: Settings → Secrets and variables → Actions → **Variables** → New variable.
   - Name: `QF_SERVER_URL`. Value: `wss://<server address>/ws`.
   - Then re-run the latest CI run on `main`.
7. Open the game's address on two devices: Online → pick a fighter → Create room / Join room.

## Good to know

- **Sleeping server:** on the free plan the online server sleeps after 15 minutes without players. The game wakes it as soon as the page opens, so it is usually awake by the time you reach the Online menu. If not, the first connection can take up to about a minute.
- **Strict networks:** about 1 in 10 players are on networks (some mobile carriers, offices) that block direct connections. For them, add a free relay:
  1. Sign up at https://www.metered.ca/tools/openrelay/.
  2. Put its TURN addresses, username and password into the server's `TURN_URLS`, `TURN_USERNAME` and `TURN_CREDENTIAL` in the Render dashboard (Environment).
- **Desktop players:** the desktop game connects to a local server by default. To use the hosted one, set the environment variable `QF_SERVER=wss://quick-fight-server.onrender.com/ws` before starting Godot.
- **Limits:** the free plan allows 100 GB/month of downloads for the site. One visit is about 4 MB, so roughly 25,000 visits.
- **Moving to a VPS later** (`infra/`) only means changing `QF_SERVER_URL` and where the files go.
