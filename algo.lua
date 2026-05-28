------------------------------------------------------------------------
-- turbo.algo — Algoritmos otimizados para processamento de dados
-- Parte da biblioteca Turbo
-- 100% Lua puro | Compatível com Lua 5.3+ / 5.5
------------------------------------------------------------------------

local algo = {}

-- Cache de funções padrão como variáveis locais (evita lookup na tabela global)
local type       = type
local tonumber   = tonumber
local math_huge  = math.huge
local math_max   = math.maxinteger or  2^53
local math_min   = math.mininteger or -2^53
local select     = select
local rawget     = rawget

------------------------------------------------------------------------
-- CONFIGURAÇÃO
------------------------------------------------------------------------

--- Tamanho de chunk padrão para processamento em blocos
algo.CHUNK_SIZE = 4096

------------------------------------------------------------------------
-- max — Encontra o maior valor em uma tabela (array)
------------------------------------------------------------------------
---@param t table     Array de números
---@param n? integer  Tamanho do array (opcional, usa #t)
---@param cmp? function  Comparador customizado f(a,b) retorna true se a > b
---@return number max_value  O maior valor
---@return integer max_index  O índice do maior valor
function algo.max(t, n, cmp)
  n = n or #t
  if n == 0 then return nil, 0 end

  if cmp then
    -- Caminho com comparador customizado
    local mv = t[1]
    local mi = 1
    for i = 2, n do
      local v = t[i]
      if cmp(v, mv) then
        mv = v
        mi = i
      end
    end
    return mv, mi
  end

  -- Caminho otimizado: sem comparador, sem chamadas de função
  local mv = t[1]
  local mi = 1
  for i = 2, n do
    local v = t[i]
    if v > mv then
      mv = v
      mi = i
    end
  end
  return mv, mi
end

------------------------------------------------------------------------
-- min — Encontra o menor valor em uma tabela (array)
------------------------------------------------------------------------
---@param t table     Array de números
---@param n? integer  Tamanho do array (opcional, usa #t)
---@param cmp? function  Comparador customizado f(a,b) retorna true se a < b
---@return number min_value  O menor valor
---@return integer min_index  O índice do menor valor
function algo.min(t, n, cmp)
  n = n or #t
  if n == 0 then return nil, 0 end

  if cmp then
    local mv = t[1]
    local mi = 1
    for i = 2, n do
      local v = t[i]
      if cmp(v, mv) then
        mv = v
        mi = i
      end
    end
    return mv, mi
  end

  local mv = t[1]
  local mi = 1
  for i = 2, n do
    local v = t[i]
    if v < mv then
      mv = v
      mi = i
    end
  end
  return mv, mi
end

------------------------------------------------------------------------
-- extremes — Encontra max E min em UMA ÚNICA passagem (O(n), 1 pass)
------------------------------------------------------------------------
---@param t table     Array de números
---@param n? integer  Tamanho do array (opcional)
---@return number max_value
---@return integer max_index
---@return number min_value
---@return integer min_index
function algo.extremes(t, n)
  n = n or #t
  if n == 0 then return nil, 0, nil, 0 end

  local maxv = t[1]
  local maxi = 1
  local minv = t[1]
  local mini = 1

  for i = 2, n do
    local v = t[i]
    if v > maxv then
      maxv = v
      maxi = i
    elseif v < minv then
      minv = v
      mini = i
    end
  end

  return maxv, maxi, minv, mini
end

------------------------------------------------------------------------
-- sum — Soma todos os valores (usa compensação Kahan para precisão)
------------------------------------------------------------------------
---@param t table     Array de números
---@param n? integer  Tamanho
---@return number total
function algo.sum(t, n)
  n = n or #t
  if n == 0 then return 0 end

  -- Algoritmo de Kahan para compensar erros de ponto flutuante
  local sum = 0.0
  local c   = 0.0  -- compensação
  for i = 1, n do
    local y = t[i] - c
    local temp = sum + y
    c = (temp - sum) - y
    sum = temp
  end
  return sum
end

------------------------------------------------------------------------
-- stats — Estatísticas completas em uma única passagem
------------------------------------------------------------------------
---@param t table     Array de números
---@param n? integer  Tamanho
---@return table stats  {max, max_i, min, min_i, sum, avg, count}
function algo.stats(t, n)
  n = n or #t
  if n == 0 then
    return { max = nil, max_i = 0, min = nil, min_i = 0,
             sum = 0, avg = 0, count = 0 }
  end

  local maxv = t[1]
  local maxi = 1
  local minv = t[1]
  local mini = 1
  local sum  = t[1]
  local c    = 0.0  -- Kahan compensation

  for i = 2, n do
    local v = t[i]
    if v > maxv then
      maxv = v
      maxi = i
    elseif v < minv then
      minv = v
      mini = i
    end
    -- Kahan sum
    local y = v - c
    local temp = sum + y
    c = (temp - sum) - y
    sum = temp
  end

  return {
    max   = maxv,
    max_i = maxi,
    min   = minv,
    min_i = mini,
    sum   = sum,
    avg   = sum / n,
    count = n,
  }
end

------------------------------------------------------------------------
-- count_if — Conta elementos que satisfazem um predicado
------------------------------------------------------------------------
---@param t table
---@param pred function  f(v) retorna true/false
---@param n? integer
---@return integer
function algo.count_if(t, pred, n)
  n = n or #t
  local count = 0
  for i = 1, n do
    if pred(t[i]) then
      count = count + 1
    end
  end
  return count
end

------------------------------------------------------------------------
-- find — Encontra o primeiro elemento igual ao valor
------------------------------------------------------------------------
---@param t table
---@param value any
---@param n? integer
---@return integer? index  nil se não encontrado
function algo.find(t, value, n)
  n = n or #t
  for i = 1, n do
    if t[i] == value then
      return i
    end
  end
  return nil
end

------------------------------------------------------------------------
-- find_if — Encontra o primeiro elemento que satisfaz predicado
------------------------------------------------------------------------
---@param t table
---@param pred function
---@param n? integer
---@return integer? index
---@return any? value
function algo.find_if(t, pred, n)
  n = n or #t
  for i = 1, n do
    local v = t[i]
    if pred(v) then
      return i, v
    end
  end
  return nil, nil
end

------------------------------------------------------------------------
-- reduce — Aplica função de redução sobre o array
------------------------------------------------------------------------
---@param t table
---@param fn function  f(acumulador, valor) retorna novo acumulador
---@param init? any    Valor inicial (default: t[1])
---@param n? integer
---@return any resultado
function algo.reduce(t, fn, init, n)
  n = n or #t
  local start = 1
  local acc = init
  if acc == nil then
    acc = t[1]
    start = 2
  end
  for i = start, n do
    acc = fn(acc, t[i])
  end
  return acc
end

------------------------------------------------------------------------
-- transform — Aplica função a cada elemento, escrevendo no lugar
------------------------------------------------------------------------
---@param t table
---@param fn function  f(v, i) retorna novo valor
---@param n? integer
---@return table t (mesma tabela, modificada)
function algo.transform(t, fn, n)
  n = n or #t
  for i = 1, n do
    t[i] = fn(t[i], i)
  end
  return t
end

------------------------------------------------------------------------
-- fill_random — Preenche array com números aleatórios
------------------------------------------------------------------------
---@param t table
---@param n integer
---@param lo? integer  Limite inferior (default 1)
---@param hi? integer  Limite superior (default 2^31-1)
---@return table t
function algo.fill_random(t, n, lo, hi)
  lo = lo or 1
  hi = hi or 2147483647
  local random = math.random
  for i = 1, n do
    t[i] = random(lo, hi)
  end
  return t
end

return algo
