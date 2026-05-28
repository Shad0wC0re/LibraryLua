------------------------------------------------------------------------
-- fiber.pool — Pool de workers reutilizáveis
-- Parte da biblioteca Fiber
-- 100% Lua puro | Compatível com Lua 5.3+ / 5.5
------------------------------------------------------------------------

local pool = {}
pool.__index = pool

-- Cache local
local coroutine_create = coroutine.create
local coroutine_resume = coroutine.resume
local coroutine_yield  = coroutine.yield
local coroutine_status = coroutine.status
local setmetatable     = setmetatable
local table_insert     = table.insert
local table_remove     = table.remove
local math_ceil        = math.ceil
local math_min         = math.min

------------------------------------------------------------------------
-- Construtor
------------------------------------------------------------------------
---@param num_workers? integer  Número de workers (default: 4)
---@return table pool
function pool.new(num_workers)
  return setmetatable({
    _num_workers = num_workers or 4,
    _results     = {},
  }, pool)
end

------------------------------------------------------------------------
-- map — Aplica uma função a cada elemento em paralelo (cooperativo)
------------------------------------------------------------------------
---@param data table      Array de dados
---@param fn function     Função a aplicar: f(valor, índice) -> resultado
---@param n? integer      Tamanho dos dados
---@return table results  Array de resultados na mesma ordem
function pool:map(data, fn, n)
  n = n or #data
  local results = {}
  local num_workers = self._num_workers
  local chunk_size = math_ceil(n / num_workers)

  -- Criar coroutines para cada chunk
  local workers = {}
  for w = 1, num_workers do
    local from = (w - 1) * chunk_size + 1
    local to = math_min(w * chunk_size, n)
    if from > n then break end

    workers[#workers + 1] = coroutine_create(function()
      local chunk_results = {}
      for i = from, to do
        chunk_results[i - from + 1] = fn(data[i], i)
      end
      return chunk_results, from, to
    end)
  end

  -- Executar todos os workers
  for _, co in ipairs(workers) do
    local ok, chunk_results, from, to = coroutine_resume(co)
    if ok and chunk_results then
      for i = from, to do
        results[i] = chunk_results[i - from + 1]
      end
    end
  end

  return results
end

------------------------------------------------------------------------
-- reduce — Redução paralela em chunks, depois combina resultados
------------------------------------------------------------------------
---@param data table       Array de dados
---@param fn function      Função de redução: f(acc, valor) -> acc
---@param combine function Função de combinação: f(acc1, acc2) -> acc
---@param init any         Valor inicial
---@param n? integer       Tamanho dos dados
---@return any result      Resultado final
function pool:reduce(data, fn, combine, init, n)
  n = n or #data
  if n == 0 then return init end

  local num_workers = self._num_workers
  local chunk_size = math_ceil(n / num_workers)

  -- Cada worker reduz seu chunk
  local partial_results = {}
  local workers = {}
  local num_active = 0

  for w = 1, num_workers do
    local from = (w - 1) * chunk_size + 1
    local to = math_min(w * chunk_size, n)
    if from > n then break end

    num_active = num_active + 1
    workers[num_active] = coroutine_create(function()
      local acc = data[from]
      for i = from + 1, to do
        acc = fn(acc, data[i])
      end
      return acc
    end)
  end

  -- Executar workers
  for i = 1, num_active do
    local ok, result = coroutine_resume(workers[i])
    if ok then
      partial_results[i] = result
    end
  end

  -- Combinar resultados parciais
  if #partial_results == 0 then return init end
  local final = partial_results[1]
  for i = 2, #partial_results do
    final = combine(final, partial_results[i])
  end
  return final
end

------------------------------------------------------------------------
-- parallel — Executa múltiplas funções em paralelo (cooperativo)
------------------------------------------------------------------------
---@param tasks table  Array de funções a executar
---@return table results  Array de resultados {ok, value/err}
function pool:parallel(tasks)
  local results = {}
  local workers = {}

  for i, task in ipairs(tasks) do
    workers[i] = coroutine_create(task)
  end

  -- Round-robin execution
  local active = #workers
  local status = {}
  for i = 1, active do
    status[i] = "ready"
  end

  while active > 0 do
    for i = 1, #workers do
      if status[i] == "ready" or status[i] == "suspended" then
        local co = workers[i]
        if coroutine_status(co) == "dead" then
          status[i] = "dead"
          active = active - 1
        else
          local ok, value = coroutine_resume(co)
          if coroutine_status(co) == "dead" then
            status[i] = "dead"
            active = active - 1
            results[i] = { ok = ok, value = ok and value or nil, err = not ok and value or nil }
          else
            status[i] = "suspended"
          end
        end
      end
    end
  end

  return results
