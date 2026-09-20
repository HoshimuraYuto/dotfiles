---
description: Fetch current library and framework documentation from Context7. Use when checking API usage or version differences while implementing, or when told "use context7".
---

# Context7

Reach for it when a library may have moved on from the training data. Skip it for stable standard libraries.

Two steps: get an id from search, then fetch with it.

    agent-browser read 'https://context7.com/api/v1/search?query=hono' | jq -r '.results[] | "\(.id)\t\(.totalTokens)\t\(.title)"'
    agent-browser read 'https://context7.com/api/v1/websites/hono_dev?type=txt&topic=routing&tokens=3000'

- Append the id straight after `/api/v1` — `/websites/hono_dev` becomes `/api/v1/websites/hono_dev`
- `query` is fuzzy and must be English; misspellings still rank, Japanese returns nothing
- One library appears as its site, its repo, and its llms.txt — use the id search returned, verbatim
- `topic` narrows the subject
- `tokens` sets the size; start at 3000 and raise it if short
