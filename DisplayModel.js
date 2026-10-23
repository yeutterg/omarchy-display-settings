.pragma library

function clone(value) { return JSON.parse(JSON.stringify(value)) }

function friendlyName(display) {
  if (!display) return "Display"
  var connector = String(display.name || "")
  var make = String(display.make || "")
  var model = String(display.model || "")
  var description = String(display.description || "")
  if (/^eDP(?:-|$)/i.test(connector)) return "Built-in Display"
  if (/apple/i.test(make + " " + description)
      && /studio\s*display/i.test(model + " " + description))
    return "Apple Studio Display"
  if (model && !/^(unknown|display|monitor)$/i.test(model))
    return model.replace(/([a-z])([A-Z])/g, "$1 $2")
  return description || connector || "Display"
}

function modeParts(mode) {
  var match = String(mode || "").match(/^(\d+)x(\d+)@(\d+(?:\.\d+)?)/)
  return match ? { width: Number(match[1]), height: Number(match[2]), refresh: Number(match[3]) } : null
}

function resolution(mode) {
  var p = modeParts(mode)
  return p ? p.width + "x" + p.height : ""
}

function refresh(mode) {
  var p = modeParts(mode)
  return p ? String(Math.round(p.refresh * 100) / 100) : ""
}

function canonicalMode(mode) {
  var p = modeParts(mode)
  return p ? p.width + "x" + p.height + "@" + (Math.round(p.refresh * 100) / 100) : String(mode || "preferred")
}

function modesForResolution(modes, wanted) {
  return (modes || []).filter(function(mode) { return resolution(mode) === wanted })
}

function refreshOptions(modes, wanted) {
  var seen = {}, result = []
  modesForResolution(modes, wanted).forEach(function(mode) {
    var value = refresh(mode)
    if (value && !seen[value]) {
      seen[value] = true
      result.push({ value: value, label: value + " Hz" })
    }
  })
  return result
}

function resolutions(modes) {
  var seen = {}, result = []
  ;(modes || []).forEach(function(mode) {
    var value = resolution(mode)
    if (value && !seen[value]) { seen[value] = true; result.push(value) }
  })
  return result
}

function resolutionOptions(modes) {
  var values = resolutions(modes)
  return values.map(function(value) {
    return {
      value: value,
      label: values.length === 1 ? value + " (native)" : value
    }
  })
}

function validScales(mode) {
  var p = modeParts(mode)
  if (!p) return [1]
  // Common integer, Windows-style, and fractional Wayland scales. Filter out
  // values that would create fractional logical pixels for the chosen mode.
  var candidates = [1, 1.2, 1.25, 4 / 3, 1.5, 1.6, 1.75, 2, 2.25, 2.5, 3, 4]
  return candidates.filter(function(scale) {
    return Math.abs(p.width / scale - Math.round(p.width / scale)) < 0.0001
      && Math.abs(p.height / scale - Math.round(p.height / scale)) < 0.0001
  })
}

function logicalSize(display) {
  var p = modeParts(display.mode) || { width: display.width || 0, height: display.height || 0 }
  var scale = Number(display.scale) || 1
  var rotated = Number(display.transform) % 2 === 1
  return {
    width: Math.round((rotated ? p.height : p.width) / scale),
    height: Math.round((rotated ? p.width : p.height) / scale)
  }
}

function overlap(a, b) {
  if (a.disabled || b.disabled || a.mirror || b.mirror) return false
  var as = logicalSize(a), bs = logicalSize(b)
  return a.x < b.x + bs.width && a.x + as.width > b.x
      && a.y < b.y + bs.height && a.y + as.height > b.y
}

function hasOverlap(displays) {
  for (var i = 0; i < displays.length; i++)
    for (var j = i + 1; j < displays.length; j++)
      if (overlap(displays[i], displays[j])) return true
  return false
}

function touches(a, b) {
  if (a.disabled || b.disabled || a.mirror || b.mirror) return false
  var as = logicalSize(a), bs = logicalSize(b)
  var verticalSpan = a.y < b.y + bs.height && a.y + as.height > b.y
  var horizontalSpan = a.x < b.x + bs.width && a.x + as.width > b.x
  return (verticalSpan && (a.x + as.width === b.x || b.x + bs.width === a.x))
      || (horizontalSpan && (a.y + as.height === b.y || b.y + bs.height === a.y))
}

