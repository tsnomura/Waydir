-- Fills the marked items (or the cursor item) into a command template and
-- types the result into the built-in terminal without pressing Enter, so
-- the command can be checked and edited before it runs.
--
-- Each .json file next to this one (except manifest.json) is one entry in
-- the "Send to terminal" submenu; the file name (without .json) is its id,
-- and entries are sorted by it.
-- See README.md for the fields. Builders below handle the commands a
-- placeholder string can't express.

local GROUP = "Send to terminal"

local function is_windows_path(path)
  return path:match("^%a:[\\/]") ~= nil or path:match("^\\\\") ~= nil
end

local function cmd_quote(s)
  return '"' .. s:gsub('"', '""') .. '"'
end

local function posix_quote(s)
  if s == "" then return "''" end
  if not s:find("[%s'\"`$\\|&;()<>*?!%[%]{}]") then return s end
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function basename(path)
  return (path:gsub("[/\\]+$", ""):match("([^/\\]+)$")) or path
end

local function dirname(path)
  local trimmed = path:gsub("[/\\]+$", "")
  local parent = trimmed:match("^(.*)[/\\][^/\\]*$")
  if parent == nil then return trimmed end
  if parent == "" then return "/" end
  if parent:match("^%a:$") then return parent .. "\\" end
  return parent
end

local function join(dir, name)
  local sep = is_windows_path(dir) and "\\" or "/"
  return (dir:gsub("[/\\]+$", "")) .. sep .. name
end

local function on_windows(ctx)
  if is_windows_path(ctx.dir) then return true end
  if ctx.other_pane and is_windows_path(ctx.other_pane.dir) then return true end
  for _, path in ipairs(ctx.paths) do
    if is_windows_path(path) then return true end
  end
  return false
end

local function scp_spec(path)
  local rest = path:match("^sftp://(.*)$")
  if not rest then return path, nil end
  local authority, remote = rest:match("^([^/]*)(.*)$")
  local user, hostport = authority:match("^(.*)@(.*)$")
  hostport = hostport or authority
  local host, port = hostport:match("^(.*):(%d+)$")
  host = host or hostport
  local prefix = user and user ~= "" and (user .. "@") or ""
  if remote == "" then remote = "/" end
  return prefix .. host .. ":" .. remote, port
end

local function with_flags(parts, flags)
  if flags and flags ~= "" then parts[#parts + 1] = flags end
  return table.concat(parts, " ")
end

local BUILDERS = {}

function BUILDERS.robocopy(t, h)
  local flags = t.flags or "/MT:8 /Z"
  local commands = {}
  local files = {}
  local order = {}
  for _, item in ipairs(h.items) do
    if item.is_dir then
      commands[#commands + 1] = with_flags({
        "robocopy",
        h.q(item.path),
        h.q(join(h.dest, item.name)),
        "/E",
      }, flags)
    else
      if not files[item.parent] then
        files[item.parent] = {}
        order[#order + 1] = item.parent
      end
      table.insert(files[item.parent], h.q(item.name))
    end
  end
  for _, parent in ipairs(order) do
    commands[#commands + 1] = with_flags({
      "robocopy",
      h.q(parent),
      h.q(h.dest),
      table.concat(files[parent], " "),
    }, flags)
  end
  return table.concat(commands, " && ")
end

function BUILDERS.scp(t, h)
  local port
  local specs = {}
  for _, item in ipairs(h.items) do
    local spec, p = scp_spec(item.path)
    port = port or p
    specs[#specs + 1] = h.q(spec)
  end
  local dest, p = scp_spec(h.dest)
  port = port or p
  local parts = { "scp" }
  local flags = t.flags or "-r -C"
  if flags ~= "" then parts[#parts + 1] = flags end
  if port and port ~= "22" then parts[#parts + 1] = "-P " .. port end
  parts[#parts + 1] = table.concat(specs, " ")
  parts[#parts + 1] = h.q(dest)
  return table.concat(parts, " ")
end

local function lookup_dirs(paths)
  local dirs = {}
  local listed = {}
  for _, path in ipairs(paths) do
    local parent = dirname(path)
    if not listed[parent] and not parent:match("^%a+://") then
      listed[parent] = true
      local ok, entries = pcall(waydir.list, parent)
      if ok and entries then
        for _, e in ipairs(entries) do
          dirs[e.path] = e.is_dir
        end
      end
    end
  end
  return dirs
end

local function fill(template, values)
  return (template:gsub("{(%w+)}", function(key)
    return values[key]
  end))
end

local function build(t, ctx)
  local style = t.quote or (on_windows(ctx) and "cmd" or "posix")
  local q = style == "cmd" and cmd_quote or posix_quote
  local dest = (ctx.other_pane and ctx.other_pane.dir) or ctx.dir
  local dirs = lookup_dirs(ctx.paths)
  local items = {}
  for _, path in ipairs(ctx.paths) do
    items[#items + 1] = {
      path = path,
      name = basename(path),
      parent = dirname(path),
      is_dir = dirs[path] == true,
    }
  end

  if t.builder then
    return BUILDERS[t.builder](t, { items = items, dest = dest, q = q })
  end

  local quoted = {}
  for _, item in ipairs(items) do
    quoted[#quoted + 1] = q(item.path)
  end
  local base = { paths = table.concat(quoted, " "), dest = q(dest), dir = q(ctx.dir) }
  if not t.each then
    return fill(t.command, base)
  end
  local parts = {}
  for _, item in ipairs(items) do
    parts[#parts + 1] = fill(t.command, {
      paths = base.paths,
      dest = base.dest,
      dir = base.dir,
      path = q(item.path),
      name = q(item.name),
      parent = q(item.parent),
    })
  end
  return table.concat(parts, t.join or " && ")
end

local function load_templates()
  local ok, entries = pcall(waydir.list, waydir.plugin_dir)
  if not ok or not entries then return {} end
  table.sort(entries, function(a, b) return a.name < b.name end)
  local templates = {}
  for _, entry in ipairs(entries) do
    local id = entry.name:match("^(.+)%.json$")
    if id and id ~= "manifest" and not entry.is_dir then
      local parsed, t = pcall(function()
        return waydir.json_decode(waydir.read_text(entry.path))
      end)
      local usable = parsed and type(t) == "table" and type(t.title) == "string"
        and (type(t.command) == "string" or BUILDERS[t.builder] ~= nil)
      if usable then
        t.id = id
        templates[#templates + 1] = t
      else
        waydir.log("send-to-terminal: skipped " .. entry.name)
      end
    end
  end
  return templates
end

for _, t in ipairs(load_templates()) do
  waydir.register({
    id = t.id,
    group = GROUP,
    title = t.title,
    icon = "terminal",
    when = t.when or { min = 1, in_archive = false },
    run = function(ctx)
      if ctx.count == 0 then return end
      local windows = on_windows(ctx)
      if (t.os == "windows" and not windows) or (t.os == "unix" and windows) then
        waydir.toast(t.title .. " is for " .. t.os)
        return
      end
      waydir.terminal({
        input = build(t, ctx),
        cwd = t.cwd,
        shell = t.shell,
      })
    end,
  })
end
