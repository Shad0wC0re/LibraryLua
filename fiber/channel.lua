------------------------------------------------------------------------
-- fiber.channel — Canais de comunicação entre fibers
-- Parte da biblioteca Fiber
-- 100% Lua puro | Compatível com Lua 5.3+ / 5.5
------------------------------------------------------------------------

local channel = {}
channel.__index = channel

local setmetatable = setmetatable
local coroutine_yield  = coroutine.yield
local coroutine_running = coroutine.running
local table_insert = table.insert
local table_remove = table.remove

------------------------------------------------------------------------
-- Construtor
------------------------------------------------------------------------
---@param capacity? integer  Capacidade do buffer (0 = unbuffered)
---@return table channel
function channel.new(capacity)
  return setmetatable({
    _buffer   = {},
    _capacity = capacity or 0,
    _closed   = false,
    _senders  = {},  -- Fibers esperando para enviar
    _receivers = {}, -- Fibers esperando para receber
  }, channel)
end

------------------------------------------------------------------------
-- send — Envia um valor pelo canal
------------------------------------------------------------------------
---@param value any
---@return boolean ok  false se o canal está fechado
function channel:send(value)
  if self._closed then
    return false
  end

  -- Se há receivers esperando, entrega diretamente
  if #self._receivers > 0 then
    local receiver = table_remove(self._receivers, 1)
    receiver.value = value
    receiver.ready = true
    return true
  end

  -- Se o buffer tem espaço, adiciona ao buffer
  if #self._buffer < self._capacity then
    table_insert(self._buffer, value)
    return true
  end

  -- Caso contrário, bloqueia o sender (será retomado pelo scheduler)
  local entry = { value = value, ready = false }
  table_insert(self._senders, entry)
  -- O scheduler vai yield aqui
  return not self._closed
end

------------------------------------------------------------------------
-- receive — Recebe um valor do canal
------------------------------------------------------------------------
---@return any value
---@return boolean ok  false se o canal está fechado e vazio
function channel:receive()
  -- Se há dados no buffer, retorna o primeiro
  if #self._buffer > 0 then
    local value = table_remove(self._buffer, 1)
    -- Se há senders esperando, move o valor deles para o buffer
    if #self._senders > 0 then
      local sender = table_remove(self._senders, 1)
      table_insert(self._buffer, sender.value)
      sender.ready = true
    end
    return value, true
  end

  -- Se há senders esperando, recebe diretamente
  if #self._senders > 0 then
    local sender = table_remove(self._senders, 1)
    sender.ready = true
    return sender.value, true
  end

  -- Se o canal está fechado e sem dados
  if self._closed then
    return nil, false
  end

  -- Bloqueia o receiver
  local entry = { value = nil, ready = false }
  table_insert(self._receivers, entry)
  -- O scheduler vai yield aqui e setar entry.value quando disponível
  return entry.value, not self._closed
end

------------------------------------------------------------------------
-- try_send — Tenta enviar sem bloquear
------------------------------------------------------------------------
---@param value any
---@return boolean ok
function channel:try_send(value)
  if self._closed then return false end

  if #self._receivers > 0 then
    local receiver = table_remove(self._receivers, 1)
    receiver.value = value
    receiver.ready = true
    return true
  end

  if #self._buffer < self._capacity then
    table_insert(self._buffer, value)
    return true
  end

  return false
end

------------------------------------------------------------------------
-- try_receive — Tenta receber sem bloquear
------------------------------------------------------------------------
---@return any value
---@return boolean ok
function channel:try_receive()
  if #self._buffer > 0 then
    local value = table_remove(self._buffer, 1)
    if #self._senders > 0 then
      local sender = table_remove(self._senders, 1)
      table_insert(self._buffer, sender.value)
      sender.ready = true
    end
    return value, true
  end

  if #self._senders > 0 then
    local sender = table_remove(self._senders, 1)
    sender.ready = true
    return sender.value, true
  end

  return nil, false
end

------------------------------------------------------------------------
-- close — Fecha o canal
------------------------------------------------------------------------
function channel:close()
  self._closed = true
  -- Notifica todos os receivers esperando
  for _, entry in ipairs(self._receivers) do
    entry.ready = true
  end
  -- Notifica todos os senders esperando
  for _, entry in ipairs(self._senders) do
    entry.ready = true
  end
end

------------------------------------------------------------------------
-- is_closed — Verifica se o canal está fechado
------------------------------------------------------------------------
---@return boolean
function channel:is_closed()
  return self._closed
end

------------------------------------------------------------------------
-- len — Número de itens no buffer
------------------------------------------------------------------------
---@return integer
function channel:len()
  return #self._buffer
end

return channel
