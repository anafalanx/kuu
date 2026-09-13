-- _nearest.lua -- the nearest name to a misspelt one, for a suggestion.
--
-- Damerau-Levenshtein over a set of candidates, with a bound that scales
-- with the name: one mistake for a short name, up to three for a long one.
-- Two letters the wrong way round is one mistake, not two: it is the
-- commonest typo there is, and counting it as two put "file" out of reach
-- of "flie" and "notfound" out of reach of "notfuond".
--
-- Private: check uses it for exports, codes, options and values; task for
-- a task name kuu run does not know.
global none
global <const> pairs, math

-- nearest(name, candidates) -> the closest candidate within the bound, or nil.
-- `candidates` is a set (keys) or a list (values); a list is read by its values.
return function(name, candidates)
  local best, distance
  local function consider(candidate)
    local before, previous = nil, {}
    for j = 0, #candidate do previous[j] = j end
    for i = 1, #name do
      local current = { [0] = i }
      for j = 1, #candidate do
        local d = math.min(current[j - 1] + 1, previous[j] + 1,
          previous[j - 1] + (name:sub(i, i) == candidate:sub(j, j) and 0 or 1))
        if before and i > 1 and j > 1
          and name:sub(i, i) == candidate:sub(j - 1, j - 1)
          and name:sub(i - 1, i - 1) == candidate:sub(j, j) then
          d = math.min(d, before[j - 2] + 1)
        end
        current[j] = d
      end
      before, previous = previous, current
    end
    local d = previous[#candidate]
    if distance == nil or d < distance or (d == distance and candidate < best) then best, distance = candidate, d end
  end
  local listed = candidates[1] ~= nil
  for key, value in pairs(candidates) do
    consider(listed and value or key)
  end
  if distance ~= nil and distance <= math.max(1, math.min(3, #name // 3)) then return best end
end
