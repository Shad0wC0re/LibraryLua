------------------------------------------------------------------------
-- turbo.stream — Leitura streaming ultra-eficiente de arquivos
-- Parte da biblioteca Turbo
-- 100% Lua puro | Compatível com Lua 5.3+ / 5.5
------------------------------------------------------------------------

local stream = {}

-- Cache local de funções
local io_open       = io.open
local string_find   = string.find
local string_sub    = string.sub
local string_pack   = string.pack
local string_unpack = string.unpack
local tonumber      = tonumber
local type          = type
local math_huge     = math.huge
local math_maxint   = math.maxinteger or  2^53
local math_minint   = math.mininteger or -2^53
local collectgarbage = collectgarbage
local table_unpack  = table.unpack
local string_rep    = string.rep

------------------------------------------------------------------------
-- CONFIGURAÇÃO
------------------------------------------------------------------------

--- Tamanho do bloco de leitura (bytes)
--- 1MB é ideal para minimizar chamadas do OS em arquivos grandes (10M+)
stream.BLOCK_SIZE = 1048576

--- Tamanho do bloco para formato binário
stream.BINARY_BLOCK_SIZE = 1048576

------------------------------------------------------------------------
-- Formatos e Tipos de Dados Binários
------------------------------------------------------------------------
stream.FORMAT_TEXT    = "text"     -- Um número por linha
stream.FORMAT_BINARY  = "binary"   -- Binário padrão

local BINARY_TYPES = {
  i8 = { fmt = "<i8", size = 8, char = "i8" },
  I8 = { fmt = "<I8", size = 8, char = "I8" },
  d  = { fmt = "<d",  size = 8, char = "d"  },
  f  = { fmt = "<f",  size = 4, char = "f"  },
  i4 = { fmt = "<i4", size = 4, char = "i4" },
  I4 = { fmt = "<I4", size = 4, char = "I4" },
}

local function parse_format(format)
  if not format then
    return stream.FORMAT_TEXT, nil
  end
  local fmt_type, sub_fmt = format:match("([^:]+):?(.*)")
  if fmt_type == "binary" then
    if sub_fmt == "" or sub_fmt == nil then
      sub_fmt = "I8" -- Padrão legado do benchmark
    end
    local info = BINARY_TYPES[sub_fmt]
    if not info then
      error("Formato binário não suportado: " .. tostring(sub_fmt))
    end
    return "binary", info
  end
  return fmt_type, nil
end

------------------------------------------------------------------------
-- stream_max — Encontra o máximo em arquivo (streaming, memória fixa)
------------------------------------------------------------------------
---@param filepath string      Caminho do arquivo
---@param format? string       "text" | "binary:<tipo>"
---@param block_size? integer  Tamanho do bloco
---@return number max_value
---@return integer count       Total de elementos processados
---@return number elapsed_sec  Tempo gasto
function stream.max(filepath, format, block_size)
  local fmt_type, bin_info = parse_format(format)
  block_size = block_size or stream.BLOCK_SIZE

  local start = os.clock()

  if fmt_type == "binary" then
    return stream._max_binary(filepath, block_size, start, bin_info)
  else
    return stream._max_text(filepath, block_size, start)
  end
end

------------------------------------------------------------------------
-- stream_min — Encontra o mínimo em arquivo (streaming, memória fixa)
------------------------------------------------------------------------
---@param filepath string
---@param format? string
---@param block_size? integer
---@return number min_value
---@return integer count
---@return number elapsed_sec
function stream.min(filepath, format, block_size)
  local fmt_type, bin_info = parse_format(format)
  block_size = block_size or stream.BLOCK_SIZE

  local start = os.clock()

  if fmt_type == "binary" then
    return stream._min_binary(filepath, block_size, start, bin_info)
  else
    return stream._min_text(filepath, block_size, start)
  end
end

