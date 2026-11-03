local TITLE = "New folder from marks"

local RESERVED = {
  CON = true, PRN = true, AUX = true, NUL = true,
  COM1 = true, COM2 = true, COM3 = true, COM4 = true, COM5 = true,
  COM6 = true, COM7 = true, COM8 = true, COM9 = true,
  LPT1 = true, LPT2 = true, LPT3 = true, LPT4 = true, LPT5 = true,
  LPT6 = true, LPT7 = true, LPT8 = true, LPT9 = true,
}

local function is_windows(dir)
  return dir:match("^%a:") ~= nil or dir:sub(1, 2) == "\\\\"
end

local function join(dir, name)
  local sep = is_windows(dir) and "\\" or "/"
  if dir:sub(-1) == sep then
    return dir .. name
  end
  return dir .. sep .. name
end

local function basename(path)
  return path:match("([^/\\]+)[/\\]*$") or path
end

local function stem(name, is_dir)
  if is_dir then
    return name
  end
  return name:match("^(.+)%.[^.]+$") or name
end

local function fold(name, windows)
  return windows and name:lower() or name
end

local function validate(name, ctx, listing, targets)
  local windows = is_windows(ctx.dir)
  if name == "" then
    return "Enter a folder name."
  end
  if name:find("/", 1, true) or (windows and name:find("\\", 1, true)) then
    return "The name cannot contain a path separator."
  end
  if name == "." or name == ".." then
    return "The name cannot be . or .."
  end
  if windows then
    if name:find('[<>:"|%?%*]') then
      return 'The name cannot contain any of < > : " | ? *'
    end
    if name:match("[%s%.]$") then
      return "The name cannot end with a space or a dot."
    end
    local base = name:match("^([^.]*)") or name
    if RESERVED[base:upper()] then
      return name .. " is a reserved name on Windows."
    end
  end
  local key = fold(name, windows)
  for _, t in ipairs(targets) do
    if fold(t.name, windows) == key then
      return name .. " is one of the items being moved."
    end
  end
  for _, e in ipairs(listing) do
    if fold(e.name, windows) == key then
      if e.is_dir then
        return nil, e.name
      end
      return "A file named " .. name .. " already exists in this folder."
    end
  end
  return nil
end

local function ask(name, error_text, merge_prompt)
  local fields = {}
  if error_text then
    fields[#fields + 1] = { id = "error", type = "info", label = error_text }
  end
  fields[#fields + 1] = {
    id = "name",
    type = "input",
    label = "Folder name",
    default = name,
    select = "all",
  }
  if merge_prompt then
    fields[#fields + 1] = {
      id = "merge",
      type = "checkbox",
      label = merge_prompt,
      default = true,
    }
  end
  waydir.dialog({ title = TITLE, fields = fields })
end

local function targets_of(ctx, listing)
  local is_dir = {}
  for _, e in ipairs(listing) do
    is_dir[e.name] = e.is_dir
  end
  local out = {}
  for _, path in ipairs(ctx.paths or {}) do
    local name = basename(path)
    if name ~= ".." and name ~= "." then
      out[#out + 1] = { path = path, name = name, is_dir = is_dir[name] == true }
    end
  end
  return out
end

local function run(ctx)
  local is_local = ctx.location and ctx.location.is_local
  if is_local == nil then
    is_local = waydir.exists(ctx.dir)
  end
  if not is_local then
    waydir.notify({
      title = TITLE,
      message = "Only local folders are supported (not archives, SFTP or SMB URIs).",
      level = "warn",
    })
    return
  end
  local listing = waydir.list(ctx.dir)

  local targets = targets_of(ctx, listing)
  if #targets == 0 then
    waydir.toast("Nothing to move")
    return
  end

  if not ctx.form then
    ask(stem(targets[1].name, targets[1].is_dir))
    return
  end

  local name = ctx.form.name or ""
  local problem, existing = validate(name, ctx, listing, targets)
  if problem then
    ask(name, problem)
    return
  end
  if existing and ctx.form.merge ~= true then
    ask(
      existing,
      "The folder " .. existing .. " already exists.",
      string.format("Add the %d item(s) to the existing folder", #targets)
    )
    return
  end

  local folder = join(ctx.dir, existing or name)
  if not existing then
    waydir.mkdir(folder)
  end
  for _, t in ipairs(targets) do
    waydir.move(t.path, folder)
  end
  if waydir.focus then
    waydir.focus(folder)
  else
    waydir.refresh()
  end
end

waydir.register({
  id = "new_folder_from_marks",
  title = "New folder from marks…",
  menu = "menubar",
  icon = "folder-plus",
  run = run,
})

waydir.register({
  id = "new_folder_from_marks_context",
  title = "New folder from marks…",
  menu = "context",
  where = { "selection" },
  when = { in_archive = false },
  icon = "folder-plus",
  run = run,
})
