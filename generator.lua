------------------------------------------------------------------------
-- turbo.generator — Gerador de dados massivos ultra-rápido em Lua pura
-- Parte da biblioteca Turbo
-- 100% Lua puro | Compatível com Lua 5.3+ / 5.5
------------------------------------------------------------------------

local generator = {}

-- Cache local de funções
local math_random   = math.random
local string_format = string.format
local table_concat  = table.concat
local io_open       = io.open
local string_pack   = string.pack
local table_unpack  = table.unpack
local math_min      = math.min
local math_floor    = math.floor
local tostring      = tostring

------------------------------------------------------------------------
-- Tabelas de Configuração
------------------------------------------------------------------------

local BINARY_FMT_INFO = {
  i8 = { char = "i8", is_float = false },
  I8 = { char = "I8", is_float = false },
  d  = { char = "d",  is_float = true },
  f  = { char = "f",  is_float = true },
  i4 = { char = "i4", is_float = false },
  I4 = { char = "I4", is_float = false },
}

------------------------------------------------------------------------
-- generate — Rota para o gerador correto baseado nas opções
------------------------------------------------------------------------
---@param filepath string
---@param count integer
---@param options? table
---@return boolean ok
---@return string? error_msg
function generator.generate(filepath, count, options)
  options = options or {}
  local format_type = options.type or "text"

  if format_type == "binary" then
    return generator.generate_binary(filepath, count, options)
  elseif format_type == "csv" then
    return generator.generate_csv(filepath, count, options)
  else
    return generator.generate_text(filepath, count, options)
  end
end

------------------------------------------------------------------------
-- generate_text — Gera arquivo texto com um número por linha
------------------------------------------------------------------------
function generator.generate_text(filepath, count, options)
  local f, err = io_open(filepath, "w")
  if not f then return false, err end

  local min_val      = options.min or 1
  local max_val      = options.max or 2000000000
  local dec_chance   = options.decimals or 0
  local neg_chance   = options.negatives or 0
  local empty_chance = options.empty_lines or 0

  local batch_size = 50000
  local buf = {}
  local bi = 0

  for i = 1, count do
    -- Decide se gera linha vazia
    if empty_chance > 0 and math_random() <= empty_chance then
      bi = bi + 1
      buf[bi] = ""
    else
      local val
      if dec_chance > 0 and math_random() <= dec_chance then
        local diff = max_val - min_val
        val = min_val + math_random() * diff
        val = string_format("%.2f", val)
      else
        local min_i = math_floor(min_val)
        local max_i = math_floor(max_val)
        if min_i >= max_i then
          val = min_i
        else
          val = math_random(min_i, max_i)
        end
      end

      -- Decide se é negativo
      if neg_chance > 0 and math_random() <= neg_chance then
        val = "-" .. val
      end

      bi = bi + 1
      buf[bi] = tostring(val)
    end

    if bi >= batch_size then
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
  return true
end

------------------------------------------------------------------------
-- generate_binary — Gera arquivo binário compactado usando string.pack
------------------------------------------------------------------------
function generator.generate_binary(filepath, count, options)
  local f, err = io_open(filepath, "wb")
  if not f then return false, err end

  local min_val    = options.min or 1
  local max_val    = options.max or 2000000000
  local bin_format = options.bin_format or "i8"
  local fmt_info   = BINARY_FMT_INFO[bin_format] or BINARY_FMT_INFO.i8
  local fmt_char   = fmt_info.char
  local neg_chance = options.negatives or 0

  local batch_size = 2000  -- Evita estouro de pilha com table.unpack
  local pack_pattern = "<" .. string.rep(fmt_char, batch_size)
  local buf = {}

  local i = 1
  while i <= count do
    local current_batch = math_min(batch_size, count - i + 1)
    for j = 1, current_batch do
      local val
      if fmt_info.is_float then
        local diff = max_val - min_val
        val = min_val + math_random() * diff
      else
        local min_i = math_floor(min_val)
        local max_i = math_floor(max_val)
        if min_i >= max_i then
          val = min_i
        else
          val = math_random(min_i, max_i)
        end
      end

      if neg_chance > 0 and not fmt_char:match("^I") and math_random() <= neg_chance then
        val = -val
      end

      buf[j] = val
    end

    local pattern = (current_batch == batch_size) and pack_pattern or ("<" .. string.rep(fmt_char, current_batch))
    local packed = string_pack(pattern, table_unpack(buf, 1, current_batch))
    f:write(packed)

    i = i + current_batch
  end

  f:close()
  return true
end

------------------------------------------------------------------------
-- generate_csv — Gera arquivo CSV multi-colunas de alta velocidade
------------------------------------------------------------------------
function generator.generate_csv(filepath, count, options)
  local f, err = io_open(filepath, "w")
  if not f then return false, err end

  local min_val      = options.min or 1
  local max_val      = options.max or 2000000000
  local dec_chance   = options.decimals or 0
  local neg_chance   = options.negatives or 0
  local empty_chance = options.empty_lines or 0
  local sep          = options.separator or ","
  local cols         = options.cols or 2

  local batch_size = 20000
  local buf = {}
  local bi = 0

  for i = 1, count do
    if empty_chance > 0 and math_random() <= empty_chance then
      bi = bi + 1
      buf[bi] = ""
    else
      local row = {}
      for c = 1, cols do
        local val
        if dec_chance > 0 and math_random() <= dec_chance then
          local diff = max_val - min_val
          val = min_val + math_random() * diff
          val = string_format("%.2f", val)
        else
          local min_i = math_floor(min_val)
          local max_i = math_floor(max_val)
          if min_i >= max_i then
            val = min_i
          else
            val = math_random(min_i, max_i)
          end
        end

        if neg_chance > 0 and math_random() <= neg_chance then
          val = "-" .. val
        end
        row[c] = tostring(val)
      end
      bi = bi + 1
      buf[bi] = table_concat(row, sep)
    end

    if bi >= batch_size then
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
  return true
end

return generator
