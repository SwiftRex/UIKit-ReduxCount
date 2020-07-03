import Foundation
import SwiftRex

enum AppAction {
    case counter(CounterAction)
}

struct AppState: Equatable {
    var counter: CounterState

    static var empty: AppState {
        .init(counter: .empty)
    }
}

enum CounterAction {
    case increase
    case decrease
}

struct CounterState: Equatable {
    var currentCount: Int

    static var empty: CounterState {
        .init(currentCount: 0)
    }
}

extension Reducer where ActionType == CounterAction, StateType == CounterState {
    static let counter = Reducer { action, state in
        var state = state
        switch action {
        case .increase:
            state.currentCount += 1
        case .decrease:
            state.currentCount -= 1
        }
        return state
    }
}

extension Reducer where ActionType == AppAction, StateType == AppState {
    static let app = Reducer<CounterAction, CounterState>.counter.lift(
        action: \AppAction.counter,
        state: \AppState.counter
    )
}

let appMiddleware = IdentityMiddleware<AppAction, AppAction, AppState>()
    .logger()

class Store: ReduxStoreBase<AppAction, AppState> {
    private init() {
        super.init(
            subject: .rx(initialValue: .empty),
            reducer: Reducer.app,
            middleware: appMiddleware
        )
    }

    static let instance = Store()
}

struct World {
    let store: () -> AnyStoreType<AppAction, AppState>
}

extension World {
    static let `default` = World(
        store: { Store.instance.eraseToAnyStoreType() }
    )
}
