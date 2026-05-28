------------------------------------------------------------------------
-- Turbo — Biblioteca de processamento de dados ultra-rápido
-- 100% Lua puro | Compatível com Lua 5.3+ / 5.5
------------------------------------------------------------------------
--
-- Turbo oferece processamento de dados massivos (10M+ elementos) com:
--   • Performance máxima via loops otimizados e cache local
--   • Consumo mínimo de RAM via streaming (memória fixa ~100KB)
--   • Operações in-memory para velocidade máxima
--   • Formato binário para I/O até 10x mais rápido que texto
--
-- Uso básico:
--   local turbo = require("turbo")
--
--   -- In-memory (velocidade máxima)
--   local max_val, max_idx = turbo.max(minha_tabela)
--
--   -- Streaming de arquivo (memória mínima)
--   local max_val = turbo.stream.max("dados.dat")
--
------------------------------------------------------------------------

local turbo = {}

-- Importa submódulos
local algo      = require("turbo.algo")
local buffer    = require("turbo.buffer")
local stream    = require("turbo.stream")
local generator = require("turbo.generator")

-- Exporta submódulos
turbo.algo      = algo
turbo.buffer    = buffer
turbo.stream    = stream
turbo.generator = generator

-- Versão
turbo._VERSION = "Turbo 1.1.0"
turbo._DESCRIPTION = "Ultra-fast data processing and generation library for Lua"

------------------------------------------------------------------------
-- API principal — Atalhos para os métodos mais comuns
------------------------------------------------------------------------

--- Encontra o maior valor em uma tabela
---@param t table       Array de números
---@param n? integer    Tamanho (default: #t)
---@return number value O maior valor
---@return integer index Índice do maior valor
function turbo.max(t, n)
  return algo.max(t, n)
end

--- Encontra o menor valor em uma tabela
---@param t table
---@param n? integer
---@return number value
---@return integer index
function turbo.min(t, n)
  return algo.min(t, n)
end

--- Encontra max E min em uma única passagem
---@param t table
---@param n? integer
---@return number max_val
---@return integer max_idx
---@return number min_val
---@return integer min_idx
function turbo.extremes(t, n)
  return algo.extremes(t, n)
end

--- Calcula a soma de todos os valores (com compensação Kahan)
---@param t table
---@param n? integer
---@return number
function turbo.sum(t, n)
  return algo.sum(t, n)
end

--- Estatísticas completas em uma passagem
---@param t table
---@param n? integer
---@return table  {max, max_i, min, min_i, sum, avg, count}
function turbo.stats(t, n)
  return algo.stats(t, n)
end

------------------------------------------------------------------------
-- API de alta performance — Processamento com controle de GC
------------------------------------------------------------------------

--- Executa uma operação com GC desligado (performance máxima)
---@param fn function  Função a executar
---@return any ...  Retornos da função
function turbo.fast(fn)
  local gc_was = collectgarbage("isrunning")
  if gc_was then
    collectgarbage("stop")
  end
  local results = { fn() }
  if gc_was then
    collectgarbage("restart")
  end
  return table.unpack(results)
end

------------------------------------------------------------------------
-- Buffer factory
------------------------------------------------------------------------

--- Cria um novo buffer pré-alocado
---@param capacity? integer
---@return table
function turbo.new_buffer(capacity)
  return buffer.new(capacity)
end

--- Cria buffer a partir de tabela existente (zero-copy)
---@param t table
---@param n? integer
---@return table
function turbo.wrap(t, n)
  return buffer.from_table(t, n)
end

------------------------------------------------------------------------
-- Benchmark utilitário
------------------------------------------------------------------------

--- Mede o tempo de execução de uma função
---@param fn function  Função a medir
---@param label? string  Rótulo para exibição
---@return number elapsed  Tempo em segundos
---@return any ...  Retornos da função
function turbo.bench(fn, label)
  collectgarbage("collect")
  local mem_before = collectgarbage("count")
  local start = os.clock()
  local results = { fn() }
  local elapsed = os.clock() - start
  collectgarbage("collect")
  local mem_after = collectgarbage("count")

  if label then
    io.write(string.format(
      "[turbo.bench] %s: %.4fs | RAM: %.1fKB → %.1fKB (Δ%.1fKB)\n",
      label, elapsed, mem_before, mem_after, mem_after - mem_before
    ))
  end

  return elapsed, table.unpack(results)
end

return turbo
