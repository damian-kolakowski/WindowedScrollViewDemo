import SwiftUI

/// Renders a fixed `0..<store.totalCount` range over a sparse index-addressed cache, so an
/// index whose page isn't resident draws a placeholder of the same height instead of
/// disappearing from the list. The content height stays constant across page loads and
/// evictions, which is what keeps the scroll position stable.
struct WindowedTodoScrollView: View {
    @StateObject private var store = WindowedTodoStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<store.totalCount, id: \.self) { index in
                        TodoRowView(
                            todo: store.items[index],
                            onToggle: { store.toggleTodo(id: $0) },
                            onDelete: { store.removeTodo(id: $0) }
                        )
                        .equatable()
                        .padding(.horizontal)
                        .onAppear {
                            store.ensureLoaded(index: index)
                        }

                        Divider()
                    }
                }
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Todo")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Takes an optional `Todo`: `nil` means "this index isn't loaded yet" and draws a placeholder.
/// Both states are pinned to `Self.rowHeight` so a row swapping between them never changes the
/// list's content height.
private struct TodoRowView: View, Equatable {
    static let rowHeight: CGFloat = 44

    let todo: Todo?
    let onToggle: (String) -> Void
    let onDelete: (String) -> Void

    static func == (lhs: TodoRowView, rhs: TodoRowView) -> Bool {
        lhs.todo == rhs.todo
    }

    var body: some View {
        Group {
            if let todo {
                // Height is text-driven now: a wrapped title makes this row taller than the
                // placeholder it replaces, which is the case being tested.
                loadedRow(todo)
                    .padding(.vertical, 11)
            } else {
                placeholderRow
                    .frame(height: Self.rowHeight)
            }
        }
    }

    private func loadedRow(_ todo: Todo) -> some View {
        HStack {
            Button {
                onToggle(todo.id)
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.plain)

            Text(todo.title)
                .strikethrough(todo.isDone)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onDelete(todo.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }

    private var placeholderRow: some View {
        HStack {
            Image(systemName: "circle")
                .foregroundStyle(.quaternary)

            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(width: 160, height: 12)

            Spacer()
        }
    }
}
