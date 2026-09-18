-- Read the effective Hyprland binds out of the user's Lua config.
--
--   lua notch-setup-binds.lua            one JSON object per line, on stdout
--
-- Hyprland's `hyprctl binds -j` can't tell us where a bind came from, and it
-- reports keycodes rather than the `code:201` the config was written with. The
-- only way to know what a config *means* is to run it, so this does what
-- Omarchy's own keybindings menu does: it loads the real hyprland.lua with a
-- recording stand-in for the `hl` table Hyprland normally provides, and writes
-- down every bind, unbind and layer rule as it happens.
--
-- Nothing is applied: `hl` here only records. It is still the user's Lua, so it
-- runs whatever the config runs at load (Omarchy itself shells out to `find`
-- while listing its module folders) -- this is read-only, but it is not inert.
--
-- Lines:
--   {"bind": {...}}      an effective bind, after unbinds were applied
--   {"unbind": "..."}    a key the config unbound
--   {"layerRule": {...}} hl.layer_rule(rule, namespace)
--   {"marker": "hypr.bindings-end", "seq": n}
--   {"error": "..."}     the config raised; whatever was recorded still prints
--
-- Environment:
--   NOTCH_SETUP_HOME                 the HOME whose config is read
--   NOTCH_SETUP_OMARCHY_PATH         Omarchy's tree
--   NOTCH_SETUP_BINDINGS_OVERRIDE    load this file in place of `hypr.bindings`
--                                    (used to check a candidate before it is
--                                    written)

local home = os.getenv("NOTCH_SETUP_HOME") or os.getenv("HOME") or ""
local omarchy = os.getenv("NOTCH_SETUP_OMARCHY_PATH") or os.getenv("OMARCHY_PATH") or "/usr/share/omarchy"
local override = os.getenv("NOTCH_SETUP_BINDINGS_OVERRIDE")

-- Omarchy's own modules read these, so the stub has to agree with the tree it
-- is reading. Both are restored to the process's real values by the caller's
-- environment, never written back here.
local out = {}
local seq = 0

local function json_string(value)
  local text = tostring(value or "")
  text = text:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    if c == "\n" then return "\\n" end
    if c == "\t" then return "\\t" end
    if c == "\r" then return "\\r" end
    return string.format("\\u%04x", string.byte(c))
  end)
  return '"' .. text .. '"'
end

