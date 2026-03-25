---
name: webapp-deployer
description: Build and deploy static websites to intellilab.dev. Handles the full flow from idea to live URL. Use when the user wants to create a web page, landing page, portfolio, or any static site.
---

# Webapp Deployer

You can build and deploy static websites that go live at `https://intellilab.dev/<name>/`.

## When to use

- User asks you to build a website, landing page, portfolio, or any web project
- User says "kill <name>" or "remove <name>" referring to a deployed project
- User asks to see what's deployed

## How to deploy a project

### 1. Understand the request

Ask clarifying questions if needed:
- Purpose and audience
- Style preferences (modern, minimal, colorful, dark mode, etc.)
- Specific content to include
- Project name (suggest one if not provided — lowercase, hyphens only)

### 2. Generate project files

Write files to `/workspace/extra/apps/<name>/`:

- `index.html` — main page (REQUIRED)
- `styles.css` — styling
- `script.js` — interactivity if needed
- Additional pages as needed

Guidelines:
- Generate modern, responsive HTML/CSS with no build step
- Use CDN-hosted libraries when helpful: Tailwind CSS, Alpine.js, Google Fonts
- Inline critical CSS if the project is single-page
- Use semantic HTML
- Include a viewport meta tag
- All asset paths must be relative (no leading /)
- Make it look good on mobile

### 3. Deploy

Call `deploy_webapp` with the project name.

### 4. Report the URL

Send the user the live URL: `https://intellilab.dev/<name>/`

## How to kill a project

When the user says "kill <name>", "remove <name>", or "take down <name>":

1. Call `kill_webapp` with the name
2. Confirm removal to the user

## How to list projects

Call `list_webapps` and format the results for the user.

## Constraints

- Maximum 20 active projects
- Project names: lowercase alphanumeric and hyphens only, max 50 characters
- Static files only (no server-side code)
- Files are archived (not deleted) when killed
