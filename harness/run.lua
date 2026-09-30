-- Command-file driven MAME harness for SNES games.
-- Env HARNESS_CMDS = command file. See docs/harness.md for the command list.
-- Line format: <frame> <command> [args]. Frames count from script start;
-- commands run in frame order (stable for equal frames). '#' starts a comment.
if HARNESS_LOADED then return end   -- soft_reset re-runs autoboot scripts
HARNESS_LOADED = true

local cmds = {}
for line in io.lines(os.getenv("HARNESS_CMDS")) do
  line = line:gsub("#.*$", "")
  local fr, rest = line:match("^%s*(%d+)%s+(.-)%s*$")
  if fr then table.insert(cmds, {f = tonumber(fr), c = rest, i = #cmds + 1}) end
end
table.sort(cmds, function(a, b) if a.f ~= b.f then return a.f < b.f end return a.i < b.i end)

local machine = manager.machine
local cpu = machine.devices[":maincpu"]
local mem = cpu.spaces["program"]
local fields = {}
for name, field in pairs(machine.ioport.ports[":ctrl1:joypad:JOYPAD"].fields) do
  local b = name:match("^P1 (%w+)$")
  if b then fields[b] = field end
end

local held = {}      -- button -> frames remaining
local frame = 0
local idx = 1
local logs = {}      -- open files, closed on exit
local taps = {}      -- tap handles must stay referenced or they are collected
local pins = nil     -- addr -> byte, rewritten every frame
local auto = nil     -- steering autopilot state
local bplog = nil
local bp_on = false

local function hex(s) return tonumber(s, 16) end
local function pc() return cpu.state["CURPC"].value end

-- Low WRAM ($7E0000-$7E1FFF) is mirrored at $0000-$1FFF of banks $00-$3F and
-- $80-$BF, and games usually write it through a mirror. Tap all of them.
local function tap_write(a, n, name, cb)
  taps[#taps + 1] = mem:install_write_tap(a, a + n - 1, name, cb)
  if a >= 0x7E0000 and a + n <= 0x7E2000 then
    local lo = a & 0xFFFF
    for _, base in ipairs({0x00, 0x80}) do
      for b = base, base + 0x3F do
        local s = (b << 16) | lo
        taps[#taps + 1] = mem:install_write_tap(s, s + n - 1, name .. "_" .. b, cb)
      end
    end
  end
end

local function dump(a, n, path)
  local fh = io.open(path, "wb")
  for i = 0, n - 1 do fh:write(string.char(mem:read_u8(a + i))) end
  fh:close()
end

local function run(c)
  local w = {}
  for t in c:gmatch("%S+") do table.insert(w, t) end
  local op = w[1]
  if op == "hold" then                 -- hold <frames> <Btn[,Btn...]>
    for b in w[3]:gmatch("[^,]+") do held[b] = tonumber(w[2]) end
  elseif op == "snap" then             -- snap
    machine.video:snapshot()
  elseif op == "dump" then             -- dump <addr> <len> <file>
    dump(hex(w[2]), hex(w[3]), w[4])
  elseif op == "loadbin" then          -- loadbin <addr> <file> [skip]
    local fh = io.open(w[3], "rb"); local data = fh:read("a"); fh:close()
    local a, skip = hex(w[2]), tonumber(w[4] or "0")
    for i = 1 + skip, #data do mem:write_u8(a + i - 1 - skip, data:byte(i)) end
  elseif op == "poke" then             -- poke <addr> <byte>
    mem:write_u8(hex(w[2]), hex(w[3]))
  elseif op == "pin" then              -- pin <addr> <byte>: rewrite every frame
    pins = pins or {}
    pins[hex(w[2])] = hex(w[3])
  elseif op == "unpin" then
    pins = nil
  elseif op == "save" then             -- save <name> (MAME state)
    machine:save(w[2])
  elseif op == "load" then             -- load <name>
    machine:load(w[2])
  elseif op == "reset" then
    machine:soft_reset()
  elseif op == "hardreset" then
    machine:hard_reset()
  elseif op == "watch" then            -- watch <addr> <len> <file>
    local fh = io.open(w[4], "w"); table.insert(logs, fh)
    tap_write(hex(w[2]), hex(w[3]), "watch" .. w[2] .. "_" .. frame, function(off, data)
      fh:write(string.format("%d %06X %06X %02X\n", frame, pc(), off, data & 0xFF))
      return data
    end)
  elseif op == "stackon" then          -- stackon <addr> <file> [peek...]
    -- On each write to addr: frame, PC, S, 8 bytes above S (return addresses)
    -- and the 16-bit values at the optional peek addresses.
    local fh = io.open(w[3], "w"); table.insert(logs, fh)
    local peeks = {}
    for i = 4, #w do peeks[#peeks + 1] = hex(w[i]) end
    tap_write(hex(w[2]), 1, "stack" .. w[2] .. "_" .. frame, function(off, data)
      local sp = cpu.state["S"].value
      local t = {}
      for i = 1, 8 do t[#t + 1] = string.format("%02X", mem:read_u8(sp + i)) end
      for _, p in ipairs(peeks) do t[#t + 1] = string.format("%06X=%04X", p, mem:read_u16(p)) end
      fh:write(string.format("%d %06X S=%04X %s\n", frame, pc(), sp, table.concat(t, " ")))
      return data
    end)
  elseif op == "dumpon" then           -- dumpon <addr> <prefix> [start len]
    local s, n = hex(w[4] or "7E0000"), hex(w[5] or "2000")
    local pre = w[3]
    tap_write(hex(w[2]), 1, "dumpon" .. w[2] .. "_" .. frame, function(off, data)
      dump(s, n, string.format("%s_%d.bin", pre, frame))
      return data
    end)
  elseif op == "bp" then               -- bp <addr>: log frame when PC hits (DEBUG=1)
    bplog = bplog or io.open(os.getenv("HARNESS_BPLOG") or "bp.log", "w")
    cpu.debug:bpset(hex(w[2]), "1", "")
    bp_on = true
  elseif op == "auto" then             -- auto <addr> <frames> [target] [band] [gas] [invert]
    -- Steer to keep the signed word at addr near target, holding the gas
    -- button. Left lowers the value unless 'invert' is given.
    auto = {addr = hex(w[2]), n = tonumber(w[3]), tgt = tonumber(w[4] or "0"),
            band = tonumber(w[5] or "15"), gas = w[6] or "X", inv = w[7] == "invert"}
  elseif op == "exit" then
    for _, fh in ipairs(logs) do fh:close() end
    if bplog then bplog:close() end
    machine:exit()
  else
    print("harness: unknown command: " .. c)
  end
end

emu.register_periodic(function()
  if bp_on and machine.debugger and machine.debugger.execution_state == "stop" then
    bplog:write(string.format("%d %06X\n", frame, pc())); bplog:flush()
    machine.debugger.execution_state = "run"
  end
end)

emu.register_frame_done(function()
  while idx <= #cmds and cmds[idx].f <= frame do run(cmds[idx].c); idx = idx + 1 end
  if pins then for a, v in pairs(pins) do mem:write_u8(a, v) end end
  if auto and auto.n > 0 then
    auto.n = auto.n - 1
    local v = mem:read_u16(auto.addr); if v >= 0x8000 then v = v - 0x10000 end
    local lo, hi = "Left", "Right"
    if auto.inv then lo, hi = hi, lo end
    held[auto.gas] = 1
    if v > auto.tgt + auto.band then held[lo] = 1 elseif v < auto.tgt - auto.band then held[hi] = 1 end
  end
  for b, field in pairs(fields) do
    if held[b] and held[b] > 0 then field:set_value(1); held[b] = held[b] - 1 else field:clear_value() end
  end
  frame = frame + 1
end)
