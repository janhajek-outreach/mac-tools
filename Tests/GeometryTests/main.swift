import CoreGraphics
import MacToolsGeometry

// A tiny dependency-free test harness so tests run without Xcode/XCTest:
//   swift run GeometryTests
// Exits non-zero if any check fails.

var failures = 0
var checks = 0

func check(_ condition: Bool, _ message: String, line: Int = #line) {
    checks += 1
    if condition {
        print("  ok  \(message)")
    } else {
        failures += 1
        print("FAIL  \(message)  (line \(line))")
    }
}

func approx(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 0.001) -> Bool { abs(a - b) <= tol }

func section(_ name: String) { print("\n# \(name)") }

// The user's real layout (CG top-left space), left→right:
//   left external, middle/main, built-in Retina (shorter & narrower).
let leftFull    = CGRect(x: -2560, y: 0,   width: 2560, height: 1440)
let midFull     = CGRect(x: 0,     y: 0,   width: 2560, height: 1440)
let builtInFull = CGRect(x: 2560,  y: 458, width: 1512, height: 982)

let leftVis     = CGRect(x: -2560, y: 0,   width: 2560, height: 1440)
let midVis      = CGRect(x: 0,     y: 30,  width: 2560, height: 1345)
let builtInVis  = CGRect(x: 2560,  y: 490, width: 1512, height: 950)

let fulls = [leftFull, midFull, builtInFull]

// MARK: flipToCG
section("flipToCG")
do {
    let ns = CGRect(x: 2560, y: 0, width: 1512, height: 982)   // built-in in AppKit coords
    let cg = WindowGeometry.flipToCG(ns, primaryTop: 1440)
    check(cg == CGRect(x: 2560, y: 458, width: 1512, height: 982), "bottom-aligned screen flips about primaryTop")
}

// MARK: ordering
section("orderedIndices")
do {
    let order = WindowGeometry.orderedIndices(of: [builtInFull, leftFull, midFull])
    check(order == [1, 2, 0], "sorted left→right returns original indices")
}

// MARK: screen detection
section("screenIndex")
do {
    check(WindowGeometry.screenIndex(containing: CGRect(x: 100, y: 100, width: 1200, height: 800), in: fulls) == 1, "window on middle → 1")
    check(WindowGeometry.screenIndex(containing: CGRect(x: 2700, y: 600, width: 1000, height: 700), in: fulls) == 2, "window on built-in → 2")
    check(WindowGeometry.screenIndex(containing: CGRect(x: -2000, y: 200, width: 900, height: 600), in: fulls) == 0, "window on left → 0")

    // Right edge exactly on the mid/built-in boundary (x=2560): zero-area overlap with the
    // built-in, so it must resolve to the middle display, not skip to the next.
    check(WindowGeometry.screenIndex(containing: CGRect(x: 1360, y: 100, width: 1200, height: 800), in: fulls) == 1, "window touching boundary stays on its display")

    // Zero-area window: center fallback (center in middle display).
    check(WindowGeometry.screenIndex(containing: CGRect(x: 500, y: 500, width: 0, height: 0), in: fulls) == 1, "center fallback when no overlap")
}

// MARK: halves
section("halves")
do {
    let (l, r) = WindowGeometry.halves(of: midVis)
    check(approx(l.minX, midVis.minX), "left starts at visible minX")
    check(approx(r.maxX, midVis.maxX), "right ends at visible maxX")
    check(approx(l.maxX, r.minX), "no gap / no overlap between halves")
    check(approx(l.width + r.width, midVis.width), "halves cover full width")
    check(l.height == midVis.height && r.height == midVis.height, "halves keep full height")
}

// MARK: isMaximized
section("isMaximized")
do {
    let almost = CGRect(x: midVis.minX + 3, y: midVis.minY - 4, width: midVis.width - 5, height: midVis.height + 2)
    check(WindowGeometry.isMaximized(almost, in: midVis), "true within tolerance")
    check(!WindowGeometry.isMaximized(CGRect(x: 100, y: 100, width: 800, height: 600), in: midVis), "false when clearly smaller")
}

// MARK: mappedFrame (proportional resize)
section("mappedFrame")
do {
    // Full middle display → full built-in display.
    let full = WindowGeometry.mappedFrame(window: midVis, from: midVis, to: builtInVis)
    check(approx(full.origin.x, builtInVis.minX) && approx(full.origin.y, builtInVis.minY)
          && approx(full.width, builtInVis.width) && approx(full.height, builtInVis.height),
          "maximized window fills the narrower display")

    // Half-size window keeps ~half footprint on the target (i.e. it resizes).
    let win = CGRect(x: midVis.minX + midVis.width * 0.25, y: midVis.minY + midVis.height * 0.25,
                     width: midVis.width * 0.5, height: midVis.height * 0.5)
    let mapped = WindowGeometry.mappedFrame(window: win, from: midVis, to: builtInVis)
    check(approx(mapped.width, builtInVis.width * 0.5, 0.5), "width scales to ~half of target")
    check(approx(mapped.height, builtInVis.height * 0.5, 0.5), "height scales to ~half of target")
    check(approx(mapped.midX, builtInVis.midX, 1.0), "stays horizontally centered")
    check(approx(mapped.midY, builtInVis.midY, 1.0), "stays vertically centered")

    // Always fully inside the destination.
    let edge = WindowGeometry.mappedFrame(window: CGRect(x: midVis.maxX - 1000, y: midVis.minY, width: 1000, height: 1000), from: midVis, to: builtInVis)
    check(edge.minX >= builtInVis.minX - 0.001 && edge.maxX <= builtInVis.maxX + 0.001
          && edge.minY >= builtInVis.minY - 0.001 && edge.maxY <= builtInVis.maxY + 0.001,
          "result stays within destination bounds")
}

// MARK: full move cycle — the reported "skips the middle display" bug
section("next cycle advances one display at a time")
do {
    let vis = [leftVis, midVis, builtInVis]
    var frame = CGRect(x: leftVis.minX + 100, y: leftVis.minY + 100, width: 900, height: 700)
    var index = WindowGeometry.screenIndex(containing: frame, in: fulls)
    check(index == 0, "starts on left display")
    for step in 1...4 {
        let target = (index + 1) % 3
        frame = WindowGeometry.mappedFrame(window: frame, from: vis[index], to: vis[target])
        let detected = WindowGeometry.screenIndex(containing: frame, in: fulls)
        check(detected == target, "step \(step): landed on display \(target) (got \(detected))")
        index = target
    }
}

// MARK: summary
print("\n\(checks - failures)/\(checks) checks passed")
if failures > 0 {
    print("\(failures) FAILED")
    exit(1)
}
print("ALL PASSED")
