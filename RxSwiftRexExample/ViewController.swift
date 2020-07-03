import UIKit
import RxSwift
import SwiftRex

class CounterViewController: UIViewController {
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var counterLabel: UILabel!
    @IBOutlet var minusButton: UIButton!
    @IBOutlet var plusButton: UIButton!
    private let disposeBag = DisposeBag()

    // TODO: Proper dependency injection
    let viewModel = CounterViewModel.viewModel(store: World.default.store())
    // let store = World.default.store() // -> You could use Store directly here, without the ViewModel step
    //                                         That would be a more MVC-ish approach. Having the CounterViewModel
    //                                         layer in between, as a MVVM-ish approach helps to clean-up the code
    //                                         by having a layer for UI formatting logic.
    //                                         In the end, Store and StoreProjection behave identically, but over
    //                                         different generic parameters.

    override func viewDidLoad() {
        super.viewDidLoad()

        // You can optionally use RxCocoa for bindings
        viewModel
            .statePublisher
            .subscribe(onNext: { [weak self] newState in
                guard let self = self else { return }
                self.titleLabel.text = newState.title
                self.counterLabel.text = newState.counterText
                self.minusButton.setTitle(newState.minusButtonTitle, for: .normal)
                self.plusButton.setTitle(newState.plusButtonTitle, for: .normal)
            })
            .disposed(by: disposeBag)

        // You can optionally use RxCocoa for target/action
        minusButton.addTarget(self, action: #selector(tapMinus), for: .touchUpInside)
        plusButton.addTarget(self, action: #selector(tapPlus), for: .touchUpInside)
    }

    @objc private func tapMinus(_ sender: AnyObject) {
        viewModel.dispatch(.tapMinus)
    }

    @objc private func tapPlus(_ sender: AnyObject) {
        viewModel.dispatch(.tapPlus)
    }
}

enum CounterViewModel {
    static func viewModel<S: StoreType>(store: S) -> StoreProjection<ViewEvent, ViewState>
    where S.ActionType == AppAction, S.StateType == AppState {
        store.projection(action: Self.handleViewEvent, state: Self.prepareViewState)
    }

    static func handleViewEvent(_ viewEvent: ViewEvent) -> AppAction? {
        switch viewEvent {
        case .tapMinus: return .counter(.decrease)
        case .tapPlus: return .counter(.increase)
        }
    }

    static func prepareViewState(from state: AppState) -> ViewState {
        ViewState(
            title: NSLocalizedString("Yet another Redux counter", comment: "Title for counter view"),
            counterText: NumberFormatter().string(from: .init(value: state.counter.currentCount)) ?? "0",
            minusButtonTitle: "➖",
            plusButtonTitle: "➕"
        )
    }

    // Having ViewEvents and ViewState is totally optional, but recommended to avoid Model in the ViewController
    // There's an extra effort to make a store projection, but at the same time gives a place to put UI formatting logic

    enum ViewEvent {
        case tapPlus
        case tapMinus
    }

    struct ViewState: Equatable {
        let title: String
        let counterText: String
        let minusButtonTitle: String
        let plusButtonTitle: String
    }

}
