# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git Workflow

**MANDATORY**: Read and follow `AGENTS.md` before creating branches, committing, or opening PRs.
It contains required branch naming conventions and push/PR workflow rules.

Key rules (see `AGENTS.md` for full details):
- Feature branches MUST be named `AGENT-feature/<short-description>` (e.g. `claude-feature/magic-link-auth`)
- Never commit directly to `main` — all agent work on feature branches
- Run `npm run lint` (from `frontend/`) before creating PRs
- Work is not done until `git push` succeeds
- Always keep CLAUDE.md and AGENTS.md up to date with new requirements that are learned during a session.

## Project Overview

Monorepo containing an iOS application for location tracking and a backend to capture the data.

The backend is deployed to a single Fly.io VM with path-based routing:
- `/api/*` → Exposed API routes

## Repository Structure

To be supplied.

### Code standards
All Python code must be formatted with black.
All javascript code must pass eslint and be formatted with prettier

### Database
The database is Postgres.  Migrations should be managed using [yoyo-migrations](https://ollycope.com/software/yoyo/latest/).

### Python environment
- NEVER install python modules using pip
- ALWAYS install modules using pipenv
- When running python scripts, you must use pipenv.

## Deployment

Single Fly.io VM with path-based routing. See `Dockerfile` and `fly.toml`.
