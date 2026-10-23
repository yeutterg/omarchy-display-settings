const fs = require("fs")
const vm = require("vm")
const assert = require("assert")

const path = require("path")
const source = fs.readFileSync(path.join(__dirname, "../DisplayModel.js"), "utf8")
  .replace(/^\.pragma library\s*/m, "")
const context = { JSON, Math, Number, String, Array, Object, isFinite }
vm.createContext(context)
vm.runInContext(source, context)

assert.strictEqual(context.friendlyName({ name: "DP-4", make: "Apple Computer Inc", model: "StudioDisplay" }), "Apple Studio Display")
assert.strictEqual(context.friendlyName({ name: "eDP-1", make: "Tianma", model: "TL134ADXP03" }), "Built-in Display")
assert.strictEqual(context.friendlyName({ name: "DP-1", make: "Dell", model: "U2723QE" }), "U2723QE")
assert.deepStrictEqual(Array.from(context.resolutions(["1920x1080@60", "1920x1080@144", "2560x1440@60"])), ["1920x1080", "2560x1440"])
assert.strictEqual(context.resolutionOptions(["3840x2400@59.99Hz", "3840x2400@47.99Hz"])[0].label, "3840x2400 (native)")
assert.strictEqual(context.nearestMode(["1920x1080@60", "1920x1080@144"], "1920x1080", 120), "1920x1080@144")
assert.strictEqual(context.nearestMode(["3440x1440@59.97Hz"], "3440x1440", 60), "3440x1440@59.97")
assert.deepStrictEqual(JSON.parse(JSON.stringify(context.refreshOptions(["1920x1080@60.00Hz", "1920x1080@60.00Hz", "1920x1080@59.94Hz"], "1920x1080"))), [
  { value: "60", label: "60 Hz" },
  { value: "59.94", label: "59.94 Hz" }
])
assert.deepStrictEqual(Array.from(context.resolutions(["7680x4320@30.00Hz", "5120x1440@120.00Hz", "3440x1440@59.97Hz"])), ["7680x4320", "5120x1440", "3440x1440"])
assert.strictEqual(context.logicalSize({ mode: "3840x2160@60", scale: 2, transform: 0 }).width, 1920)
assert.strictEqual(context.logicalSize({ mode: "1920x1080@60", scale: 1, transform: 1 }).width, 1080)
assert.strictEqual(context.hasOverlap([
  { mode: "1920x1080@60", scale: 1, transform: 0, x: 0, y: 0 },
  { mode: "1920x1080@60", scale: 1, transform: 0, x: 1800, y: 0 }
]), true)
assert.strictEqual(context.hasOverlap([
  { mode: "1920x1080@60", scale: 1, transform: 0, x: 0, y: 0 },
  { mode: "1920x1080@60", scale: 1, transform: 0, x: 1920, y: 0 }
]), false)
assert.strictEqual(context.isConnected([
  { mode: "1920x1080@60", scale: 1, transform: 0, x: 0, y: 0 },
  { mode: "1920x1080@60", scale: 1, transform: 0, x: 1920, y: 500 }
]), true)
assert.strictEqual(context.isConnected([
  { mode: "1920x1080@60", scale: 1, transform: 0, x: 0, y: 0 },
  { mode: "1920x1080@60", scale: 1, transform: 0, x: 1921, y: 0 }
]), false)
assert.strictEqual(context.isConnected([
  { mode: "100x100@60", scale: 1, transform: 0, x: 0, y: 0 },
  { mode: "100x100@60", scale: 1, transform: 0, x: 100, y: 0 },
  { mode: "100x100@60", scale: 1, transform: 0, x: 200, y: 0 }
]), true)
assert.deepStrictEqual(Array.from(context.validScales("1920x1080@60")), [1, 1.2, 1.25, 4 / 3, 1.5, 1.6, 2, 2.5, 3, 4])
assert.ok(context.validScales("3840x2160@60").indexOf(4 / 3) >= 0)

const snapDisplays = [
  { mode: "1920x1080@60", scale: 1, transform: 0, x: 0, y: 0 },
  { mode: "2560x1440@60", scale: 1, transform: 0, x: 1920, y: 0 }
]
assert.deepStrictEqual(
  JSON.parse(JSON.stringify(context.snapPosition(snapDisplays, 1, 1888, 14, 40))),
  { x: 1920, y: 0 }
)
assert.deepStrictEqual(
  JSON.parse(JSON.stringify(context.snapPosition(snapDisplays, 1, 700, 1097, 40))),
  { x: 700, y: 1080 }
)
const forcedAttachment = context.snapPosition(snapDisplays, 1, 5000, 5000, 40)
const forcedLayout = JSON.parse(JSON.stringify(snapDisplays))
forcedLayout[1].x = forcedAttachment.x
forcedLayout[1].y = forcedAttachment.y
assert.strictEqual(context.hasOverlap(forcedLayout), false)
assert.strictEqual(context.isConnected(forcedLayout), true)

// Moving the middle display in a chain must not strand the display attached
// through it. If no closer valid bridge exists, it stays in a connected spot.
const chain = [
  { mode: "100x100@60", scale: 1, transform: 0, x: 0, y: 0 },
  { mode: "100x100@60", scale: 1, transform: 0, x: 100, y: 0 },
  { mode: "100x100@60", scale: 1, transform: 0, x: 200, y: 0 }
]
const bridge = context.snapPosition(chain, 1, 0, 500, 20)
chain[1].x = bridge.x
chain[1].y = bridge.y
assert.strictEqual(context.hasOverlap(chain), false)
assert.strictEqual(context.isConnected(chain), true)

console.log("DisplayModel tests passed")
