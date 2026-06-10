// CrowdSec Guardian Portal - Main Server
const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const http = require('http');

const app = express();
const PORT = process.env.PORT || 3000;
const LAPI_URL = process.env.LAPI_URL || 'http://127.0.0.1:8080';

app.use(cors());
app.use(express.json({ limit: '50mb' }));

// Agent Registry
const REGISTRY_FILE = path.join(__dirname, 'agents.json');

function loadRegistry() {
    try {
        if (fs.existsSync(REGISTRY_FILE)) {
            return JSON.parse(fs.readFileSync(REGISTRY_FILE, 'utf8'));
        }
    } catch (e) { /* ignore */ }
    return { agents: [], pending: [] };
}

function saveRegistry(data) {
    fs.writeFileSync(REGISTRY_FILE, JSON.stringify(data, null, 2));
}

// Dashboard Auth
const DASHBOARD_TOKEN = process.env.DASHBOARD_TOKEN || 'guardian-secret-token-2024';

function requireDashboardAuth(req, res, next) {
    const auth = req.headers.authorization;
    if (auth && auth === 'Bearer ' + DASHBOARD_TOKEN) return next();
    if (req.query.token === DASHBOARD_TOKEN) return next();
    res.status(401).json({ error: 'Unauthorized' });
}

// Helper: forward GET to LAPI
function lapiGet(apiPath, res) {
    const url = LAPI_URL + apiPath;
    http.get(url, {
        headers: { 'Authorization': 'Bearer ' + DASHBOARD_TOKEN }
    }, (lapiRes) => {
        let body = '';
        lapiRes.on('data', chunk => body += chunk);
        lapiRes.on('end', () => {
            try { res.json(JSON.parse(body)); }
            catch (e) { res.json([]); }
        });
    }).on('error', (e) => {
        console.error('[LAPI]', e.message);
        res.json([]);
    });
}

// === PUBLIC: Agent Registration ===
app.post('/api/register', (req, res) => {
    const { machine_id, password, registration_token } = req.body;
    if (!machine_id || !password) {
        return res.status(400).json({ error: 'machine_id and password required' });
    }

    const registry = loadRegistry();
    const existing = registry.agents.find(a => a.machine_id === machine_id);
    if (existing) {
        return res.json({ status: 'already_registered', machine_id });
    }

    const alreadyPending = registry.pending.find(a => a.machine_id === machine_id);
    if (alreadyPending) {
        return res.json({ status: 'pending', machine_id, message: 'Waiting for admin approval' });
    }

    registry.pending.push({
        machine_id,
        password,
        registration_token: registration_token || '',
        ip: req.ip,
        registered_at: new Date().toISOString(),
        status: 'pending'
    });

    saveRegistry(registry);
    console.log('[REGISTER] Pending: ' + machine_id + ' from ' + req.ip);
    res.json({ status: 'pending', machine_id, message: 'Waiting for admin approval' });
});

// === PUBLIC: Agent Login ===
app.post('/api/agents/login', (req, res) => {
    const { machine_id, password } = req.body;
    if (!machine_id || !password) {
        return res.status(400).json({ error: 'machine_id and password required' });
    }

    const registry = loadRegistry();
    const agent = registry.agents.find(a => a.machine_id === machine_id);

    if (!agent) {
        const pending = registry.pending.find(a => a.machine_id === machine_id);
        if (pending) return res.status(403).json({ error: 'Agent pending approval' });
        return res.status(404).json({ error: 'Agent not found. Register first.' });
    }

    if (agent.password !== password) {
        return res.status(401).json({ error: 'Invalid credentials' });
    }

    const token = Buffer.from(machine_id + ':' + Date.now()).toString('base64');
    agent.last_seen = new Date().toISOString();
    agent.status = 'active';
    saveRegistry(registry);

    console.log('[LOGIN] ' + machine_id);
    res.json({ code: 200, token, expire: new Date(Date.now() + 86400000).toISOString(), machine_id });
});

// === PUBLIC: Agent Push Alerts ===
app.post('/api/alerts', (req, res) => {
    const alerts = req.body;
    if (!Array.isArray(alerts) || alerts.length === 0) {
        return res.status(400).json({ error: 'Expected array of alerts' });
    }

    const data = JSON.stringify(alerts);
    const lapiUrl = new URL(LAPI_URL + '/v1/alerts');
    const options = {
        hostname: lapiUrl.hostname,
        port: lapiUrl.port,
        path: lapiUrl.pathname,
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(data),
            'Authorization': 'Bearer ' + DASHBOARD_TOKEN
        }
    };

    const lapiReq = http.request(options, (lapiRes) => {
        let body = '';
        lapiRes.on('data', chunk => body += chunk);
        lapiRes.on('end', () => {
            res.status(lapiRes.statusCode).json(JSON.parse(body || '{}'));
        });
    });

    lapiReq.on('error', (e) => {
        console.error('[ALERTS] LAPI error:', e.message);
        res.status(502).json({ error: 'LAPI unavailable' });
    });

    lapiReq.write(data);
    lapiReq.end();
});

