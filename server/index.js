const express = require("express");
const cors = require("cors");
const { WebSocketServer } = require("ws");
const http = require("http");
const path = require("path");
const { db, getAllTasks, getTaskById, getTasksByStatus, createTask, updateTask, updateTaskStatus, updateTaskPid, updateTaskLogs, updateTaskArtifacts, updateTaskExitCode, deleteTask, addLog, getLogs, clearLogs, getStats, close } = require("./db/tasks");

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

const PORT = process.env.PORT || 3001;
const HOST = process.env.HOST || "0.0.0.0";

// Middleware
app.use(cors());
app.use(express.json({ limit: "10mb" }));
app.use(express.urlencoded({ extended: true }));

// Health check endpoint
app.get("/api/health", (req, res) => {
  res.json({ status: "ok", timestamp: new Date().toISOString() });
});

// WebSocket connection handling
const clients = new Set();

wss.on("connection", (ws) => {
  clients.add(ws);
  console.log("WebSocket client connected. Total clients:", clients.size);
  
  ws.on("close", () => {
    clients.delete(ws);
    console.log("WebSocket client disconnected. Total clients:", clients.size);
  });
  
  ws.on("error", (error) => {
    console.error("WebSocket error:", error);
    clients.delete(ws);
  });
});

function broadcast(message) {
  const data = JSON.stringify(message);
  clients.forEach((client) => {
    if (client.readyState === 1) { // WebSocket.OPEN
      try {
        client.send(data);
      } catch (error) {
        console.error("Error broadcasting to client:", error);
      }
    }
  });
}

// API Routes

// Get all tasks
app.get("/api/tasks", (req, res) => {
  try {
    const tasks = getAllTasks();
    res.json(tasks);
  } catch (error) {
    console.error("Error fetching tasks:", error);
    res.status(500).json({ error: "Failed to fetch tasks" });
  }
});

// Get task stats
app.get("/api/tasks/stats", (req, res) => {
  try {
    const stats = getStats();
    res.json(stats);
  } catch (error) {
    console.error("Error fetching stats:", error);
    res.status(500).json({ error: "Failed to fetch stats" });
  }
});

// Get task by ID
app.get("/api/tasks/:id", (req, res) => {
  try {
    const task = getTaskById(req.params.id);
    if (!task) {
      return res.status(404).json({ error: "Task not found" });
    }
    res.json(task);
  } catch (error) {
    console.error("Error fetching task:", error);
    res.status(500).json({ error: "Failed to fetch task" });
  }
});

// Get tasks by status
app.get("/api/tasks/status/:status", (req, res) => {
  try {
    const tasks = getTasksByStatus(req.params.status);
    res.json(tasks);
  } catch (error) {
    console.error("Error fetching tasks by status:", error);
    res.status(500).json({ error: "Failed to fetch tasks" });
  }
});

// Create task
app.post("/api/tasks", (req, res) => {
  try {
    const task = createTask(req.body);
    broadcast({ type: "task_created", task });
    res.status(201).json(task);
  } catch (error) {
    console.error("Error creating task:", error);
    res.status(500).json({ error: "Failed to create task" });
  }
});

// Update task
app.put("/api/tasks/:id", (req, res) => {
  try {
    const task = updateTask(req.params.id, req.body);
    if (!task) {
      return res.status(404).json({ error: "Task not found" });
    }
    broadcast({ type: "task_updated", task });
    res.json(task);
  } catch (error) {
    console.error("Error updating task:", error);
    res.status(500).json({ error: "Failed to update task" });
  }
});

// Update task status
app.patch("/api/tasks/:id/status", (req, res) => {
  try {
    const { status } = req.body;
    if (!status) {
      return res.status(400).json({ error: "Status is required" });
    }
    const task = updateTaskStatus(req.params.id, status);
    if (!task) {
      return res.status(404).json({ error: "Task not found" });
    }
    broadcast({ type: "task_status_changed", task });
    res.json(task);
  } catch (error) {
    console.error("Error updating task status:", error);
    res.status(500).json({ error: "Failed to update task status" });
  }
});

