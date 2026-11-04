-- Json.lua
-- Turns Lua tables into JSON text, the format the Ledger's Import box reads.
-- WoW has no built-in JSON encoder, so we write a small one.

-- Every file in an addon receives two values through "...":
-- the addon's folder name and a private table shared by all its files.
-- We call the table "ns" (namespace) and hang our modules on it,
-- so nothing leaks into the global space other addons share.
local _, ns = ...

local Json = {}
ns.Json = Json

-- Lua uses one kind of table for both lists ({1, 2, 3}) and records
-- ({name = "x"}). JSON needs to know which is which, and an empty table
-- could be either. Json.array({}) tags a table so it always prints as [].
local ARRAY = {}

function Json.array(t)
  return setmetatable(t or {}, ARRAY)
end

local function isArray(t)
  if getmetatable(t) == ARRAY then return true end
  if next(t) == nil then return false end   -- empty, untagged: treat as {}
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count == #t                        -- only keys 1..n means a list
end

-- Characters that must be escaped inside a JSON string.
local ESCAPES = {
  ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
  ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}

local function encodeString(s)
  -- %c matches control characters. gsub calls our function for each match.
  s = s:gsub('[%c"\\]', function(c)
    return ESCAPES[c] or string.format("\\u%04x", c:byte())
  end)
  return '"' .. s .. '"'
end

local function encodeNumber(n)
  if n ~= n or n == math.huge or n == -math.huge then
    return "null"                           -- JSON has no NaN or infinity
  end
  if n == math.floor(n) then
    return string.format("%.0f", n)         -- whole numbers without ".0"
  end
  return string.format("%.14g", n)
end

-- Sorts record keys: keys listed in `order` come first in that order,
-- anything else follows alphabetically. This keeps the export readable.
local function sortedKeys(t, order)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    local ra, rb = order[a], order[b]
    if ra and rb then return ra < rb end
    if ra then return true end
    if rb then return false end
    return tostring(a) < tostring(b)
  end)
  return keys
end

local encode   -- declared first so the function can call itself

encode = function(value, order, out)
  local kind = type(value)
  if kind == "nil" then
    out[#out + 1] = "null"
  elseif kind == "boolean" then
    out[#out + 1] = value and "true" or "false"
  elseif kind == "number" then
    out[#out + 1] = encodeNumber(value)
  elseif kind == "string" then
    out[#out + 1] = encodeString(value)
  elseif kind == "table" then
    if isArray(value) then
      out[#out + 1] = "["
      for i = 1, #value do
        if i > 1 then out[#out + 1] = "," end
        encode(value[i], order, out)
      end
      out[#out + 1] = "]"
    else
      out[#out + 1] = "{"
      for i, k in ipairs(sortedKeys(value, order)) do
        if i > 1 then out[#out + 1] = "," end
        out[#out + 1] = encodeString(tostring(k))
        out[#out + 1] = ":"
        encode(value[k], order, out)
      end
      out[#out + 1] = "}"
    end
  else
    out[#out + 1] = "null"                  -- functions etc. can't be JSON
  end
end

-- Json.encode(value, keyOrder) returns a JSON string.
-- keyOrder is an optional list like {"name", "level"}.
function Json.encode(value, keyOrder)
  local order = {}
  for i, k in ipairs(keyOrder or {}) do order[k] = i end
  local out = {}
  encode(value, order, out)
  -- Collecting pieces in a table and joining once is much faster
  -- than gluing strings together with .. in a loop.
  return table.concat(out)
end
