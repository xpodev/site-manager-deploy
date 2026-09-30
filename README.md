# Site Manager Deploy

A GitHub / Gitea / Forgejo Action that publishes a built static site through a [Site Manager](https://git.server.xpo/xpodev/site-manager) deploy service.

```yaml
- uses: xpodev/site-manager-deploy@v1
  with:
    url: ${{ vars.DEPLOY_URL }}
    token: ${{ secrets.DEPLOY_TOKEN }}
    path: dist
```

The action packs the contents of `path` and uploads them. The deploy key decides which `namespace/site` the upload replaces. If it fails, the step shows the reason and a hint, such as a revoked key, an upload that's too large, or an unreachable server.

## Setup

1. In the Site Manager admin panel, create a deploy key for your site.
2. In the repository settings, add:
   - the secret `DEPLOY_TOKEN`: the deploy key
   - the variable `DEPLOY_URL`: the deploy service URL, e.g. `https://deploy.example.com`
3. Add a workflow:

```yaml
name: Deploy site

on:
  push:
    branches: [main]
  workflow_dispatch:

concurrency:
  group: deploy-site
  cancel-in-progress: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm

      - run: npm ci
      - run: npm run build

      - uses: xpodev/site-manager-deploy@v1
        with:
          url: ${{ vars.DEPLOY_URL }}
          token: ${{ secrets.DEPLOY_TOKEN }}
          path: dist
```

### Gitea and Forgejo

- **Gitea** resolves `xpodev/site-manager-deploy@v1` from GitHub by default (`DEFAULT_ACTIONS_URL = github`).
- **Forgejo**, or a Gitea instance whose default actions URL is set elsewhere, needs the full URL:

```yaml
- uses: https://github.com/xpodev/site-manager-deploy@v1
```

The workflow file can live in `.gitea/workflows/` or `.forgejo/workflows/`.

## Inputs

| Input     | Required | Default | Description |
|-----------|----------|---------|-------------|
| `url`     | yes      |         | Base URL of the deploy service |
| `token`   | yes      |         | Deploy key of the site. Pass it from a secret. |
| `path`    | no       | `dist`  | Folder with the built site. Its contents become the site root. |
| `retries` | no       | `2`     | Retries on network errors and 5xx responses |

## Outputs

| Output      | Description |
|-------------|-------------|
| `namespace` | Namespace the site was deployed to |
| `site`      | Name of the deployed site |
| `files`     | Number of files published |
| `bytes`     | Unpacked size of the site in bytes |

A successful run also adds the deployed site and its size to the job summary.

## Requirements

The runner needs `bash`, `tar` and `curl`. GitHub-hosted runners and the usual Gitea/Forgejo runner images have them.