local function json(value)
  local kind = type(value)
  if kind == "string" then return json_string(value) end
  if kind == "number" then return string.format("%d", value) end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "nil" then return "null" end
  if kind ~= "table" then return json_string(tostring(value)) end
  if #value > 0 then
    local parts = {}
    for _, item in ipairs(value) do parts[#parts + 1] = json(item) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do
    parts[#parts + 1] = json_string(key) .. ":" .. json(value[key])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function emit(line) out[#out + 1] = line end

-- "SUPER + SHIFT + code:201" -> mods {SUPER, SHIFT}, key "code:201".
local MODMASK = { SUPER = 64, CTRL = 4, CONTROL = 4, ALT = 8, SHIFT = 1 }
local function split_combo(combo)
  local parts = {}
  for raw in tostring(combo):gmatch("[^+]+") do
    local part = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if part ~= "" then parts[#parts + 1] = part end
  end
  local key = table.remove(parts) or ""
  local mask = 0
  local mods = {}
  for _, mod in ipairs(parts) do
    local upper = mod:upper()
    mods[#mods + 1] = upper
    mask = mask + (MODMASK[upper] or 0)
  end
  table.sort(mods)
  return mods, key, mask
end

local function combo_id(combo)
  local mods, key, mask = split_combo(combo)
  return mask .. "|" .. key:lower(), mods, key, mask
end

-- Where the call came from: the first frame outside this file and outside
-- Omarchy's helpers, which is the file that actually wrote the bind.
local function caller()
  for level = 3, 12 do
    local info = debug.getinfo(level, "Sl")
    if not info then break end
    local source = (info.source or ""):gsub("^@", "")
    if source ~= "" and not source:match("notch%-setup%-binds%.lua$") and not source:match("/helpers%.lua$") then
      return source, info.currentline or 0
    end
  end
  return "", 0
end

local binds = {}   -- combo id -> bind record (last one wins, as Hyprland does)
local order = {}   -- combo ids in the order they were first bound

local function record_bind(keys, dispatcher, options)
  seq = seq + 1
  local opts = options or {}
  local command = ""
  if type(dispatcher) == "table" and dispatcher.__dsp then
    command = dispatcher.__command or dispatcher.__dsp
  elseif type(dispatcher) == "string" then
    command = dispatcher
  end
  local source, line = caller()
  local id, mods, key, mask = combo_id(keys)
  if not binds[id] then order[#order + 1] = id end
  binds[id] = {
    combo = tostring(keys), key = key, mods = mods, modmask = mask,
    description = tostring(opts.description or ""), command = command,
    locked = opts.locked == true, source = source, line = line, seq = seq,
  }
end

local function record_unbind(keys)
  seq = seq + 1
  local id = combo_id(keys)
  binds[id] = nil
  emit('{"unbind":' .. json_string(tostring(keys)) .. ',"seq":' .. seq .. "}")
end

-- The stand-in for Hyprland's `hl`. Dispatchers are recorded rather than run,
-- and anything the config reaches for that isn't listed answers as a no-op so
-- the config keeps loading instead of raising.
-- Dispatchers nest (`hl.dsp.window.close()`), so each name answers both as a
-- table to index further and as a function to call.
local function proxy(name)
  return setmetatable({}, {
    __index = function(_, key) return proxy(name .. "." .. tostring(key)) end,
    __call = function(_, ...)
      local args = { ... }
      return { __dsp = name, __command = type(args[1]) == "string" and args[1] or nil }
    end,
  })
end

local dsp = setmetatable({}, { __index = function(_, name) return proxy(tostring(name)) end })

local hl_real = {
  dsp = dsp,
  bind = record_bind,
  unbind = record_unbind,
  -- Omarchy passes one table: { match = { namespace = "…" }, no_anim = true, … }.
  -- Older calls pass the rule and the namespace separately; both are flattened
  -- to "key=value" strings plus the namespace they match.
  layer_rule = function(rule, namespace)
    seq = seq + 1
    local source, line = caller()
    local ns = namespace and tostring(namespace) or ""
    local parts = {}
    if type(rule) == "table" then
      local keys = {}
      for key in pairs(rule) do keys[#keys + 1] = tostring(key) end
      table.sort(keys)
      for _, key in ipairs(keys) do
        local value = rule[key]
        if key == "match" and type(value) == "table" then
          if ns == "" and value.namespace then ns = tostring(value.namespace) end
        elseif type(value) ~= "table" and type(value) ~= "function" then
          parts[#parts + 1] = key .. "=" .. tostring(value)
        end
      end
    elseif rule ~= nil then
      parts[#parts + 1] = tostring(rule)
    end
    emit('{"layerRule":' .. json({ rule = table.concat(parts, " "), namespace = ns,
      source = source, line = line, seq = seq }) .. "}")
  end,
  on = function() end,
  timer = function() end,
  dispatch = function() end,
  exec_cmd = function(command) return { __dsp = "exec_cmd", __command = command } end,
  get_config = function() return nil end,
  get_active_window = function() return nil end,
}

hl = setmetatable(hl_real, {
  __index = function(_, name) return proxy(tostring(name)) end,
})

-- Omarchy's bootstrap sets package.path from HOME and OMARCHY_PATH; do the same
-- here so a sandbox tree is read instead of the real one.
package.path = home .. "/.local/state/?.lua;" .. home .. "/.config/?.lua;" .. omarchy .. "/?.lua;" .. package.path

-- Wrap require, so the point where the user's own bindings stop is known: a
-- block appended to bindings.lua can only override binds made before it.
local real_require = require
local bindings_end = nil
require = function(module)
  if module == "hypr.bindings" and override and override ~= "" then
    seq = seq + 1
    local chunk, err = loadfile(override)
    if not chunk then error(err, 0) end
    local value = chunk()
    seq = seq + 1
    bindings_end = seq
    return value
  end
  local value = real_require(module)
  if module == "hypr.bindings" then
    seq = seq + 1
    bindings_end = seq
  end
  return value
end

local config = home .. "/.config/hypr/hyprland.lua"
local ok, err = pcall(function() dofile(config) end)

-- A key that was unbound and bound again is in `order` twice; print it once.
local printed = {}
for _, id in ipairs(order) do
  local bind = binds[id]
  if bind and not printed[id] then
    printed[id] = true
    emit('{"bind":' .. json(bind) .. "}")
  end
end
if bindings_end then
  emit('{"marker":"hypr.bindings-end","seq":' .. bindings_end .. "}")
end
if not ok then
  emit('{"error":' .. json_string(err) .. "}")
end

print(table.concat(out, "\n"))
