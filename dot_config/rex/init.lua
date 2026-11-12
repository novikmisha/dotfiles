local database = os.getenv("HOME") .. "/Library/Application Support/rex/session-roots.sqlite3"

local function quote(value)
  return "'" .. value:gsub("'", "''") .. "'"
end

local function sql(query)
  local result = assert(rex.exec({
    "/usr/bin/sqlite3",
    "-batch",
    "-bail",
    "-json",
    "-init",
    "/dev/null",
    "-cmd",
    ".timeout 3000",
    database,
    "CREATE TABLE IF NOT EXISTS session_roots (session_id TEXT PRIMARY KEY, root TEXT NOT NULL); " .. query,
  }))
  assert(result.ok, result.stderr)
  if result.stdout == "" then
    return {}
  end
  return assert(rex.json.decode(result.stdout))
end

-- The same file runs as the cleanup listener under launchd, without extra Lua files.
if rex.args ~= nil then
  rex.on("session_destroyed", function(ctx, ev)
    local session = assert(ev.session_id or ctx.session_id, "Missing destroyed session ID")
    sql("DELETE FROM session_roots WHERE session_id = " .. quote(session))
  end)
  local list = assert(rex.call("session.list"))
  local ids = {}
  for _, session in ipairs(list.sessions or {}) do
    ids[#ids + 1] = quote(session.session_id)
  end
  -- SQLite's empty IN list also handles zero open sessions.
  sql("DELETE FROM session_roots WHERE session_id NOT IN (" .. table.concat(ids, ",") .. ")")
  return
end

local function directory(ctx, path)
  local dir = assert(rex.block.call("com.superlogical.terminal", "list_dir", {
    block_id = ctx.block_id,
    path = path or "",
    limit = 1,
  }))
  if dir.status ~= "ok" then
    error("Directory unavailable: " .. dir.path, 0)
  end
  return dir.path
end

local function show_window(ctx, session, window)
  local selection = { session_id = session, window_id = window }
  local client = assert(rex.call("client.inspect", { client_id = ctx.client_id }))
  if client.client.info and client.client.info.kind == "app" then
    assert(rex.call("client.perform", {
      client_id = ctx.client_id,
      action = "session.select",
      args = selection,
      origin = ctx.origin,
    }))
  else
    rex.client.queue("session.select", selection)
  end
end

rex.action({
  name = "new_folder_session",
  title = "New Session from Current Directory",
  category = "Session",
  args = { directory = "string?" },
  run = function(ctx, args)
    local root = directory(ctx, args.directory)
    local created = assert(rex.call("session.create", {
      label = root:match("([^/]+)/*$") or "/",
      initial_windows = {
        {
          layout = rex.layout.block({
            flavor = "com.superlogical.terminal.shell",
            options = { cwd = root },
          }),
        },
      },
    }))
    sql("INSERT OR REPLACE INTO session_roots VALUES (" .. quote(created.session_id) .. "," .. quote(root) .. ")")
    show_window(ctx, created.session_id, created.initial_windows[1].window_id)
    return created
  end,
})

rex.action({
  name = "set_session_root",
  title = "Set Session Root to Current Directory",
  category = "Session",
  args = { directory = "string?" },
  run = function(ctx, args)
    assert(ctx.session_id, "Select a session first")
    local root = directory(ctx, args.directory)
    sql("INSERT OR REPLACE INTO session_roots VALUES (" .. quote(ctx.session_id) .. "," .. quote(root) .. ")")
    return { root = root }
  end,
})

rex.action({
  name = "new_session_tab",
  title = "New Tab at Session Root",
  category = "Tab",
  run = function(ctx)
    assert(ctx.session_id, "Select a session first")
    local rows = sql("SELECT root FROM session_roots WHERE session_id = " .. quote(ctx.session_id))
    if #rows == 0 then
      rex.client.queue("client.tab.new")
      return
    end
    local root = rows[1].root
    assert(type(root) == "string" and root:sub(1, 1) == "/", "Invalid saved session root")
    local result = assert(rex.exec({ "test", "-d", root }))
    assert(result.ok, "Session root is unavailable: " .. root)
    local window = assert(rex.session.new_window({
      layout = rex.layout.block({
        flavor = "com.superlogical.terminal.shell",
        options = { cwd = root },
      }),
    }))
    show_window(ctx, ctx.session_id, window.window_id)
    return window
  end,
})

-- shortcut: built-in menus and the + button bypass this; use Cmd+T or this action.
rex.bind("cmd+t", "new_session_tab")
