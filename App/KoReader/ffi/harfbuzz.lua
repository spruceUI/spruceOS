local coverage = require("ffi/harfbuzz_coverage")
local ffi = require("ffi")
local hb = ffi.load("libs/libharfbuzz." .. (ffi.os == "OSX" and "0.dylib" or "so.0"))
local HB = setmetatable({}, {__index = hb})

require("ffi/harfbuzz_h")

local hb_face_t = {}
hb_face_t.__index = hb_face_t
ffi.metatype("hb_face_t", hb_face_t)

-- Dump contents of OT name fields
function hb_face_t:getNames(maxlen)
    maxlen = maxlen or 256
    local n = ffi.new("unsigned[1]")
    local list = hb.hb_ot_name_list_names(self, n)
    if list == nil then return end
    local buf = ffi.new("char[?]", maxlen)
    local res = {}
    for i=0, n[0]-1 do
        local name_id = list[i].name_id
        local hb_lang = list[i].language
        local lang = hb.hb_language_to_string(hb_lang)
        if lang ~= nil then
            lang = ffi.string(lang)
            local got = hb.hb_ot_name_get_utf8(self, name_id, hb_lang, ffi.new("unsigned[1]", maxlen), buf)
            name_id = tonumber(name_id)
            if got > 0 then
                res[lang] = res[lang] or {}
                res[lang][name_id] = ffi.string(buf)
            end
        end
    end
    return res
end

-- Alphabets are subset of a larger script - just enough for a specific language.
-- This is used to mark face as eligibile to speak some tongue in particular.
-- Later on the results are sorted by best ratio still, when multiple choices are available.
-- TODO: These numbers are ballkpark, tweak this to more real-world defaults
local coverage_thresholds = {
    -- nglyph   coverage %
    0,          100,    -- Simple alphabets of 0-100 glyphs. Be strict, all glyphs are typically in use.
    100,        99,     -- 100-250 glyphs. abundant diacritics, allow for 1% missing, typically some archaisms
    250,        98,     -- 250-1000 glyphs. even more diacritics (eg cyrillic dialects), allow for 2% missing
    1000,       85,     -- 1000 and more = CJK, allow for 15% missing
}

-- Get script and language coverage
function hb_face_t:getCoverage()
    local set, tmp = hb.hb_set_create(), hb.hb_set_create()
    local scripts = {}
    local langs = {}

    hb.hb_face_collect_unicodes(self, set)

    local function intersect(tab)
        hb.hb_set_set(tmp, set)
        hb.hb_set_intersect(tmp, tab)
        return hb.hb_set_get_population(tmp), hb.hb_set_get_population(tab)
    end

    for script_id, tab in ipairs(coverage.scripts) do
        local hit, total = intersect(tab)
        -- for scripts, we do only rough majority hit
        if 2*hit > total then
            scripts[script_id] = hit / total
        end
    end

    for lang_id, tab in pairs(coverage.langs) do
        local found
        local hit, total = intersect(tab)
        -- for languages, consider predefined threshold by glyph count
        for i=1, #coverage_thresholds, 2 do
            if total > coverage_thresholds[i] then
                found = i+1
            end
        end
        if hit*100/total >= coverage_thresholds[found] then
            langs[lang_id] = hit/total
        end
    end

    hb.hb_set_destroy(set)
    hb.hb_set_destroy(tmp)
    return scripts, langs
end

function hb_face_t:destroy()
    hb.hb_face_destroy(self)
end

-- private

-- preprocess the script/language tables into HB range sets
local function make_set(tab)
    local set = ffi.gc(hb.hb_set_create(), hb.hb_set_destroy)
    local first = 0
    local seen = 0
    for i=1, #tab, 2 do
        first = first + tab[i]
        local count = tab[i+1]
        seen = seen + count
        local last = first + count - 1
        hb.hb_set_add_range(set, first, last)
        first = last
    end
    assert(hb.hb_set_get_population(set) == seen, "invalid coverage table")
    return set
end

for ucd_id, ranges in ipairs(coverage.scripts) do
    coverage.scripts[ucd_id] = make_set(ranges)
end

for lang_id, ranges in pairs(coverage.langs) do
    coverage.langs[lang_id] = make_set(ranges)
end


return HB