------------------------------------------------------------------------
-- stream_extremes — Encontra max E min em UMA passagem (streaming)
------------------------------------------------------------------------
---@param filepath string
---@param format? string
---@param block_size? integer
---@return number max_value
---@return number min_value
---@return integer count
---@return number elapsed_sec
function stream.extremes(filepath, format, block_size)
  local fmt_type, bin_info = parse_format(format)
  block_size = block_size or stream.BLOCK_SIZE

  local start = os.clock()

  if fmt_type == "binary" then
    return stream._extremes_binary(filepath, block_size, start, bin_info)
  else
    return stream._extremes_text(filepath, block_size, start)
  end
end

------------------------------------------------------------------------
-- stream_stats — Estatísticas completas em streaming (1 passagem)
------------------------------------------------------------------------
---@param filepath string
---@param format? string
---@param block_size? integer
---@return table stats  {max, min, sum, avg, count, elapsed}
function stream.stats(filepath, format, block_size)
  local fmt_type, bin_info = parse_format(format)
  block_size = block_size or stream.BLOCK_SIZE

  local start = os.clock()
  local f = io_open(filepath, fmt_type == "binary" and "rb" or "r")
  if not f then
    return { max = nil, min = nil, sum = 0, avg = 0, count = 0, elapsed = 0 }
  end

  local maxv  = -math_huge
  local minv  = math_huge
  local sum   = 0.0
  local c     = 0.0  -- Compensação Kahan
  local count = 0

  if fmt_type == "binary" then
    local fmt = bin_info.fmt
    local size = bin_info.size
    while true do
      local data = f:read(block_size)
      if not data then break end
      local len = #data
      for pos = 1, len - size + 1, size do
        local v = string_unpack(fmt, data, pos)
        count = count + 1
        if v > maxv then maxv = v end
        if v < minv then minv = v end
        local y = v - c
        local temp = sum + y
        c = (temp - sum) - y
        sum = temp
      end
    end
  else
    local remainder = ""
    while true do
      local block = f:read(block_size)
      if not block then
        if #remainder > 0 then
          local v = tonumber(remainder)
          if v then
            count = count + 1
            if v > maxv then maxv = v end
            if v < minv then minv = v end
            local y = v - c
            local temp = sum + y
            c = (temp - sum) - y
            sum = temp
          end
        end
        break
      end
      local data = remainder .. block
      local pos = 1
      while true do
        local nl = string_find(data, "\n", pos, true)
        if not nl then
          remainder = string_sub(data, pos)
          break
        end
        local line = string_sub(data, pos, nl - 1)
        local v = tonumber(line)
        if v then
          count = count + 1
          if v > maxv then maxv = v end
          if v < minv then minv = v end
          local y = v - c
          local temp = sum + y
          c = (temp - sum) - y
          sum = temp
        end
        pos = nl + 1
      end
    end
  end

  f:close()
  local elapsed = os.clock() - start

  return {
    max     = count > 0 and maxv or nil,
    min     = count > 0 and minv or nil,
    sum     = sum,
    avg     = count > 0 and sum / count or 0,
    count   = count,
    elapsed = elapsed,
  }
end

------------------------------------------------------------------------
-- IMPLEMENTAÇÕES INTERNAS — TEXTO
------------------------------------------------------------------------

function stream._max_text(filepath, block_size, start)
  local f = io_open(filepath, "r")
  if not f then return nil, 0, 0 end

  local maxv = -math_huge
  local count = 0
  local remainder = ""

  while true do
    local block = f:read(block_size)
    if not block then
      if #remainder > 0 then
        local v = tonumber(remainder)
        if v then
          count = count + 1
          if v > maxv then maxv = v end
        end
      end
      break
    end
    local data = remainder .. block
    local pos = 1
    while true do
      local nl = string_find(data, "\n", pos, true)
      if not nl then
        remainder = string_sub(data, pos)
        break
      end
      local v = tonumber(string_sub(data, pos, nl - 1))
      if v then
        count = count + 1
        if v > maxv then maxv = v end
      end
      pos = nl + 1
    end
  end

  f:close()
  return count > 0 and maxv or nil, count, os.clock() - start