// Update task PID
app.patch("/api/tasks/:id/pid", (req, res) => {
  try {
    const { pid } = req.body;
    if (!pid) {
      return res.status(400).json({ error: "PID is required" });
    }
    const task = updateTaskPid(req.params.id, pid);
    if (!task) {
      return res.status(404).json({ error: "Task not found" });
    }
    broadcast({ type: "task_pid_changed", task });
    res.json(task);
  } catch (error) {
    console.error("Error updating task PID:", error);
    res.status(500).json({ error: "Failed to update task PID" });
  }
});

// Update task logs
app.patch("/api/tasks/:id/logs", (req, res) => {
  try {
    const { logs } = req.body;
    if (logs === undefined) {
      return res.status(400).json({ error: "Logs are required" });
    }
    const task = updateTaskLogs(req.params.id, logs);
    if (!task) {
      return res.status(404).json({ error: "Task not found" });
    }
    broadcast({ type: "task_logs_changed", task });
    res.json(task);
  } catch (error) {
    console.error("Error updating task logs:", error);
    res.status(500).json({ error: "Failed to update task logs" });
  }
});

// Update task artifacts
app.patch("/api/tasks/:id/artifacts", (req, res) => {
  try {
    const { artifacts } = req.body;
    if (!artifacts) {
      return res.status(400).json({ error: "Artifacts are required" });
    }
    const task = updateTaskArtifacts(req.params.id, artifacts);
    if (!task) {
      return res.status(404).json({ error: "Task not found" });
    }
    broadcast({ type: "task_artifacts_changed", task });
    res.json(task);
  } catch (error) {
    console.error("Error updating task artifacts:", error);
    res.status(500).json({ error: "Failed to update task artifacts" });
  }
});

// Update task exit code
app.patch("/api/tasks/:id/exit-code", (req, res) => {
  try {
    const { exitCode } = req.body;
    if (exitCode === undefined) {
      return res.status(400).json({ error: "Exit code is required" });
    }
    const task = updateTaskExitCode(req.params.id, exitCode);
    if (!task) {
      return res.status(404).json({ error: "Task not found" });
    }
    broadcast({ type: "task_exit_code_changed", task });
    res.json(task);
  } catch (error) {
    console.error("Error updating task exit code:", error);
    res.status(500).json({ error: "Failed to update task exit code" });
  }
});

// Delete task
app.delete("/api/tasks/:id", (req, res) => {
  try {
    const deleted = deleteTask(req.params.id);
    if (!deleted) {
      return res.status(404).json({ error: "Task not found" });
    }
    broadcast({ type: "task_deleted", id: req.params.id });
    res.json({ success: true });
  } catch (error) {
    console.error("Error deleting task:", error);
    res.status(500).json({ error: "Failed to delete task" });
  }
});

// Logs endpoints
app.get("/api/tasks/:id/logs", (req, res) => {
  try {
    const logs = getLogs(req.params.id);
    res.json(logs);
  } catch (error) {
    console.error("Error fetching logs:", error);
    res.status(500).json({ error: "Failed to fetch logs" });
  }
});

app.post("/api/tasks/:id/logs", (req, res) => {
  try {
    const { level, message } = req.body;
    if (!level || !message) {
      return res.status(400).json({ error: "Level and message are required" });
    }
    addLog(req.params.id, level, message);
    res.status(201).json({ success: true });
  } catch (error) {
    console.error("Error adding log:", error);
    res.status(500).json({ error: "Failed to add log" });
  }
});

app.delete("/api/tasks/:id/logs", (req, res) => {
  try {
    clearLogs(req.params.id);
    res.json({ success: true });
  } catch (error) {
    console.error("Error clearing logs:", error);
    res.status(500).json({ error: "Failed to clear logs" });
  }
});

// Graceful shutdown
process.on("SIGTERM", () => {
  console.log("SIGTERM received, shutting down gracefully...");
  server.close(() => {
    close();
    process.exit(0);
  });
});

process.on("SIGINT", () => {
  console.log("SIGINT received, shutting down gracefully...");
  server.close(() => {
    close();
    process.exit(0);
  });
});

server.listen(PORT, HOST, () => {
  console.log("Kanban API server running on http://" + HOST + ":" + PORT);
  console.log("WebSocket server running on ws://" + HOST + ":" + PORT);
  console.log("Health check: http://localhost:" + PORT + "/api/health");
});

module.exports = { app, server, wss };
