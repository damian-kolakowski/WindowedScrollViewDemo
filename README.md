# WindowedScrollViewDemo

A SwiftUI todo list backed by SQLite that keeps only a few pages of rows in memory at a time, loading them as you scroll. It demonstrates why a windowed list has to render a fixed `0..<totalCount` range rather than just the rows it happens to have loaded.

[interactive demo](https://damian-kolakowski.github.io/WindowedScrollViewDemo/windowed-loading-demo.html)

## The problem with rendering only what's loaded

The obvious approach is to back the list with a plain array of the rows currently in memory and iterate it directly:

```swift
@Published private(set) var items: [Todo] = []

ForEach(store.items) { todo in ... }
```

Scrolling to the bottom loads the next page and trims the oldest one, so `items` is replaced with an array that is longer at the tail and shorter at the head. From SwiftUI's side there is no append and no separate trim; `items` is simply assigned a different array.

That replacement is what breaks scrolling. The scroll offset is a distance in points from the top of the content, and it is left untouched. But the rows that used to occupy those points were dropped from the head, so the same offset now lands a page deeper into the table. The list appears to leap forward even though nothing scrolled, no offset was set, and no animation ran.

## The fix: a fixed range over a sparse cache

Instead, keep the rows in an index-addressed cache and tell the view how long the list really is:

```swift
@Published private(set) var items: [Int: Todo] = [:]
@Published private(set) var totalCount: Int = 0

ForEach(0..<store.totalCount, id: \.self) { index in
    TodoRowView(todo: store.items[index])   // nil when that page isn't resident
        .onAppear { store.ensureLoaded(index: index) }
}
```

`items[i]` holds the row at absolute position `i` when its page is resident and `nil` when it isn't. Evicting a page still frees the memory, but it no longer shortens the list: index `i` keeps its slot and draws a placeholder instead.

This is what makes the content offset behave. Because the range is `0..<totalCount`, the content height is fixed from the first frame and never changes as pages load and evict. The offset keeps measuring against the same content, so the rows under the viewport stay exactly where they were, and the scroll indicator reflects the real size of the table rather than the size of the window.

## Loading

`.onAppear` fires only for rows the `LazyVStack` actually instantiates, which is what makes it a usable signal for where the user is. Every row calls `ensureLoaded(index:)`, placeholder or not; the store maps the index to a page, skips it if that page is already loaded or in flight, and otherwise fetches it. Three pages stay resident at a time, and the page evicted is the one farthest from the page just loaded, so the pages nearest the user survive.
