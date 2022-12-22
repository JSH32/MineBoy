-- MIT License
--
-- Copyright (c) 2021 JackMacWindows
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

-- FROM: https://gist.github.com/MCJack123/e2a44c3bc80d5a151f0fb69756852019

local expect = require "cc.expect".expect

local imgquant = {}
imgquant.defaultPalette = {}
for i = 0, 15 do
    local r, g, b = term.nativePaletteColor(2^i)
    imgquant.defaultPalette[i+1] = {r * 255, g * 255, b * 255}
end

local names = {'r', 'g', 'b'}
local function getComponent(c, n) return c[n] or c[names[n]] end
local function setComponent(c, n, v) if c[n] then c[n] = v else c[names[n]] = v end end
local function makeRGB(base, r, g, b) if base[1] then return {r, g, b} else return {r = r, g = g, b = b} end end

local function medianCut(pal, num)
    if num == 1 then
        local sum = {r = 0, g = 0, b = 0}
        for _,v in ipairs(pal) do sum.r, sum.g, sum.b = sum.r + getComponent(v, 1), sum.g + getComponent(v, 2), sum.b + getComponent(v, 3) end
        return {makeRGB(pal[1], math.floor(sum.r / #pal), math.floor(sum.g / #pal), math.floor(sum.b / #pal))}
    else
        local red, green, blue = {min = 255, max = 0}, {min = 255, max = 0}, {min = 255, max = 0}
        for _,v in ipairs(pal) do
            local r, g, b = getComponent(v, 1), getComponent(v, 2), getComponent(v, 3)
            red.min, red.max = math.min(r, red.min), math.max(r, red.max)
            green.min, green.max = math.min(g, green.min), math.max(g, green.max)
            blue.min, blue.max = math.min(b, blue.min), math.max(b, blue.max)
        end
        local ranges = {red.max - red.min, green.max - green.min, blue.max - blue.min}
        local maxComponent
        if ranges[1] > ranges[2] and ranges[1] > ranges[3] then maxComponent = 1
        elseif ranges[2] > ranges[3] and ranges[2] > ranges[1] then maxComponent = 2
        else maxComponent = 3 end
        table.sort(pal, function(a, b) return getComponent(a, maxComponent) < getComponent(b, maxComponent) end)
        local a, b = {}, {}
        for i,v in ipairs(pal) do
            if i < #pal / 2 then a[i] = v
            else b[i - math.floor(#pal / 2)] = v end
        end
        local ar, br = medianCut(a, num / 2), medianCut(b, num / 2)
        for _,v in ipairs(br) do ar[#ar+1] = v end
        return ar
    end
end

function imgquant.reducePalette(origpal, numColors)
    expect(1, origpal, "table")
    expect(2, numColors, "number")
    if math.frexp(numColors) > 0.5 then error("bad argument #2 (color count must be a power of 2)", 2) end
    if numColors >= #origpal then return origpal end
    local pal = {}
    for i,v in ipairs(origpal) do pal[i] = v end
    return medianCut(pal, numColors)
end

local function nearestColor(palette, color)
    local nearest = {dist = math.huge}
    for i,v in ipairs(palette) do
        local dist = math.sqrt((getComponent(v, 1) - getComponent(color, 1))^2 + (getComponent(v, 2) - getComponent(color, 2))^2 + (getComponent(v, 3) - getComponent(color, 3))^2)
        if dist < nearest.dist then nearest = {n = i, dist = dist} end
    end
    return makeRGB(color, getComponent(palette[nearest.n], 1), getComponent(palette[nearest.n], 2), getComponent(palette[nearest.n], 3))
end

function imgquant.ditherImage(origimage, palette)
    expect(1, origimage, "table")
    expect(2, palette, "table")
    local image = {}
    for y,r in ipairs(origimage) do
        local nr = {}
        for x,c in ipairs(r) do nr[x] = c end
        image[y] = nr
    end
    for y,r in ipairs(image) do
        for x,c in ipairs(r) do
            local newpixel = nearestColor(palette, c)
            r[x] = newpixel
            local err = {getComponent(c, 1) - getComponent(newpixel, 1), getComponent(c, 2) - getComponent(newpixel, 2), getComponent(c, 3) - getComponent(newpixel, 3)}
            if x < #r then image[y][x+1] = makeRGB(image[y][x+1], getComponent(image[y][x+1], 1) + err[1] * (7/16), getComponent(image[y][x+1], 2) + err[2] * (7/16), getComponent(image[y][x+1], 3) + err[3] * (7/16)) end
            if y < #image then
                if x > 1 then image[y+1][x-1] = makeRGB(image[y+1][x-1], getComponent(image[y+1][x-1], 1) + err[1] * (3/16), getComponent(image[y+1][x-1], 2) + err[2] * (3/16), getComponent(image[y+1][x-1], 3) + err[3] * (3/16)) end
                image[y+1][x] = makeRGB(image[y+1][x], getComponent(image[y+1][x], 1) + err[1] * (5/16), getComponent(image[y+1][x], 2) + err[2] * (5/16), getComponent(image[y+1][x], 3) + err[3] * (5/16))
                if x < #r then image[y+1][x+1] = makeRGB(image[y+1][x+1], getComponent(image[y+1][x+1], 1) + err[1] * (1/16), getComponent(image[y+1][x+1], 2) + err[2] * (1/16), getComponent(image[y+1][x+1], 3) + err[3] * (1/16)) end
            end
        end
    end
    return image
end

function imgquant.rgbToPaletteImage(image, palette, toColors)
    expect(1, image, "table")
    expect(2, palette, "table")
    expect(3, toColors, "boolean", "nil")
    local retval = {}
    for y,r in ipairs(image) do
        local nr = {}
        for x,c in ipairs(r) do
            local found = nil
            for i,v in ipairs(palette) do if getComponent(v, 1) == getComponent(c, 1) and getComponent(v, 2) == getComponent(c, 2) and getComponent(v, 3) == getComponent(c, 3) then found = i break end end
            if found == nil then error("Image contains colors not in palette (" .. c.r .. ", " .. c.g .. ", " .. c.b .. ")", 2) end
            nr[x] = toColors and 2^(found-1) or found
        end
        retval[y] = nr
    end
    return retval
end

function imgquant.extractPalette(image)
    expect(1, image, "table")
    local pal = {}
    for _,r in ipairs(image) do
        for _,c in ipairs(r) do
            local found = false
            for _,v in ipairs(pal) do if v == c or (type(c) == "table" and getComponent(v, 1) == getComponent(c, 1) and getComponent(v, 2) == getComponent(c, 2) and getComponent(v, 3) == getComponent(c, 3)) then found = true break end end
            if not found then pal[#pal+1] = c end
        end
    end
    return pal
end

function imgquant.reduceImage(image, numColors, asPalette, toColors)
    expect(1, image, "table")
    expect(2, numColors, "number")
    expect(3, asPalette, "boolean", "nil")
    expect(4, toColors, "boolean", "nil")
    local oldpal = imgquant.extractPalette(image)
    local newpal = imgquant.reducePalette(oldpal, numColors)
    local img = imgquant.ditherImage(image, newpal)
    if asPalette then return imgquant.rgbToPaletteImage(img, newpal, toColors), newpal
    else return img, newpal end
end

function imgquant.toCCImage(image, palette)
    expect(1, image, "table")
    expect(2, palette, "table")
    local retval = {}
    for y = 0, #image-4, 3 do
        local row = {"", "", ""}
        for x = 0, #image[y+1]-3, 2 do
            local subimg = {{image[y+1][x+1], image[y+1][x+2]}, {image[y+2][x+1], image[y+2][x+2]}, {image[y+3][x+1], image[y+3][x+2]}}
            local used_colors = imgquant.extractPalette(subimg)
            local colors = {image[y+1][x+1], image[y+1][x+2], image[y+2][x+1], image[y+2][x+2], image[y+3][x+1], image[y+3][x+2]}
            if #used_colors == 1 then
                row[1] = row[1] .. " "
                row[2] = row[2] .. "f"
                row[3] = row[3] .. ("0123456789abcdef"):sub(used_colors[1], used_colors[1])
            elseif #used_colors == 2 then
                local char, fg, bg = 128, used_colors[2], used_colors[1]
                for i = 1, 5 do if colors[i] == used_colors[2] then char = char + 2^(i-1) end end
                if colors[6] == used_colors[2] then char, fg, bg = bit32.band(bit32.bnot(char), 0x1F) + 128, bg, fg end
                row[1] = row[1] .. string.char(char)
                row[2] = row[2] .. ("0123456789abcdef"):sub(fg, fg)
                row[3] = row[3] .. ("0123456789abcdef"):sub(bg, bg)
            elseif #used_colors == 3 then
                local color_distances = {}
                local color_map = {}
                local char, fg, bg = 128
                table.sort(used_colors, function(a, b) return (getComponent(palette[a], 1) + getComponent(palette[a], 2) + getComponent(palette[a], 3)) < (getComponent(palette[b], 1) + getComponent(palette[b], 2) + getComponent(palette[b], 3)) end)
                color_distances[1] = math.sqrt((getComponent(palette[used_colors[1]], 1) - getComponent(palette[used_colors[2]], 1))^2 + (getComponent(palette[used_colors[1]], 2) - getComponent(palette[used_colors[2]], 2))^2 + (getComponent(palette[used_colors[1]], 3) - getComponent(palette[used_colors[2]], 3))^2)
                color_distances[2] = math.sqrt((getComponent(palette[used_colors[2]], 1) - getComponent(palette[used_colors[3]], 1))^2 + (getComponent(palette[used_colors[2]], 2) - getComponent(palette[used_colors[3]], 2))^2 + (getComponent(palette[used_colors[2]], 3) - getComponent(palette[used_colors[3]], 3))^2)
                color_distances[3] = math.sqrt((getComponent(palette[used_colors[3]], 1) - getComponent(palette[used_colors[1]], 1))^2 + (getComponent(palette[used_colors[3]], 2) - getComponent(palette[used_colors[1]], 2))^2 + (getComponent(palette[used_colors[3]], 3) - getComponent(palette[used_colors[1]], 3))^2)
                if color_distances[1] - color_distances[2] > 10 then
                    color_map[used_colors[1]] = used_colors[1]
                    color_map[used_colors[2]] = used_colors[3]
                    color_map[used_colors[3]] = used_colors[3] 
                    fg, bg = used_colors[3], used_colors[1]
                elseif color_distances[2] - color_distances[1] > 10 then
                    color_map[used_colors[1]] = used_colors[1]
                    color_map[used_colors[2]] = used_colors[1]
                    color_map[used_colors[3]] = used_colors[3] 
                    fg, bg = used_colors[3], used_colors[1]
                else
                    if (getComponent(palette[used_colors[1]], 1) + getComponent(palette[used_colors[1]], 2) + getComponent(palette[used_colors[1]], 3)) < 32 then
                        color_map[used_colors[1]] = used_colors[2]
                        color_map[used_colors[2]] = used_colors[2]
                        color_map[used_colors[3]] = used_colors[3] 
                        fg, bg = used_colors[2], used_colors[3]
                    elseif (getComponent(palette[used_colors[3]], 1) + getComponent(palette[used_colors[3]], 2) + getComponent(palette[used_colors[3]], 3)) >= 224 then
                        color_map[used_colors[1]] = used_colors[2]
                        color_map[used_colors[2]] = used_colors[3]
                        color_map[used_colors[3]] = used_colors[3]
                        fg, bg = used_colors[2], used_colors[3]
                    else -- Fallback if the algorithm fails
                        color_map[used_colors[1]] = used_colors[2]
                        color_map[used_colors[2]] = used_colors[3]
                        color_map[used_colors[3]] = used_colors[3]
                        fg, bg = used_colors[2], used_colors[3]
                    end
                end
                for i = 1, 5 do if color_map[colors[i]] == fg then char = char + 2^(i-1) end end
                if color_map[colors[6]] == fg then char, fg, bg = bit32.band(bit32.bnot(char), 0x1F) + 128, bg, fg end
                row[1] = row[1] .. string.char(char)
                row[2] = row[2] .. ("0123456789abcdef"):sub(fg, fg)
                row[3] = row[3] .. ("0123456789abcdef"):sub(bg, bg)
            elseif #used_colors == 4 then
                local color_map = {}
                local char, fg, bg = 128
                -- maybe do a real check? this was optimized for grayscale
                color_map[used_colors[1]] = used_colors[2]
                color_map[used_colors[2]] = used_colors[2]
                color_map[used_colors[3]] = used_colors[3]
                color_map[used_colors[4]] = used_colors[3]
                fg, bg = used_colors[2], used_colors[3]
                for i = 1, 5 do if color_map[colors[i]] == fg then char = char + 2^(i-1) end end
                if color_map[colors[6]] == fg then char, fg, bg = bit32.band(bit32.bnot(char), 0x1F) + 128, bg, fg end
                row[1] = row[1] .. string.char(char)
                row[2] = row[2] .. ("0123456789abcdef"):sub(fg, fg)
                row[3] = row[3] .. ("0123456789abcdef"):sub(bg, bg)
            else
                -- Fall back on median cut
                local red, green, blue = {min = 255, max = 0}, {min = 255, max = 0}, {min = 255, max = 0}
                for _,v in ipairs(used_colors) do
                    local r, g, b = getComponent(palette[v], 1), getComponent(palette[v], 2), getComponent(palette[v], 3)
                    red.min, red.max = math.min(r, red.min), math.max(r, red.max)
                    green.min, green.max = math.min(g, green.min), math.max(g, green.max)
                    blue.min, blue.max = math.min(b, blue.min), math.max(b, blue.max)
                end
                local ranges = {red.max - red.min, green.max - green.min, blue.max - blue.min}
                local maxComponent
                if ranges[1] > ranges[2] and ranges[1] > ranges[3] then maxComponent = 1
                elseif ranges[2] > ranges[3] and ranges[2] > ranges[1] then maxComponent = 2
                else maxComponent = 3 end
                table.sort(used_colors, function(a, b) return getComponent(palette[a], maxComponent) < getComponent(palette[b], maxComponent) end)
                local a, b = {}, {}
                for i,v in ipairs(used_colors) do
                    if i < #used_colors / 2 then a[i] = v
                    else b[i - math.floor(#used_colors / 2)] = v end
                end
                local newpal = {palette[a[2]], palette[b[2]]}
                local dimg = imgquant.rgbToPaletteImage(imgquant.ditherImage({{palette[image[y+1][x+1]], palette[image[y+1][x+2]]}, {palette[image[y+2][x+1]], palette[image[y+2][x+2]]}, {palette[image[y+3][x+1]], palette[image[y+3][x+2]]}}, newpal), palette)
                colors = {dimg[1][1], dimg[1][2], dimg[2][1], dimg[2][2], dimg[3][1], dimg[3][2]}
                local char, fg, bg = 128, a[2], b[2]
                for i = 1, 5 do if colors[i] == a[2] then char = char + 2^(i-1) end end
                if colors[6] == a[2] then char, fg, bg = bit32.band(bit32.bnot(char), 0x1F) + 128, bg, fg end
                row[1] = row[1] .. string.char(char)
                row[2] = row[2] .. ("0123456789abcdef"):sub(fg, fg)
                row[3] = row[3] .. ("0123456789abcdef"):sub(bg, bg)
            end
        end
        retval[y/3+1] = row
    end
    return retval, palette
end

function imgquant.toBigCCImage(image, palette)
    expect(1, image, "table")
    expect(2, palette, "table")
    local retval = {}
    local iy = 1
    for y = 1, #image, 3 do
        retval[iy] = {("\143"):rep(#image[y]), "", ""}
        for _,c in ipairs(image[y]) do retval[iy][2] = retval[iy][2] .. ("0123456789abcdef"):sub(c, c) end
        if image[y+1] then
            retval[iy+1] = {("\131"):rep(#image[y]), "", ""}
            for _,c in ipairs(image[y+1]) do
                retval[iy][3] = retval[iy][3] .. ("0123456789abcdef"):sub(c, c)
                retval[iy+1][2] = retval[iy+1][2] .. ("0123456789abcdef"):sub(c, c)
            end
            if image[y+2] then for _,c in ipairs(image[y+2]) do retval[iy+1][3] = retval[iy+1][3] .. ("0123456789abcdef"):sub(c, c) end
            else retval[iy+1][3] = ("0"):rep(#image[y+1]) end
        else retval[iy][3] = ("0"):rep(#image[y]) end
        iy = iy + 2
    end
    return retval, palette
end

function imgquant.reduceCCImage(image)
    expect(1, image, "table")
    return imgquant.toCCImage(imgquant.reduceImage(image, 16, true))
end

function imgquant.reduceBigCCImage(image)
    expect(1, image, "table")
    return imgquant.toBigCCImage(imgquant.reduceImage(image, 16, true))
end

function imgquant.drawBlitImage(x, y, image, palette, terminal)
    expect(1, x, "number")
    expect(2, y, "number")
    expect(3, image, "table")
    expect(4, palette, "table")
    terminal = expect(5, terminal, "table") or term
    for i,v in ipairs(palette) do terminal.setPaletteColor(2^(i-1), getComponent(v, 1) / 255, getComponent(v, 2) / 255, getComponent(v, 3) / 255) end
    for dy,r in ipairs(image) do
        terminal.setCursorPos(x, y+dy-1)
        terminal.blit(r[1], r[2], r[3])
    end
end

return imgquant