function isConnected(displays) {
  var active = (displays || []).filter(function(d) { return !d.disabled && !d.mirror })
  if (active.length <= 1) return true
  var visited = [0]
  for (var cursor = 0; cursor < visited.length; cursor++) {
    for (var candidate = 0; candidate < active.length; candidate++) {
      if (visited.indexOf(candidate) < 0 && touches(active[visited[cursor]], active[candidate]))
        visited.push(candidate)
    }
  }
  return visited.length === active.length
}

function normalizePositions(displays) {
  var copy = clone(displays), minX = Infinity, minY = Infinity
  copy.forEach(function(d) {
    if (!d.disabled && !d.mirror) { minX = Math.min(minX, d.x); minY = Math.min(minY, d.y) }
  })
  if (!isFinite(minX)) return copy
  copy.forEach(function(d) {
    if (!d.disabled && !d.mirror) { d.x -= minX; d.y -= minY }
  })
  return copy
}

function nearestAxis(value, candidates, threshold) {
  var best = value, distance = threshold + 1
  candidates.forEach(function(candidate) {
    var delta = Math.abs(value - candidate)
    if (delta < distance) { best = candidate; distance = delta }
  })
  return distance <= threshold ? best : value
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value))
}

// Mandatory edge attachment for the visual canvas. Every candidate shares a
// useful stretch of one edge with another display, and candidates that would
// overlap any display are rejected. Alignment remains magnetic near matching
// top/centre/bottom or left/centre/right positions.
function snapPosition(displays, index, wantedX, wantedY, threshold) {
  var current = displays[index]
  if (!current || current.disabled || current.mirror) return { x: wantedX, y: wantedY }
  var size = logicalSize(current)
  var best = null

  function consider(x, y) {
    var candidateX = Math.round(x), candidateY = Math.round(y)
    var copy = clone(displays)
    copy[index].x = candidateX
    copy[index].y = candidateY
    if (hasOverlap(copy) || !isConnected(copy)) return
    var dx = candidateX - wantedX, dy = candidateY - wantedY
    var distance = dx * dx + dy * dy
    if (!best || distance < best.distance)
      best = { x: candidateX, y: candidateY, distance: distance }
  }

  displays.forEach(function(other, otherIndex) {
    if (otherIndex === index || other.disabled || other.mirror) return
    var otherSize = logicalSize(other)
    var sharedY = Math.max(1, Math.min(80, size.height, otherSize.height))
    var minY = other.y - size.height + sharedY
    var maxY = other.y + otherSize.height - sharedY
    var alignedY = nearestAxis(wantedY, [other.y, other.y + (otherSize.height - size.height) / 2, other.y + otherSize.height - size.height], threshold)
    var yChoices = [clamp(alignedY, minY, maxY), minY, maxY]
    ;[other.x - size.width, other.x + otherSize.width].forEach(function(x) {
      yChoices.forEach(function(y) { consider(x, y) })
    })

    var sharedX = Math.max(1, Math.min(80, size.width, otherSize.width))
    var minX = other.x - size.width + sharedX
    var maxX = other.x + otherSize.width - sharedX
    var alignedX = nearestAxis(wantedX, [other.x, other.x + (otherSize.width - size.width) / 2, other.x + otherSize.width - size.width], threshold)
    var xChoices = [clamp(alignedX, minX, maxX), minX, maxX]
    ;[other.y - size.height, other.y + otherSize.height].forEach(function(y) {
      xChoices.forEach(function(x) { consider(x, y) })
    })
  })

  if (best) return { x: best.x, y: best.y }
  return { x: Math.round(current.x), y: Math.round(current.y) }
}

function nearestMode(modes, wantedResolution, wantedRefresh) {
  var choices = modesForResolution(modes, wantedResolution)
  if (!choices.length) return modes && modes.length ? modes[0] : "preferred"
  var target = Number(wantedRefresh), best = choices[0], distance = Infinity
  choices.forEach(function(mode) {
    var delta = Math.abs(Number(refresh(mode)) - target)
    if (delta < distance) { best = mode; distance = delta }
  })
  return canonicalMode(best)
}