end

------------------------------------------------------------------------
-- parallel_max — Encontra o máximo usando workers paralelos
------------------------------------------------------------------------
---@param data table    Array de números
---@param n? integer    Tamanho
---@return number max   O maior valor
---@return integer idx  Índice do maior valor
function pool:parallel_max(data, n)
  n = n or #data
  if n == 0 then return nil, 0 end

  local num_workers = self._num_workers
  local chunk_size = math_ceil(n / num_workers)

  local workers = {}
  local num_active = 0

  for w = 1, num_workers do
    local from = (w - 1) * chunk_size + 1
    local to = math_min(w * chunk_size, n)
    if from > n then break end

    num_active = num_active + 1
    workers[num_active] = coroutine_create(function()
      local mv = data[from]
      local mi = from
      for i = from + 1, to do
        local v = data[i]
        if v > mv then
          mv = v
          mi = i
        end
      end
      return mv, mi
    end)
  end

  local global_max = nil
  local global_idx = 0
  for i = 1, num_active do
    local ok, mv, mi = coroutine_resume(workers[i])
    if ok then
      if global_max == nil or mv > global_max then
        global_max = mv
        global_idx = mi
      end
    end
  end

  return global_max, global_idx
end

------------------------------------------------------------------------
-- parallel_min — Encontra o mínimo usando workers paralelos
------------------------------------------------------------------------
---@param data table
---@param n? integer
---@return number min
---@return integer idx
function pool:parallel_min(data, n)
  n = n or #data
  if n == 0 then return nil, 0 end

  local num_workers = self._num_workers
  local chunk_size = math_ceil(n / num_workers)

  local workers = {}
  local num_active = 0

  for w = 1, num_workers do
    local from = (w - 1) * chunk_size + 1
    local to = math_min(w * chunk_size, n)
    if from > n then break end

    num_active = num_active + 1
    workers[num_active] = coroutine_create(function()
      local mv = data[from]
      local mi = from
      for i = from + 1, to do
        local v = data[i]
        if v < mv then
          mv = v
          mi = i
        end
      end
      return mv, mi
    end)
  end

  local global_min = nil
  local global_idx = 0
  for i = 1, num_active do
    local ok, mv, mi = coroutine_resume(workers[i])
    if ok then
      if global_min == nil or mv < global_min then
        global_min = mv
        global_idx = mi
      end
    end
  end

  return global_min, global_idx
end

------------------------------------------------------------------------
-- parallel_extremes — Encontra max E min em paralelo
------------------------------------------------------------------------
---@param data table
---@param n? integer
---@return number max_val
---@return integer max_idx
---@return number min_val
---@return integer min_idx
function pool:parallel_extremes(data, n)
  n = n or #data
  if n == 0 then return nil, 0, nil, 0 end

  local num_workers = self._num_workers
  local chunk_size = math_ceil(n / num_workers)

  local workers = {}
  local num_active = 0

  for w = 1, num_workers do
    local from = (w - 1) * chunk_size + 1
    local to = math_min(w * chunk_size, n)
    if from > n then break end

    num_active = num_active + 1
    workers[num_active] = coroutine_create(function()
      local maxv = data[from]
      local maxi = from
      local minv = data[from]
      local mini = from
      for i = from + 1, to do
        local v = data[i]
        if v > maxv then
          maxv = v
          maxi = i
        elseif v < minv then
          minv = v
          mini = i
        end
      end
      return maxv, maxi, minv, mini
    end)
  end

  local g_maxv, g_maxi, g_minv, g_mini
  for i = 1, num_active do
    local ok, maxv, maxi, minv, mini = coroutine_resume(workers[i])
    if ok then
      if g_maxv == nil or maxv > g_maxv then
        g_maxv = maxv
        g_maxi = maxi
      end
      if g_minv == nil or minv < g_minv then
        g_minv = minv
        g_mini = mini
      end
    end
  end

  return g_maxv, g_maxi, g_minv, g_mini
end

return pool
