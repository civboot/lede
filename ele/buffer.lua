local civ  = require'civ':grequire()
local T = require'ele.types'
local motion  = require'ele.motion'
local gap  = require'ele.gap'

local M = {}
local add = table.insert
local Buffer, Change, ChangeStart = T.Buffer, T.Change, T.ChangeStart

local function redoRm(ch, b)
  local len = #ch.s - 1; if len < 0 then return ch end
  local l2, c2 = b.gap:offset(len, ch.l, ch.c)
  b.gap:remove(ch.l, ch.c, l2, c2)
  return ch
end

local function redoIns(ch, b)
  b.gap:insert(ch.s, ch.l, ch.c)
  return ch
end

local CHANGE_REDO = { ins=redoIns, rm=redoRm, }
local CHANGE_UNDO = { ins=redoRm, rm=redoIns, }

methods(Buffer, {
new=function(s)
  return Buffer{
    gap=T.Gap.new(s),
    changes=List{}, changeMax=0,
    changeStartI=0, changeI=0,
  }
end,

addChange=function(b, ch)
  b.changeI = b.changeI + 1; b.changeMax = b.changeI
  b.changes[b.changeI] = ch
  return ch
end,
discardUnusedStart=function(b)
  if b.changeI ~= 0 and b.changeStartI == b.changeI then
    local ch = b.changes[b.changeI]
    assert(ty(ch) == ChangeStart)
    b.changeI = b.changeI - 1
    b.changeMax = b.changeI
    b.changeStartI = 0
  end
end,
changeStart=function(b, l, c)
  local ch = ChangeStart{l1=l, c1=c}
  b:discardUnusedStart()
  b:addChange(ch); b.changeStartI = b.changeI
  return ch
end,
getStart=function(b)
  if b.changeStartI <= b.changeMax then
    return b.changes[b.changeStartI]
  end
end,
printChanges=function(b)
  for i=1,b.changeMax do
    pnt(b.changes[i], (i == b.changeI) and "<-- changeI" or "")
  end
end,

changeIns=function(b, s, l, c)
  return b:addChange(Change{k='ins', s=s, l=l, c=c})
end,
changeRm=function(b, s, l, c)
  return b:addChange(Change{k='rm', s=s, l=l, c=c})
end,

canUndo=function(b) return b.changeI >= 1 end,
-- TODO: shouldn't it be '<=' ?
canRedo=function(b) return b.changeI < b.changeMax end,

undoTop=function(b)
  if b:canUndo() then return b.changes[b.changeI] end
end,
redoTop=function(b)
  if b:canRedo() then return b.changes[b.changeI + 1] end
end,

undo=function(b)
  local ch = b:undoTop(); if not ch then return end
  b:discardUnusedStart(); b.changeStartI = 0

  local done = {}
  while ch do
    b.changeI = b.changeI - 1
    add(done, ch)
    if ty(ch) == ChangeStart then break
    else
      assert(ty(ch) == Change)
      CHANGE_UNDO[ch.k](ch, b)
    end
    ch = b:undoTop()
  end
  local o = civ.reverse(done)
  return o
end,

redo=function(b)
  local ch = b:redoTop(); if not ch then return end
  b:discardUnusedStart(); b.changeStartI = 0
  assert(ty(ch) == ChangeStart)
  local done = {ch}; b.changeI = b.changeI + 1
  ch = b:redoTop(); assert(ty(ch) ~= ChangeStart)
  while ch and ty(ch) ~= ChangeStart do
    b.changeI = b.changeI + 1
    add(done, ch)
    CHANGE_REDO[ch.k](ch, b)
    ch = b:redoTop()
  end
  return done
end,

append=function(b, s)
  local ch = b:changeIns(s, b.gap:len() + 1, 1)
  b.gap:append(s)
  return ch
end,

insert=function(b, s, l, c)
  l, c = b.gap:bound(l, c)
  local ch = b:changeIns(s, l, c)
  b.gap:insert(s, l, c)
  return ch
end,

remove=function(b, ...)
  local l, c, l2, c2 = gap.lcs(...)
  local lt, ct = motion.topLeft(l, c, l2, c2)
  lt, ct = b.gap:bound(lt, ct)
  local ch = b.gap:sub(l, c, l2, c2)
  ch = (type(ch)=='string' and ch) or table.concat(ch, '\n')
  ch = b:changeRm(ch, lt, ct)
  b.gap:remove(l, c, l2, c2)
  return ch
end,
}) -- END Buffer methods

ChangeStart.__tostring = function(c)
  return string.format('[%s.%s -> %s.%s]', c.l1, c.c1, c.l2, c.c2)
end
Change.__tostring = function(c)
  return string.format('{%s %s.%s %q}', c.k, c.l, c.c, c.s)
end

return M
