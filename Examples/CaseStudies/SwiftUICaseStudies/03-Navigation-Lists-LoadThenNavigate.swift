import ComposableArchitecture
import Foundation
import SwiftUI

private let readMe = """
  This screen demonstrates navigation that depends on loading optional state from a list element.

  Tapping a row fires off an effect that will load its associated counter state a second later. \
  When the counter state is present, you will be programmatically navigated to the screen that \
  depends on this data.
  """

struct LoadThenNavigateListState: Equatable {
  var rows: IdentifiedArrayOf<Row> = [
    Row(count: 1, id: UUID()),
    Row(count: 42, id: UUID()),
    Row(count: 100, id: UUID()),
  ]
  var selection: Identified<Row.ID, CounterState>?

  struct Row: Equatable, Identifiable {
    var count: Int
    let id: UUID
    var isActivityIndicatorVisible = false
  }
}

enum LoadThenNavigateListAction: Equatable {
  case counter(CounterAction)
  case onDisappear
  case setNavigation(selection: UUID?)
  case setNavigationSelectionDelayCompleted(UUID)
}

struct LoadThenNavigateListEnvironment {
  var mainQueue: AnySchedulerOf<DispatchQueue>
}

let loadThenNavigateListReducer =
  counterReducer
  .pullback(
    state: \Identified.value,
    action: .self,
    environment: { $0 }
  )
  .optional()
  .pullback(
    state: \LoadThenNavigateListState.selection,
    action: /LoadThenNavigateListAction.counter,
    environment: { _ in CounterEnvironment() }
  )
  .combined(
    with: Reducer<
      LoadThenNavigateListState, LoadThenNavigateListAction, LoadThenNavigateListEnvironment
    > { state, action, environment in

      enum CancelID {}

      switch action {
      case .counter:
        return .none

      case .onDisappear:
        return .cancel(id: CancelID.self)

      case let .setNavigation(selection: .some(navigatedId)):
        for row in state.rows {
          state.rows[id: row.id]?.isActivityIndicatorVisible = row.id == navigatedId
        }
        return .task {
          try await environment.mainQueue.sleep(for: 1)
          return .setNavigationSelectionDelayCompleted(navigatedId)
        }
        .cancellable(id: CancelID.self, cancelInFlight: true)

      case .setNavigation(selection: .none):
        if let selection = state.selection {
          state.rows[id: selection.id]?.count = selection.count
        }
        state.selection = nil
        return .cancel(id: CancelID.self)

      case let .setNavigationSelectionDelayCompleted(id):
        state.rows[id: id]?.isActivityIndicatorVisible = false
        state.selection = Identified(
          CounterState(count: state.rows[id: id]?.count ?? 0),
          id: id
        )
        return .none
      }
    }
  )

struct LoadThenNavigateListView: View {
  let store: Store<LoadThenNavigateListState, LoadThenNavigateListAction>

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      Form {
        Section {
          AboutView(readMe: readMe)
        }
        ForEach(viewStore.rows) { row in
          NavigationLink(
            destination: IfLetStore(
              self.store.scope(
                state: \.selection?.value,
                action: LoadThenNavigateListAction.counter
              )
            ) {
              CounterView(store: $0)
            },
            tag: row.id,
            selection: viewStore.binding(
              get: \.selection?.id,
              send: LoadThenNavigateListAction.setNavigation(selection:)
            )
          ) {
            HStack {
              Text("Load optional counter that starts from \(row.count)")
              if row.isActivityIndicatorVisible {
                Spacer()
                ProgressView()
              }
            }
          }
        }
      }
      .navigationTitle("Load then navigate")
      .onDisappear { viewStore.send(.onDisappear) }
    }
  }
}

struct LoadThenNavigateListView_Previews: PreviewProvider {
  static var previews: some View {
    NavigationView {
      LoadThenNavigateListView(
        store: Store(
          initialState: LoadThenNavigateListState(
            rows: [
              LoadThenNavigateListState.Row(count: 1, id: UUID()),
              LoadThenNavigateListState.Row(count: 42, id: UUID()),
              LoadThenNavigateListState.Row(count: 100, id: UUID()),
            ]
          ),
          reducer: loadThenNavigateListReducer,
          environment: LoadThenNavigateListEnvironment(
            mainQueue: .main
          )
        )
      )
    }
    .navigationViewStyle(.stack)
  }
}
