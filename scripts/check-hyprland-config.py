#!/usr/bin/env python3
"""Validate archiso/airootfs/etc/skel/.config/hypr/hyprland.lua against the Hyprland
version that is currently in the Arch Linux repositories.

  scripts/check-hyprland-config.py [--version 0.57.1] [--lua lua5.4]

* downloads that version's sources from GitHub (only the needed files)
* extracts every config option with its type, every hl.* function, every
  hl.dsp.* dispatcher and every hl.on() event name
* runs hyprland.lua in a real Lua interpreter against a strict stub of that API:
  calling something that does not exist fails, every hl.config() option is
  checked for existence and type, hl.on() callbacks are executed too
Needs a Lua interpreter (lua5.4 / lua). Exit code 1 on any problem.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, "archiso", "airootfs", "etc", "skel", ".config", "hypr", "hyprland.lua")
REPO = "https://github.com/hyprwm/Hyprland"
UA = {"User-Agent": "huilo-check-hyprland-config"}


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return r.read().decode()


def arch_version():
    data = json.loads(get("https://archlinux.org/packages/extra/x86_64/hyprland/json/"))
    return data["pkgver"]


def fetch_sources(ver, dest):
    subprocess.run(["git", "clone", "-q", "--depth", "1", "--branch", f"v{ver}", "--filter=blob:none",
                    "--sparse", REPO, dest], check=True)
    subprocess.run(["git", "-C", dest, "sparse-checkout", "set", "src/config"], check=True)


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def extract_api(src):
    cfg = os.path.join(src, "src", "config")
    # Lua option names are derived like CConfigManager::luaConfigValueName():
    # "input:touchpad:tap-to-click" -> "input.touchpad.tap_to_click"
    options = {name.replace(":", ".").replace("-", "_"): kind
               for kind, name in re.findall(r'MS<(\w+)>\("([^"]+)"', read(os.path.join(cfg, "values", "ConfigValues.cpp")))}

    # hl.dsp.*: setDispatcherFn() entries belong to the table closed by the next lua_setfield(L, -2, "<name>")
    disp = read(os.path.join(cfg, "lua", "bindings", "LuaBindingsDispatchers.cpp"))
    reg = disp[disp.index("registerDispatcherBindings"):]
    dsp, pending = {}, []
    for m in re.finditer(r'setDispatcherFn\(L, "(\w+)"|lua_setfield\(L, -2, "(\w+)"\)', reg):
        if m.group(1):
            pending.append(m.group(1))
        else:
            dsp["" if m.group(2) == "dsp" else m.group(2)] = pending
            pending = []

    # hl.*: every setFn/setMgrFn in the binding sources
    top = set()
    bdir = os.path.join(cfg, "lua", "bindings")
    for f in os.listdir(bdir):
        if f.endswith(".cpp"):
            top.update(re.findall(r'set(?:Mgr)?Fn\(L, (?:mgr, )?"(\w+)"', read(os.path.join(bdir, f))))

    events = set(re.findall(r'dispatch\("([a-z_.]+)"', read(os.path.join(cfg, "lua", "LuaEventHandler.cpp"))))
    return options, dsp, sorted(top), sorted(events)


STUB = r'''
local API_TOP, API_DSP, EVENTS = ...
local errors, configs = {}, {}
local function err(msg) errors[#errors + 1] = msg end
local function where()
  local info = debug.getinfo(3, "Sl")
  return info and (info.short_src .. ":" .. (info.currentline or 0)) or "?"
end
local function strict(name, t)
  return setmetatable(t, { __index = function(_, k) error("unknown " .. name .. "." .. tostring(k), 2) end })
end
local token_mt = {}
local dsp = {}
for sub, fns in pairs(API_DSP) do
  local target = dsp
  if sub ~= "" then target = {} ; dsp[sub] = target end
  for _, fn in ipairs(fns) do
    local full = "hl.dsp." .. (sub ~= "" and (sub .. ".") or "") .. fn
    target[fn] = function(...) return setmetatable({ name = full }, token_mt) end
  end
end
for sub, t in pairs(dsp) do if type(t) == "table" and getmetatable(t) == nil then strict("hl.dsp." .. sub, t) end end
strict("hl.dsp", dsp)

local hl = { dsp = dsp }
local known_events = {}
for _, e in ipairs(EVENTS) do known_events[e] = true end
for _, fn in ipairs(API_TOP) do
  hl[fn] = function(...) return setmetatable({}, { __index = function() return function() end end }) end
end
hl.config = function(t)
  if type(t) ~= "table" then err(where() .. ": hl.config expects a table") return end
  configs[#configs + 1] = { where = where(), tbl = t }
end
hl.bind = function(keys, action, opts)
  if type(keys) ~= "string" then err(where() .. ": hl.bind: keys must be a string") end
  if type(action) ~= "function" and getmetatable(action) ~= token_mt then
    err(where() .. ": hl.bind(" .. tostring(keys) .. "): second argument is not a dispatcher")
  end
  if opts ~= nil and type(opts) ~= "table" then err(where() .. ": hl.bind: options must be a table") end
end
hl.on = function(event, fn)
  if not known_events[event] then err(where() .. ": hl.on: unknown event '" .. tostring(event) .. "'") end
  if type(fn) ~= "function" then err(where() .. ": hl.on: callback is not a function") return end
  local ok, e = pcall(fn)
  if not ok then err("in hl.on('" .. tostring(event) .. "') callback: " .. tostring(e)) end
end
_G.hl = strict("hl", hl)

local function js(s)
  return '"' .. (tostring(s):gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end)) .. '"'
end
local function ser(v)
  local t = type(v)
  if t == "table" then
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = js(k) .. ":" .. ser(x) end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "number" then
    return string.format('{"t":"%s","v":%s}', math.type(v) == "integer" and "int" or "float", string.format("%.17g", v))
  elseif t == "boolean" then
    return string.format('{"t":"bool","v":%s}', tostring(v))
  elseif t == "string" then
    return '{"t":"str","v":' .. js(v) .. '}'
  end
  return '{"t":' .. js(t) .. '}'
end

local cfg = os.getenv("HYPR_CONFIG")
package.path = cfg:match("(.*/)") .. "?.lua;" .. package.path
local chunk, perr = loadfile(cfg)
if not chunk then err("syntax: " .. tostring(perr)) else
  local ok, e = pcall(chunk)
  if not ok then err("runtime: " .. tostring(e)) end
end
local out = {}
for _, c in ipairs(configs) do out[#out + 1] = '{"where":' .. js(c.where) .. ',"tbl":' .. ser(c.tbl) .. '}' end
local errs = {}
for _, e in ipairs(errors) do errs[#errs + 1] = js(e) end
io.write('{"errors":[' .. table.concat(errs, ",") .. '],"configs":[' .. table.concat(out, ",") .. "]}")
'''


def lua_list(items):
    return "{" + ",".join('"%s"' % i for i in items) + "}"


def type_ok(kind, val):
    t = val.get("t") if isinstance(val, dict) else "table"
    if kind == "Int":
        return t == "int"
    if kind == "Float":
        return t in ("int", "float")
    if kind == "Bool":
        return t == "bool" or (t == "int" and val["v"] in (0, 1))
    if kind == "String":
        return t == "str"
    if kind == "Gradient":
        return t in ("str", "int") or t == "table"
    if kind in ("CssGap", "Vec2"):
        return t in ("int", "float", "str", "table")
    return True


def walk(tree, options, path, where, problems):
    for key, val in tree.items():
        p = path + [key]
        name = ".".join(p)
        is_leaf = isinstance(val, dict) and set(val) <= {"t", "v"} and "t" in val
        if name in options:
            if not type_ok(options[name], val if is_leaf else "table"):
                problems.append(f"{where}: {name} expects {options[name]}, got {val.get('t') if is_leaf else 'table'}")
        elif not is_leaf and isinstance(val, dict) and any(o.startswith(name + ".") for o in options):
            walk(val, options, p, where, problems)
        else:
            problems.append(f"{where}: unknown option {name}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version")
    ap.add_argument("--lua", default=shutil.which("lua5.4") or shutil.which("lua") or "lua")
    ap.add_argument("--config", default=CONFIG)
    args = ap.parse_args()

    ver = args.version or arch_version()
    print(f":: Hyprland {ver} (Arch repository)")
    with tempfile.TemporaryDirectory() as src:
        fetch_sources(ver, os.path.join(src, "hyprland"))
        options, dsp, top, events = extract_api(os.path.join(src, "hyprland"))
    print(f":: API: {len(options)} options, {sum(map(len, dsp.values()))} dispatchers, {len(top)} hl.* functions, {len(events)} events")
    if not options or not top:
        print("cannot extract the Hyprland API — source layout changed?")
        return 1

    dsp_lua = "{" + ",".join('["%s"]=%s' % (k, lua_list(v)) for k, v in dsp.items()) + "}"
    with tempfile.TemporaryDirectory() as tmp:
        stub = os.path.join(tmp, "stub.lua")
        with open(stub, "w") as f:
            f.write("local args = { %s, %s, %s }\n" % (lua_list(top), dsp_lua, lua_list(events)))
            f.write(STUB.replace("local API_TOP, API_DSP, EVENTS = ...", "local API_TOP, API_DSP, EVENTS = args[1], args[2], args[3]"))
        env = dict(os.environ, HYPR_CONFIG=os.path.abspath(args.config))
        res = subprocess.run([args.lua, stub], capture_output=True, text=True, env=env)
        if res.returncode != 0:
            print(res.stdout, res.stderr)
            return 1
        data = json.loads(res.stdout)

    problems = list(data["errors"])
    for c in data["configs"]:
        walk(c["tbl"], options, [], c["where"], problems)
    if problems:
        print("ERRORS:")
        for p in problems:
            print("  " + p)
        return 1
    print(f"OK: {os.path.relpath(args.config, ROOT)} — {len(data['configs'])} hl.config blocks valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