// === DASHBOARD: Agents ===
app.get('/api/dashboard/agents', requireDashboardAuth, (req, res) => {
    const registry = loadRegistry();
    res.json({
        approved: registry.agents,
        pending: registry.pending,
        total: registry.agents.length,
        pending_count: registry.pending.length
    });
});

app.post('/api/dashboard/agents/:id/validate', requireDashboardAuth, (req, res) => {
    const registry = loadRegistry();
    const idx = registry.pending.findIndex(a => a.machine_id === req.params.id);
    if (idx === -1) return res.status(404).json({ error: 'Not found in pending' });

    const agent = registry.pending[idx];
    agent.status = 'approved';
    agent.validated_at = new Date().toISOString();
    registry.agents.push(agent);
    registry.pending.splice(idx, 1);
    saveRegistry(registry);

    console.log('[VALIDATE] Approved: ' + agent.machine_id);
    res.json({ status: 'approved', machine_id: agent.machine_id });
});

app.delete('/api/dashboard/agents/:id', requireDashboardAuth, (req, res) => {
    const registry = loadRegistry();
    registry.agents = registry.agents.filter(a => a.machine_id !== req.params.id);
    registry.pending = registry.pending.filter(a => a.machine_id !== req.params.id);
    saveRegistry(registry);
    res.json({ status: 'removed', machine_id: req.params.id });
});

// === DASHBOARD: Alerts ===
app.get('/api/dashboard/alerts', requireDashboardAuth, (req, res) => {
    const url = '/v1/alerts?limit=' + (req.query.limit || '100') + '&since=' + (req.query.since || '24h');
    lapiGet(url, res);
});

// === DASHBOARD: Decisions ===
app.get('/api/dashboard/decisions', requireDashboardAuth, (req, res) => {
    lapiGet('/v1/decisions', res);
});

// === DASHBOARD: Stats ===
app.get('/api/dashboard/stats', requireDashboardAuth, (req, res) => {
    const registry = loadRegistry();

    http.get(LAPI_URL + '/v1/alerts?limit=1000', {
        headers: { 'Authorization': 'Bearer ' + DASHBOARD_TOKEN }
    }, (lapiRes) => {
        let body = '';
        lapiRes.on('data', chunk => body += chunk);
        lapiRes.on('end', () => {
            let alerts = [];
            try { alerts = JSON.parse(body); } catch (e) {}

            const uniqueIPs = new Set();
            const scenarios = {};
            const origins = {};

            if (Array.isArray(alerts)) {
                alerts.forEach(a => {
                    if (a.source && a.source.ip) uniqueIPs.add(a.source.ip);
                    if (a.scenario) scenarios[a.scenario] = (scenarios[a.scenario] || 0) + 1;
                    if (a.source && a.source.origin) origins[a.source.origin] = (origins[a.source.origin] || 0) + 1;
                });
            }

            const topScenarios = Object.entries(scenarios).sort((a, b) => b[1] - a[1]).slice(0, 10).map(([name, count]) => ({ name, count }));
            const topOrigins = Object.entries(origins).sort((a, b) => b[1] - a[1]).slice(0, 10).map(([name, count]) => ({ name, count }));

            res.json({
                agents: {
                    total: registry.agents.length,
                    pending: registry.pending.length,
                    active: registry.agents.filter(a => a.status === 'active').length
                },
                alerts: { total: alerts.length, unique_ips: uniqueIPs.size },
                top_scenarios: topScenarios,
                top_origins: topOrigins
            });
        });
    }).on('error', () => {
        res.json({
            agents: { total: registry.agents.length, pending: registry.pending.length, active: 0 },
            alerts: { total: 0, unique_ips: 0 },
            top_scenarios: [], top_origins: []
        });
    });
});

// === Serve Dashboard ===
app.get('/', (req, res) => res.sendFile(path.join(__dirname, 'index.html')));
app.get('/dashboard', (req, res) => res.sendFile(path.join(__dirname, 'index.html')));

// === Start ===
app.listen(PORT, '0.0.0.0', () => {
    console.log('');
    console.log('╔══════════════════════════════════════════╗');
    console.log('║   CrowdSec Guardian Portal               ║');
    console.log('║                                          ║');
    console.log('║   Dashboard:  http://localhost:' + PORT + '      ║');
    console.log('║   LAPI Proxy: ' + LAPI_URL + '          ║');
    console.log('║                                          ║');
    console.log('║   Agent registration:                    ║');
    console.log('║   POST /api/register                     ║');
    console.log('║   POST /api/agents/login                 ║');
    console.log('║   POST /api/alerts                       ║');
    console.log('║                                          ║');
    console.log('║   Dashboard API:                         ║');
    console.log('║   GET /api/dashboard/agents              ║');
    console.log('║   GET /api/dashboard/alerts              ║');
    console.log('║   GET /api/dashboard/decisions           ║');
    console.log('║   GET /api/dashboard/stats               ║');
    console.log('╚══════════════════════════════════════════╝');
    console.log('');
});