end

function stream._min_text(filepath, block_size, start)
  local f = io_open(filepath, "r")
  if not f then return nil, 0, 0 end

  local minv = math_huge
  local count = 0
  local remainder = ""

  while true do
    local block = f:read(block_size)
    if not block then
      if #remainder > 0 then
        local v = tonumber(remainder)
        if v then
          count = count + 1
          if v < minv then minv = v end
        end
      end
      break
    end
    local data = remainder .. block
    local pos = 1
    while true do
      local nl = string_find(data, "\n", pos, true)
      if not nl then
        remainder = string_sub(data, pos)
        break
      end
      local v = tonumber(string_sub(data, pos, nl - 1))
      if v then
        count = count + 1
        if v < minv then minv = v end
      end
      pos = nl + 1
    end
  end

  f:close()
  return count > 0 and minv or nil, count, os.clock() - start
end

function stream._extremes_text(filepath, block_size, start)
  local f = io_open(filepath, "r")
  if not f then return nil, nil, 0, 0 end

  local maxv = -math_huge
  local minv = math_huge
  local count = 0
  local remainder = ""

  while true do
    local block = f:read(block_size)
    if not block then
      if #remainder > 0 then
        local v = tonumber(remainder)
        if v then
          count = count + 1
          if v > maxv then maxv = v end
          if v < minv then minv = v end
        end
      end
      break
    end
    local data = remainder .. block
    local pos = 1
    while true do
      local nl = string_find(data, "\n", pos, true)
      if not nl then
        remainder = string_sub(data, pos)
        break
      end
      local v = tonumber(string_sub(data, pos, nl - 1))
      if v then
        count = count + 1
        if v > maxv then maxv = v end
        if v < minv then minv = v end
      end
      pos = nl + 1
    end
  end

  f:close()
  local elapsed = os.clock() - start
  if count == 0 then return nil, nil, 0, elapsed end
  return maxv, minv, count, elapsed
end

------------------------------------------------------------------------
-- IMPLEMENTAÇÕES INTERNAS — BINÁRIO
------------------------------------------------------------------------

function stream._max_binary(filepath, block_size, start, bin_info)
  local f = io_open(filepath, "rb")
  if not f then return nil, 0, 0 end

  local fmt = bin_info.fmt
  local size = bin_info.size
  local maxv = -math_huge
  local count = 0

  while true do
    local data = f:read(block_size)
    if not data then break end
    local len = #data
    for pos = 1, len - size + 1, size do
      local v = string_unpack(fmt, data, pos)
      count = count + 1
      if v > maxv then maxv = v end
    end
  end

  f:close()
  return count > 0 and maxv or nil, count, os.clock() - start
end

function stream._min_binary(filepath, block_size, start, bin_info)
  local f = io_open(filepath, "rb")
  if not f then return nil, 0, 0 end

  local fmt = bin_info.fmt
  local size = bin_info.size
  local minv = math_huge
  local count = 0

  while true do
    local data = f:read(block_size)
    if not data then break end
    local len = #data
    for pos = 1, len - size + 1, size do
      local v = string_unpack(fmt, data, pos)
      count = count + 1
      if v < minv then minv = v end
    end
  end

  f:close()
  return count > 0 and minv or nil, count, os.clock() - start
end

function stream._extremes_binary(filepath, block_size, start, bin_info)
  local f = io_open(filepath, "rb")
  if not f then return nil, nil, 0, 0 end

  local fmt = bin_info.fmt
  local size = bin_info.size
  local maxv = -math_huge
  local minv = math_huge
  local count = 0

  while true do
    local data = f:read(block_size)
    if not data then break end
    local len = #data
    for pos = 1, len - size + 1, size do
      local v = string_unpack(fmt, data, pos)
      count = count + 1
      if v > maxv then maxv = v end
      if v < minv then minv = v end
    end
  end

  f:close()
  local elapsed = os.clock() - start
  if count == 0 then return nil, nil, 0, elapsed end
  return maxv, minv, count, elapsed
