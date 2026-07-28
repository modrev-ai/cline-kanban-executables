const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

const dbDir = path.join(__dirname, '..', '..', 'database');
if (!fs.existsSync(dbDir)) {
  fs.mkdirSync(dbDir, { recursive: true });
}

const dbPath = path.join(dbDir, 'kanban.db');
const db = new Database(dbPath);
db.pragma('journal_mode = WAL');

const COLUMNS = [
  'id', 'title', 'description', 'work_directory', 'status', 
  'prompt', 'logs', 'artifacts', 'pid', 'exit_code',
  'created_at', 'updated_at', 'started_at', 'completed_at'
].join(', ');

const mapRow = (row) => ({
  id: row.id,
  title: row.title,
  description: row.description,
  workDirectory: row.work_directory,
  status: row.status,
  prompt: row.prompt,
  logs: row.logs,
  artifacts: JSON.parse(row.artifacts || '[]'),
  pid: row.pid,
  exitCode: row.exit_code,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
  startedAt: row.started_at,
  completedAt: row.completed_at
});

const stmt = {
  getAll: db.prepare(`SELECT ${COLUMNS} FROM tasks ORDER BY updated_at DESC`),
  getById: db.prepare(`SELECT ${COLUMNS} FROM tasks WHERE id = ?`),
  getByStatus: db.prepare(`SELECT ${COLUMNS} FROM tasks WHERE status = ? ORDER BY updated_at DESC`),
  insert: db.prepare(`
    INSERT INTO tasks (id, title, description, work_directory, status, prompt, artifacts)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `),
  update: db.prepare(`
    UPDATE tasks SET 
      title = ?, description = ?, work_directory = ?, status = ?, 
      prompt = ?, logs = ?, artifacts = ?, pid = ?, exit_code = ?,
      updated_at = CURRENT_TIMESTAMP,
      started_at = COALESCE(started_at, CASE WHEN ? = 'In Progress' THEN CURRENT_TIMESTAMP ELSE started_at END),
      completed_at = CASE WHEN ? IN ('Done', 'Failed') THEN CURRENT_TIMESTAMP ELSE completed_at END
    WHERE id = ?
  `),
  updateStatus: db.prepare(`
    UPDATE tasks SET 
      status = ?, 
      updated_at = CURRENT_TIMESTAMP,
      started_at = COALESCE(started_at, CASE WHEN ? = 'In Progress' THEN CURRENT_TIMESTAMP ELSE started_at END),
      completed_at = CASE WHEN ? IN ('Done', 'Failed') THEN CURRENT_TIMESTAMP ELSE completed_at END
    WHERE id = ?
  `),
  updatePid: db.prepare(`UPDATE tasks SET pid = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?`),
  updateLogs: db.prepare(`UPDATE tasks SET logs = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?`),
  updateArtifacts: db.prepare(`UPDATE tasks SET artifacts = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?`),
  updateExitCode: db.prepare(`UPDATE tasks SET exit_code = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?`),
  delete: db.prepare(`DELETE FROM tasks WHERE id = ?`),
  
  // Logs
  insertLog: db.prepare(`INSERT INTO task_logs (task_id, level, message) VALUES (?, ?, ?)`),
  getLogs: db.prepare(`SELECT * FROM task_logs WHERE task_id = ? ORDER BY timestamp ASC`),
  deleteLogs: db.prepare(`DELETE FROM task_logs WHERE task_id = ?`),
};

const uuid = () => require('crypto').randomUUID();

module.exports = {
  db,
  
  // Task CRUD
  getAllTasks: () => stmt.getAll.all().map(mapRow),
  getTaskById: (id) => {
    const row = stmt.getById.get(id);
    return row ? mapRow(row) : null;
  },
  getTasksByStatus: (status) => stmt.getByStatus.all(status).map(mapRow),
  createTask: (task) => {
    const id = uuid();
    stmt.insert.run(
      id,
      task.title,
      task.description || '',
      task.workDirectory,
      task.status || 'Backlog',
      task.prompt || '',
      JSON.stringify(task.artifacts || [])
    );
    return module.exports.getTaskById(id);
  },
  updateTask: (id, updates) => {
    const task = module.exports.getTaskById(id);
    if (!task) return null;
    
    const updated = { ...task, ...updates };
    stmt.update.run(
      updated.title,
      updated.description,
      updated.workDirectory,
      updated.status,
      updated.prompt,
      updated.logs || '',
      JSON.stringify(updated.artifacts || []),
      updated.pid || null,
      updated.exitCode || null,
      updated.status,
      updated.status,
      id
    );
    return module.exports.getTaskById(id);
  },
  updateTaskStatus: (id, status) => {
    stmt.updateStatus.run(status, status, status, id);
    return module.exports.getTaskById(id);
  },
  updateTaskPid: (id, pid) => {
    stmt.updatePid.run(pid, id);
    return module.exports.getTaskById(id);
  },
  updateTaskLogs: (id, logs) => {
    stmt.updateLogs.run(logs, id);
    return module.exports.getTaskById(id);
  },
  appendTaskLogs: (id, newLogs) => {
    const task = module.exports.getTaskById(id);
    if (!task) return null;
    const updatedLogs = (task.logs || '') + newLogs;
    stmt.updateLogs.run(updatedLogs, id);
    return module.exports.getTaskById(id);
  },
  updateTaskArtifacts: (id, artifacts) => {
    stmt.updateArtifacts.run(JSON.stringify(artifacts), id);
    return module.exports.getTaskById(id);
  },
  updateTaskExitCode: (id, exitCode) => {
    stmt.updateExitCode.run(exitCode, id);
    return module.exports.getTaskById(id);
  },
  deleteTask: (id) => {
    stmt.deleteLogs.run(id);
    const result = stmt.delete.run(id);
    return result.changes > 0;
  },
  
  // Logs
  addLog: (taskId, level, message) => {
    stmt.insertLog.run(taskId, level, message);
  },
  getLogs: (taskId) => stmt.getLogs.all(taskId),
  clearLogs: (taskId) => {
    stmt.deleteLogs.run(taskId);
    stmt.updateLogs.run('', taskId);
  },
  
  // Stats
  getStats: () => {
    const stats = db.prepare(`
      SELECT status, COUNT(*) as count 
      FROM tasks 
      GROUP BY status
    `).all();
    const result = { Backlog: 0, 'In Progress': 0, Review: 0, Done: 0, Failed: 0 };
    stats.forEach(s => result[s.status] = s.count);
    return result;
  },
  
  close: () => db.close()
};