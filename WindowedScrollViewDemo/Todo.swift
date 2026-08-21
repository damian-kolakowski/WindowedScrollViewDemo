import Foundation

struct Todo: Identifiable, Equatable, Hashable {
    let id: String
    var title: String
    var isDone: Bool
    var sortOrder: Double
}
