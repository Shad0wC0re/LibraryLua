------------------------------------------------------------------------
-- turbo.buffer — Buffer otimizado para processamento in-memory
-- Parte da biblioteca Turbo
-- 100% Lua puro | Compatível com Lua 5.3+ / 5.5
------------------------------------------------------------------------

local buffer = {}
buffer.__index = buffer

-- Cache local de funções
local table_create = table.create  -- Lua 5.5
local table_move   = table.move
local setmetatable = setmetatable
local type         = type
local math_ceil    = math.ceil
local math_random  = math.random
local collectgarbage = collectgarbage

--- Flag: se table.create existe (Lua 5.5+)
local HAS_TABLE_CREATE = (table_create ~= nil)

------------------------------------------------------------------------
-- Construtor — Cria um novo buffer pré-alocado
------------------------------------------------------------------------
---@param capacity integer  Capacidade inicial do buffer
---@return table buffer     Novo buffer
function buffer.new(capacity)
  capacity = capacity or 1024

  local data
  if HAS_TABLE_CREATE then
    data = table_create(capacity)
  else
    data = {}
  end

  return setmetatable({
    _data     = data,
    _size     = 0,
    _capacity = capacity,
  }, buffer)
end

------------------------------------------------------------------------
-- size — Retorna o número de elementos no buffer
------------------------------------------------------------------------
---@return integer
function buffer:size()
  return self._size
end

------------------------------------------------------------------------
-- capacity — Retorna a capacidade alocada
------------------------------------------------------------------------
---@return integer
function buffer:capacity()
  return self._capacity
end

------------------------------------------------------------------------
-- get — Acessa um elemento por índice
------------------------------------------------------------------------
---@param i integer  Índice (1-based)
---@return any
function buffer:get(i)
  return self._data[i]
end

------------------------------------------------------------------------
-- set — Define um elemento por índice
------------------------------------------------------------------------
---@param i integer
---@param value any
function buffer:set(i, value)
  self._data[i] = value
  if i > self._size then
    self._size = i
  end
end

------------------------------------------------------------------------
-- push — Adiciona elemento ao final
------------------------------------------------------------------------
---@param value any
function buffer:push(value)
  local n = self._size + 1
  self._size = n
  self._data[n] = value
end

------------------------------------------------------------------------
-- push_many — Adiciona múltiplos elementos de uma vez
------------------------------------------------------------------------
---@param values table  Array de valores a adicionar
---@param count? integer  Quantos valores (default: #values)
function buffer:push_many(values, count)
  count = count or #values
  local data = self._data
  local n = self._size
  for i = 1, count do
    n = n + 1
    data[n] = values[i]
  end
  self._size = n
end

------------------------------------------------------------------------
-- clear — Limpa o buffer sem desalocar
------------------------------------------------------------------------
function buffer:clear()
  local data = self._data
  for i = 1, self._size do
    data[i] = nil
  end
  self._size = 0
end

------------------------------------------------------------------------
-- data — Retorna referência interna da tabela (zero-copy)
------------------------------------------------------------------------
---@return table data
---@return integer size
function buffer:data()
  return self._data, self._size
end

------------------------------------------------------------------------
-- fill_random — Preenche com números aleatórios (otimizado)
------------------------------------------------------------------------
---@param n integer       Quantidade de elementos
---@param lo? integer     Limite inferior (default 1)
---@param hi? integer     Limite superior (default 2^31-1)
---@return table self
function buffer:fill_random(n, lo, hi)
  lo = lo or 1
  hi = hi or 2147483647
  local data = self._data
  local random = math_random
  for i = 1, n do
    data[i] = random(lo, hi)
  end
  self._size = n
  return self
end

------------------------------------------------------------------------
-- fill_sequence — Preenche com sequência (1, 2, 3, ..., n)
------------------------------------------------------------------------
---@param n integer
---@return table self
function buffer:fill_sequence(n)
  local data = self._data
  for i = 1, n do
    data[i] = i
  end
  self._size = n
  return self
end

------------------------------------------------------------------------
-- from_table — Cria buffer a partir de tabela existente (zero-copy)
------------------------------------------------------------------------
---@param t table
---@param n? integer
---@return table buffer
function buffer.from_table(t, n)
  n = n or #t
  return setmetatable({
    _data     = t,
    _size     = n,
    _capacity = n,
  }, buffer)
end

------------------------------------------------------------------------
-- memory_usage — Retorna estimativa de uso de memória em bytes
------------------------------------------------------------------------
---@return number bytes
function buffer:memory_usage()
  -- Cada slot em uma tabela Lua ocupa ~16 bytes (chave + valor)
  -- Mais overhead do objeto buffer (~200 bytes)
  return self._capacity * 16 + 200
end

------------------------------------------------------------------------
-- gc_compact — Força coleta de lixo e compacta
------------------------------------------------------------------------
function buffer:gc_compact()
  -- Remove slots vazios além do tamanho
  local data = self._data
  local n = self._size
  for i = n + 1, self._capacity do
    data[i] = nil
  end
  self._capacity = n
  collectgarbage("collect")
end

return buffer
