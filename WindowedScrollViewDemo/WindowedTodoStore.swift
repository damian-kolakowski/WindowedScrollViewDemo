import Foundation

/// Wraps the plain `TodoDatabase` class in an `actor` so calls into it are automatically
/// serialized — no two calls ever run concurrently against the same sqlite3 connection.
actor WindowedDatabaseAccess {
    private let database: TodoDatabase

    init(database: TodoDatabase) {
        self.database = database
    }

    func fetchPage(limit: Int, offset: Int) -> [Todo] {
        database.fetchPage(limit: limit, offset: offset)
    }

    func rowCount() -> Int {
        database.rowCount()
    }

    func addTodo(title: String) {
        database.addTodo(title: title)
    }

    func toggleDone(id: String) {
        database.toggleDone(id: id)
    }

    func delete(id: String) {
        database.delete(id: id)
    }
}

/// Index-addressed sparse cache rather than a contiguous sliding array: `items[i]` is the row
/// at absolute position `i` if its page happens to be resident, or `nil` if it isn't loaded.
/// `totalCount` comes from `rowCount()` up front, so the view renders a fixed-size
/// `ForEach(0..<totalCount)` and shows a placeholder wherever an index isn't loaded.
///
/// That fixed range is the point. Evicting a page removes rows from `items`, but it does not
/// remove them from the list — index `i` still occupies the same slot, just as a placeholder.
/// The content height never changes, so the scroll offset keeps pointing at the same place and
/// nothing shifts under the user.
@MainActor
final class WindowedTodoStore: ObservableObject {
    private let databaseAccess: WindowedDatabaseAccess
    let pageSize = 30
    private let maxLoadedPages = 3 // 90 items resident at once

    @Published private(set) var items: [Int: Todo] = [:]
    @Published private(set) var totalCount: Int = 0

    private var loadingPages: Set<Int> = []
    private var residentPages: Set<Int> = []

    init() {
        databaseAccess = WindowedDatabaseAccess(database: TodoDatabase())
        Task { await loadInitial() }
    }

    private func loadInitial() async {
        items = [:]
        loadingPages = []
        residentPages = []
        totalCount = await databaseAccess.rowCount()
        loadPage(containingIndex: 0)
    }

    /// Call from a row's `.onAppear`, whether that row is currently a placeholder or a loaded
    /// item, so the page containing that absolute index gets fetched if it isn't already.
    func ensureLoaded(index: Int) {
        guard items[index] == nil else { return }
        loadPage(containingIndex: index)
    }

    private func loadPage(containingIndex index: Int) {
        guard index >= 0, index < totalCount else { return }
        let pageIndex = index / pageSize
        guard !loadingPages.contains(pageIndex) else { return }
        loadingPages.insert(pageIndex)

        Task {
            let offset = pageIndex * pageSize
            let page = await databaseAccess.fetchPage(limit: pageSize, offset: offset)
            loadingPages.remove(pageIndex)
            residentPages.insert(pageIndex)

            // Mutate a local copy and assign once — `items` is @Published, so assigning inside
            // the loop would fire one publish per key and re-diff the whole range each time.
            var updated = items
            for (i, todo) in page.enumerated() {
                updated[offset + i] = todo
            }
            if residentPages.count > maxLoadedPages {
                // Evict whichever *other* resident page is farthest from the one just loaded;
                // that page is the reference point for where the user currently is.
                if let evicted = residentPages
                    .filter({ $0 != pageIndex })
                    .max(by: { abs($0 - pageIndex) < abs($1 - pageIndex) }) {
                    residentPages.remove(evicted)
                    let evictedStart = evicted * pageSize
                    for i in evictedStart..<(evictedStart + pageSize) {
                        updated.removeValue(forKey: i)
                    }
                }
            }
            items = updated
        }
    }

    func addTodo(title: String) {
        Task {
            await databaseAccess.addTodo(title: title)
            // New items get the lowest sortOrder (prepended), so every existing absolute index
            // shifts by one and the sparse cache can't be patched in place. Reset and reload.
            await loadInitial()
        }
    }

    func toggleTodo(id: String) {
        guard let index = items.first(where: { $0.value.id == id })?.key else { return }
        var todo = items[index]!
        todo.isDone.toggle()
        items[index] = todo
        Task {
            await databaseAccess.toggleDone(id: id)
        }
    }

    func removeTodo(id: String) {
        Task {
            await databaseAccess.delete(id: id)
            // Deleting shifts every subsequent absolute index down by one — reset and reload
            // rather than trying to patch the sparse cache.
            await loadInitial()
        }
    }
}
