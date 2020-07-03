import Foundation
import os.log
import SwiftRex

extension Middleware where StateType: Equatable {
    public func logger(
        actionTransform: @escaping (InputActionType, ActionSource) -> String = {
            "\n🕹 \($0)\n🎪 \($1.file.split(separator: "/").last ?? ""):\($1.line) \($1.function)"
        },
        actionPrinter: @escaping (String) -> Void = { os_log(.debug, log: .default, "%{PUBLIC}@", $0) },
        stateDiffTransform: @escaping (StateType?, StateType) -> String? = {
            let stateBefore = dumpToString($0)
            let stateAfter =  dumpToString($1)
            return Difference.diff(old: stateBefore, new: stateAfter, linesOfContext: 2, prefixLines: "🏛 ")
        },
        stateDiffPrinter: @escaping (String?) -> Void = { state in
            if let state = state {
                os_log(.debug, log: .default, "%{PUBLIC}@", state)
            } else {
                os_log(.debug, log: .default, "%{PUBLIC}@", "🏛 No state mutation")
            }
        },
        queue: DispatchQueue = .main
    ) -> LoggerMiddleware<Self> {
        LoggerMiddleware(
            self,
            actionTransform: actionTransform,
            actionPrinter: actionPrinter,
            stateDiffTransform: stateDiffTransform,
            stateDiffPrinter: stateDiffPrinter,
            queue: queue
        )
    }
}

public final class LoggerMiddleware<M: Middleware>: Middleware where M.StateType: Equatable {
    public typealias InputActionType = M.InputActionType
    public typealias OutputActionType = M.OutputActionType
    public typealias StateType = M.StateType
    private let middleware: M
    private let queue: DispatchQueue
    private var getState: GetState<StateType>?
    private let actionTransform: (InputActionType, ActionSource) -> String
    private let actionPrinter: (String) -> Void
    private let stateDiffTransform: (StateType?, StateType) -> String?
    private let stateDiffPrinter: (String?) -> Void

    init(
        _ middleware: M,
        actionTransform: @escaping (InputActionType, ActionSource) -> String,
        actionPrinter: @escaping (String) -> Void,
        stateDiffTransform: @escaping (StateType?, StateType) -> String?,
        stateDiffPrinter: @escaping (String?) -> Void,
        queue: DispatchQueue
    ) {
        self.middleware = middleware
        self.actionTransform = actionTransform
        self.actionPrinter = actionPrinter
        self.stateDiffTransform = stateDiffTransform
        self.stateDiffPrinter = stateDiffPrinter
        self.queue = queue
    }

    public func receiveContext(getState: @escaping GetState<StateType>, output: AnyActionHandler<OutputActionType>) {
        self.getState = getState
        middleware.receiveContext(getState: getState, output: output)
    }

    public func handle(action: InputActionType, from dispatcher: ActionSource, afterReducer: inout AfterReducer) {
        let stateBefore = getState?()
        var innerAfterReducer = AfterReducer.doNothing()

        middleware.handle(action: action, from: dispatcher, afterReducer: &innerAfterReducer)

        afterReducer = innerAfterReducer <> .do { [weak self] in
            guard let self = self,
                  let stateAfter = self.getState?() else { return }

            self.queue.async {
                let actionMessage = self.actionTransform(action, dispatcher)
                self.actionPrinter(actionMessage)
                self.stateDiffPrinter(self.stateDiffTransform(stateBefore, stateAfter))
            }
        }
    }
}

extension LoggerMiddleware {
    public static func `default`(
        actionTransform: @escaping (InputActionType, ActionSource) -> String = {
            "\n🕹 \($0)\n🎪 \($1.file.split(separator: "/").last ?? ""):\($1.line) \($1.function)"
        },
        actionPrinter: @escaping (String) -> Void = { os_log(.debug, log: .default, "%{PUBLIC}@", $0) },
        stateDiffTransform: @escaping (StateType?, StateType) -> String? = {
            let stateBefore = dumpToString($0)
            let stateAfter =  dumpToString($1)
            return Difference.diff(old: stateBefore, new: stateAfter, linesOfContext: 2, prefixLines: "🏛 ")
        },
        stateDiffPrinter: @escaping (String?) -> Void = { state in
            if let state = state {
                os_log(.debug, log: .default, "%{PUBLIC}@", state)
            } else {
                os_log(.debug, log: .default, "%{PUBLIC}@", "🏛 No state mutation")
            }
        },
        queue: DispatchQueue = .main
    ) -> LoggerMiddleware<IdentityMiddleware<InputActionType, OutputActionType, StateType>> {
        .init(
            IdentityMiddleware(),
            actionTransform: actionTransform,
            actionPrinter: actionPrinter,
            stateDiffTransform: stateDiffTransform,
            stateDiffPrinter: stateDiffPrinter,
            queue: queue
        )
    }
}

public func dumpToString<T>(_ something: T, indent: Int = 2) -> String {
    var output = ""
    dump(something, to: &output, name: nil, indent: indent)
    return output
}

public struct Difference<A> {
    public enum Which {
        case first
        case second
        case both
    }

    public let elements: [A]
    public let which: Which
}

extension Difference where A == String {
    public static func diff(old: String, new: String, linesOfContext: Int, prefixLines: String = "") -> String? {
        guard old != new else { return nil }
        let oldSplit = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newSplit = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        return chunk(
            diff: Difference.diff(oldSplit, newSplit),
            context: linesOfContext
        ).lazy.flatMap { [$0.patchMark] + $0.lines }.map { "\(prefixLines)\($0)" }.joined(separator: "\n")
    }
}