end

------------------------------------------------------------------------
-- Utilitários de escrita
------------------------------------------------------------------------

--- Escreve array de números em arquivo texto (um por linha)
---@param filepath string
---@param data table
---@param n? integer
function stream.write_text(filepath, data, n)
  n = n or #data
  local f = io_open(filepath, "w")
  if not f then error("Não foi possível abrir: " .. filepath) end

  local buf = {}
  local bi = 0
  local BATCH = 10000

  for i = 1, n do
    bi = bi + 1
    buf[bi] = data[i]
    if bi >= BATCH then
      f:write(table_concat(buf, "\n", 1, bi))
      f:write("\n")
      bi = 0
    end
  end
  if bi > 0 then
    f:write(table_concat(buf, "\n", 1, bi))
    f:write("\n")
  end

  f:close()
end

--- Escreve array de números em arquivo binário compactado usando string.pack
---@param filepath string
---@param data table
---@param n? integer
---@param bin_format? string   "i8" | "I8" | "d" | "f" | "i4" | "I4"
function stream.write_binary(filepath, data, n, bin_format)
  n = n or #data
  bin_format = bin_format or "I8"
  local info = BINARY_TYPES[bin_format] or BINARY_TYPES.I8
  local fmt_char = info.char

  local f = io_open(filepath, "wb")
  if not f then error("Não foi possível abrir: " .. filepath) end

  local buf = {}
  local bi = 0
  local BATCH = 2000

  for i = 1, n do
    bi = bi + 1
    buf[bi] = data[i]
    if bi >= BATCH then
      local pattern = "<" .. string_rep(fmt_char, bi)
      f:write(string_pack(pattern, table_unpack(buf, 1, bi)))
      bi = 0
    end
  end
  if bi > 0 then
    local pattern = "<" .. string_rep(fmt_char, bi)
    f:write(string_pack(pattern, table_unpack(buf, 1, bi)))
  end

  f:close()
end

------------------------------------------------------------------------
-- stream.iterate — Iterador streaming para processamento customizado
------------------------------------------------------------------------
---@param filepath string
---@param format? string    "text" | "binary:<tipo>"
---@param block_size? integer
---@return function iterator  Retorna (valor, índice) a cada chamada
function stream.iterate(filepath, format, block_size)
  local fmt_type, bin_info = parse_format(format)
  block_size = block_size or stream.BLOCK_SIZE

  local f = io_open(filepath, fmt_type == "binary" and "rb" or "r")
  if not f then
    return function() return nil end
  end

  local count = 0

  if fmt_type == "binary" then
    local fmt = bin_info.fmt
    local size = bin_info.size
    local data = ""
    local pos = 1
    return function()
      while true do
        if pos + size - 1 <= #data then
          local v = string_unpack(fmt, data, pos)
          pos = pos + size
          count = count + 1
          return v, count
        end
        data = f:read(block_size)
        if not data then
          f:close()
          return nil
        end
        pos = 1
      end
    end
  else
    local remainder = ""
    local done = false
    return function()
      if done then return nil end
      while true do
        local nl = string_find(remainder, "\n", 1, true)
        if nl then
          local line = string_sub(remainder, 1, nl - 1)
          remainder = string_sub(remainder, nl + 1)
          local v = tonumber(line)
          if v then
            count = count + 1
            return v, count
          end
        else
          local block = f:read(block_size)
          if not block then
            done = true
            f:close()
            if #remainder > 0 then
              local v = tonumber(remainder)
              if v then
                count = count + 1
                return v, count
              end
            end
            return nil
          end
          remainder = remainder .. block
        end
      end
    end
  end
end

return stream
