------------------------------------------------------------------------
-- fiber.scheduler — Escalonador cooperativo de coroutines
-- Parte da biblioteca Fiber
-- 100% Lua puro | Compatível com Lua 5.3+ / 5.5
------------------------------------------------------------------------

local scheduler = {}

-- Cache local
local coroutine_create  = coroutine.create
local coroutine_resume  = coroutine.resume
local coroutine_yield   = coroutine.yield
local coroutine_status  = coroutine.status
local table_insert      = table.insert
local table_remove      = table.remove
local setmetatable      = setmetatable
local pairs             = pairs
local ipairs            = ipairs
local error             = error
local tostring          = tostring

------------------------------------------------------------------------
-- Estados de uma fiber
------------------------------------------------------------------------
local STATE_READY    = "ready"
local STATE_RUNNING  = "running"
local STATE_WAITING  = "waiting"
local STATE_DONE     = "done"
local STATE_ERROR    = "error"

------------------------------------------------------------------------
-- Estrutura interna de uma fiber
------------------------------------------------------------------------
local function make_fiber(co, name, priority)
  return {
    co       = co,
    name     = name or "fiber",
    priority = priority or 0,
    state    = STATE_READY,
    result   = nil,
    err      = nil,
  }
end

------------------------------------------------------------------------
-- Scheduler — Escalonador round-robin com prioridades
------------------------------------------------------------------------
scheduler.__index = scheduler

function scheduler.new()
  return setmetatable({
    _queue    = {},  -- Fila de fibers prontas
    _waiting  = {},  -- Fibers esperando (por condição)
    _all      = {},  -- Todas as fibers (por ID)
    _current  = nil, -- Fiber atualmente executando
    _next_id  = 1,
    _running  = false,
    _results  = {},  -- Resultados das fibers completas
  }, scheduler)
end

------------------------------------------------------------------------
-- spawn — Cria e agenda uma nova fiber
------------------------------------------------------------------------
---@param fn function       Função a executar
---@param name? string      Nome da fiber (debug)
---@param priority? number  Prioridade (maior = executa primeiro)
---@return integer id       ID da fiber
function scheduler:spawn(fn, name, priority)
  local id = self._next_id
  self._next_id = id + 1

  local co = coroutine_create(fn)
  local fiber = make_fiber(co, name or ("fiber-" .. id), priority or 0)
  fiber.id = id

  self._all[id] = fiber
  self:_enqueue(fiber)

  return id
end

------------------------------------------------------------------------
-- run — Executa o escalonador até todas as fibers completarem
------------------------------------------------------------------------
---@return table results  Mapa de {id = resultado}
function scheduler:run()
  self._running = true

  while #self._queue > 0 do
    -- Pega a próxima fiber da fila
    local fiber = table_remove(self._queue, 1)

    if coroutine_status(fiber.co) == "dead" then
      fiber.state = STATE_DONE
      goto continue
    end

    -- Executa a fiber
    fiber.state = STATE_RUNNING
    self._current = fiber

    local ok, result = coroutine_resume(fiber.co)

    self._current = nil

    if not ok then
      -- Erro na fiber
      fiber.state = STATE_ERROR
      fiber.err = result
      self._results[fiber.id] = { ok = false, err = result }
    elseif coroutine_status(fiber.co) == "dead" then
      -- Fiber completou
      fiber.state = STATE_DONE
      fiber.result = result
      self._results[fiber.id] = { ok = true, value = result }
    else
      -- Fiber fez yield (cooperativo)
      fiber.state = STATE_READY
      self:_enqueue(fiber)
    end

    ::continue::
  end

  self._running = false
  return self._results
end

------------------------------------------------------------------------
-- yield — Cede a execução para outra fiber
------------------------------------------------------------------------
function scheduler.yield()
  coroutine_yield()
end

------------------------------------------------------------------------
-- _enqueue — Adiciona fiber à fila respeitando prioridades
------------------------------------------------------------------------
function scheduler:_enqueue(fiber)
  local queue = self._queue
  local priority = fiber.priority

  -- Inserção ordenada por prioridade (maior primeiro)
  if priority == 0 or #queue == 0 then
    table_insert(queue, fiber)
    return
  end

  for i = 1, #queue do
    if priority > queue[i].priority then
      table_insert(queue, i, fiber)
      return
    end
  end
  table_insert(queue, fiber)
end

------------------------------------------------------------------------
-- get_result — Obtém o resultado de uma fiber completada
------------------------------------------------------------------------
---@param id integer
---@return any result
---@return boolean ok
function scheduler:get_result(id)
  local r = self._results[id]
  if r then
    return r.value, r.ok
  end
  return nil, false
end

------------------------------------------------------------------------
-- status — Retorna o estado de uma fiber
------------------------------------------------------------------------
---@param id integer
---@return string state
function scheduler:status(id)
  local fiber = self._all[id]
  if fiber then
    return fiber.state
  end
  return "unknown"
end

------------------------------------------------------------------------
-- count — Número de fibers na fila
------------------------------------------------------------------------
---@return integer
function scheduler:count()
  return #self._queue
end

------------------------------------------------------------------------
-- total — Número total de fibers criadas
------------------------------------------------------------------------
---@return integer
function scheduler:total()
  local n = 0
  for _ in pairs(self._all) do
    n = n + 1
  end
  return n
end

return scheduler