extension Difference where A == String {
    public static func diff(_ fst: [String], _ snd: [String]) -> [Difference<String>] {
        var idxsOf = [String: [Int]]()
        fst.enumerated().forEach { idxsOf[$1, default: []].append($0) }

        let sub = snd.enumerated().reduce((overlap: [Int: Int](), fst: 0, snd: 0, len: 0)) { sub, sndPair in
            (idxsOf[sndPair.element] ?? [])
                .reduce((overlap: [Int: Int](), fst: sub.fst, snd: sub.snd, len: sub.len)) { innerSub, fstIdx in

                    var newOverlap = innerSub.overlap
                    newOverlap[fstIdx] = (sub.overlap[fstIdx - 1] ?? 0) + 1

                    if let newLen = newOverlap[fstIdx], newLen > sub.len {
                        return (newOverlap, fstIdx - newLen + 1, sndPair.offset - newLen + 1, newLen)
                    }
                    return (newOverlap, innerSub.fst, innerSub.snd, innerSub.len)
            }
        }
        let (_, fstIdx, sndIdx, len) = sub

        if len == 0 {
            let fstDiff = fst.isEmpty ? [] : [Difference(elements: fst, which: .first)]
            let sndDiff = snd.isEmpty ? [] : [Difference(elements: snd, which: .second)]
            return fstDiff + sndDiff
        } else {
            let fstDiff = diff(Array(fst.prefix(upTo: fstIdx)), Array(snd.prefix(upTo: sndIdx)))
            let midDiff = [Difference(elements: Array(fst.suffix(from: fstIdx).prefix(len)), which: .both)]
            let lstDiff = diff(Array(fst.suffix(from: fstIdx + len)), Array(snd.suffix(from: sndIdx + len)))
            return fstDiff + midDiff + lstDiff
        }
    }
}

let minus = "−"
let plus = "+"
private let figureSpace = "\u{2007}"

struct Hunk {
    let fstIdx: Int
    let fstLen: Int
    let sndIdx: Int
    let sndLen: Int
    let lines: [String]

    var patchMark: String {
        let fstMark = "\(minus)\(fstIdx + 1),\(fstLen)"
        let sndMark = "\(plus)\(sndIdx + 1),\(sndLen)"
        return "@@ \(fstMark) \(sndMark) @@"
    }

    // Semigroup
    static func + (lhs: Hunk, rhs: Hunk) -> Hunk {
        return Hunk(
            fstIdx: lhs.fstIdx + rhs.fstIdx,
            fstLen: lhs.fstLen + rhs.fstLen,
            sndIdx: lhs.sndIdx + rhs.sndIdx,
            sndLen: lhs.sndLen + rhs.sndLen,
            lines: lhs.lines + rhs.lines
        )
    }

    // Monoid
    init(fstIdx: Int = 0, fstLen: Int = 0, sndIdx: Int = 0, sndLen: Int = 0, lines: [String] = []) {
        self.fstIdx = fstIdx
        self.fstLen = fstLen
        self.sndIdx = sndIdx
        self.sndLen = sndLen
        self.lines = lines
    }

    init(idx: Int = 0, len: Int = 0, lines: [String] = []) {
        self.init(fstIdx: idx, fstLen: len, sndIdx: idx, sndLen: len, lines: lines)
    }
}

func chunk(diff diffs: [Difference<String>], context ctx: Int = 4) -> [Hunk] {
    func prepending(_ prefix: String) -> (String) -> String {
        return { prefix + $0 + ($0.hasSuffix(" ") ? "¬" : "") }
    }
    let changed: (Hunk) -> Bool = { $0.lines.contains(where: { $0.hasPrefix(minus) || $0.hasPrefix(plus) }) }

    let (hunk, hunks) = diffs
        .reduce((current: Hunk(), hunks: [Hunk]())) { cursor, diff in
            let (current, hunks) = cursor
            let len = diff.elements.count

            switch diff.which {
            case .both where len > ctx * 2:
                let hunk = current + Hunk(len: ctx, lines: diff.elements.prefix(ctx).map(prepending(figureSpace)))
                let next = Hunk(
                    fstIdx: current.fstIdx + current.fstLen + len - ctx,
                    fstLen: ctx,
                    sndIdx: current.sndIdx + current.sndLen + len - ctx,
                    sndLen: ctx,
                    lines: (diff.elements.suffix(ctx) as ArraySlice<String>).map(prepending(figureSpace))
                )
                return (next, changed(hunk) ? hunks + [hunk] : hunks)
            case .both where current.lines.isEmpty:
                let lines = (diff.elements.suffix(ctx) as ArraySlice<String>).map(prepending(figureSpace))
                let count = lines.count
                return (current + Hunk(idx: len - count, len: count, lines: lines), hunks)
            case .both:
                return (current + Hunk(len: len, lines: diff.elements.map(prepending(figureSpace))), hunks)
            case .first:
                return (current + Hunk(fstLen: len, lines: diff.elements.map(prepending(minus))), hunks)
            case .second:
                return (current + Hunk(sndLen: len, lines: diff.elements.map(prepending(plus))), hunks)
            }
    }

    return changed(hunk) ? hunks + [hunk] : hunks
}
