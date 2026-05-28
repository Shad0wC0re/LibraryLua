------------------------------------------------------------------------
-- Fiber — Biblioteca de multi-threading cooperativa
-- 100% Lua puro | Compatível com Lua 5.3+ / 5.5
------------------------------------------------------------------------
--
-- Fiber oferece multi-threading cooperativa usando coroutines com:
--   • Escalonador round-robin com prioridades
--   • Pool de workers para processamento paralelo
--   • Canais de comunicação estilo Go
--   • Funções de alto nível: parallel, map, reduce
--
-- Uso básico:
--   local fiber = require("fiber")
--
--   -- Execução paralela simples
--   local results = fiber.parallel({
--     function() return "resultado 1" end,
--     function() return "resultado 2" end,
--   })
--
--   -- Encontrar max em paralelo com workers
--   local max_val = fiber.parallel_max(dados, #dados)
--
------------------------------------------------------------------------

local fiber = {}

-- Importa submódulos
local scheduler_mod = require("fiber.scheduler")
local pool_mod      = require("fiber.pool")
local channel_mod   = require("fiber.channel")

-- Exporta submódulos
fiber.scheduler = scheduler_mod
fiber.pool      = pool_mod
fiber.channel   = channel_mod

-- Versão
fiber._VERSION = "Fiber 1.0.0"
fiber._DESCRIPTION = "Cooperative multi-threading library for Lua"

-- Pool global padrão
local default_pool = pool_mod.new(4)

------------------------------------------------------------------------
-- API de alto nível — Usa o pool global
------------------------------------------------------------------------

--- Executa múltiplas funções em paralelo
---@param tasks table  Array de funções
---@return table results  Array de {ok, value, err}
function fiber.parallel(tasks)
  return default_pool:parallel(tasks)
end

--- Aplica função a cada elemento em paralelo
---@param data table
---@param fn function
---@param n? integer
---@return table results
function fiber.map(data, fn, n)
  return default_pool:map(data, fn, n)
end

--- Redução paralela
---@param data table
---@param fn function
---@param combine function
---@param init any
---@param n? integer
---@return any result
function fiber.reduce(data, fn, combine, init, n)
  return default_pool:reduce(data, fn, combine, init, n)
end

--- Encontra o máximo em paralelo
---@param data table
---@param n? integer
---@return number max_val
---@return integer max_idx
function fiber.parallel_max(data, n)
  return default_pool:parallel_max(data, n)
end

--- Encontra o mínimo em paralelo
---@param data table
---@param n? integer
---@return number min_val
---@return integer min_idx
function fiber.parallel_min(data, n)
  return default_pool:parallel_min(data, n)
end

--- Encontra max e min em paralelo
---@param data table
---@param n? integer
---@return number max_val, integer max_idx, number min_val, integer min_idx
function fiber.parallel_extremes(data, n)
  return default_pool:parallel_extremes(data, n)
end

------------------------------------------------------------------------
-- Scheduler API
------------------------------------------------------------------------

--- Cria um novo scheduler
---@return table scheduler
function fiber.new_scheduler()
  return scheduler_mod.new()
end

--- Cria um novo pool de workers
---@param num_workers? integer
---@return table pool
function fiber.new_pool(num_workers)
  return pool_mod.new(num_workers)
end

--- Cria um novo canal de comunicação
---@param capacity? integer  Buffer capacity (0 = unbuffered)
---@return table channel
function fiber.new_channel(capacity)
  return channel_mod.new(capacity)
end

------------------------------------------------------------------------
-- Spawn + Run — API simplificada com scheduler
------------------------------------------------------------------------

--- Executa múltiplas fibers com scheduler
---@param fibers table  Array de {fn=function, name=string, priority=number}
---@return table results  Mapa de resultados por ID
function fiber.run(fibers)
  local sched = scheduler_mod.new()
  local ids = {}

  for i, f in ipairs(fibers) do
    if type(f) == "function" then
      ids[i] = sched:spawn(f)
    else
      ids[i] = sched:spawn(f.fn, f.name, f.priority)
    end
  end

  return sched:run()
end

--- Yield cooperativo (para usar dentro de fibers)
function fiber.yield()
  coroutine.yield()
end

------------------------------------------------------------------------
-- Configuração do pool global
------------------------------------------------------------------------

--- Define o número de workers do pool global
---@param n integer
function fiber.set_workers(n)
  default_pool = pool_mod.new(n)
end

--- Retorna o número de workers do pool global
---@return integer
function fiber.get_workers()
  return default_pool._num_workers
end

return fiber
