# CrowdSec Guardian Portal

A web dashboard for monitoring CrowdSec agents, managing access, and tracking attacks in real-time.

## Features

- **Agent Management** - View, validate, and manage connected CrowdSec agents
- **Real-time Alerts** - Monitor security alerts as they come in
- **Attack Tracking** - See blocked IPs, scenarios, and attack origins
- **Decision Management** - View and manage active ban/decision rules
- **Approval Workflow** - Approve or reject new agent registration requests

## Architecture

```
CrowdSec Agents (machines)
        |
        | cscli lapi register -u http://portal:3000
        v
+------------------+
| Guardian Portal  |  <-- Web Dashboard
| (Node.js/Express)|
+------------------+
        |
        v
CrowdSec LAPI (:8080)
```

The portal acts as a **proxy** to the CrowdSec Local API (LAPI). Agents register through the portal, which forwards credentials to the LAPI. The portal also provides a read-only dashboard for monitoring.

## Quick Start

### Prerequisites

- Node.js 18+
- CrowdSec installed and running with LAPI on port 8080

### Install

```bash
cd website-crowdsec-guardian/portal
npm install
```

### Configure

Create a `.env` file:

```env
PORT=3000
LAPI_URL=http://127.0.0.1:8080
LAPI_TOKEN=your-lapi-api-key
JWT_SECRET=change-this-to-a-random-string
```

### Run

```bash
node server.js
```

Then open http://localhost:3000 in your browser.

## API Endpoints

### Public (agent-facing)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/register` | Register a new agent |
| POST | `/api/agents/login` | Agent login (get JWT) |
| POST | `/api/alerts` | Push alerts from agent |

### Dashboard (requires auth)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/dashboard/agents` | List all agents |
| POST | `/api/dashboard/agents/:id/validate` | Validate an agent |
| DELETE | `/api/dashboard/agents/:id` | Remove an agent |
| GET | `/api/dashboard/alerts` | List alerts |
| GET | `/api/dashboard/decisions` | List active decisions |
| GET | `/api/dashboard/stats` | Dashboard statistics |

## Screenshots

- **Agents Tab** - See all connected agents, their IP, status, last seen
- **Alerts Tab** - Real-time feed of security alerts with filtering
- **Decisions Tab** - Active bans and remediation decisions
- **Stats Tab** - Attack overview, top blocked IPs, scenarios used
