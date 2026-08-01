import AppDomain
import Foundation
import GeneratorCore
import SwiftUI

public struct ArticleEditorContent: View {
    let isDocumentOpen: Bool
    let title: Binding<String>
    let slug: Binding<String>
    let author: Binding<String>
    let emphasis: Binding<Emphasis>
    let draft: Binding<Bool>
    let number: Binding<Int>
    let published: Binding<PublicationDate?>
    let tags: [Tag]
    let allTags: [Tag]
    let brainstorming: Binding<String>
    let blocks: [EditableBlock]
    let allBlockKinds: [ContentBlockKind]
    let allSummaries: [ArticleSummary]
    let hasUnsavedChanges: Bool
    let isConfirmingDiscardOpen: Binding<Bool>
    let isConfirmingRevert: Binding<Bool>
    let canUndo: Bool
    let canRedo: Bool
    let isSaving: Bool
    let saveError: String?
    let conflict: ExternalChangeState
    let isBuilding: Bool
    let buildStatus: String?
    let onToggleTag: (Tag) -> Void
    let onAddBlock: (ContentBlockKind, Int) -> Void
    let onRemoveBlock: (UUID) -> Void
    let onMoveBlocks: (IndexSet, Int) -> Void
    let onUpdateBlock: (UUID, ContentBlock) -> Void
    let onSave: () -> Void
    let onRequestRevert: () -> Void
    let onRevert: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onConfirmDiscardAndOpen: () -> Void
    let onKeepMine: () -> Void
    let onReloadTheirs: () -> Void
    let onBuild: () -> Void
    let onRun: () -> Void
    let onOpenChat: () -> Void

    public var body: some View {
        if !isDocumentOpen {
            ContentUnavailableView("No Article Open", systemImage: "doc.text", description: Text("Choose an article from the sidebar."))
        } else {
            Form {
                if case .conflict = conflict {
                    conflictBanner
                }
                metadataSection
                brainstormingSection
                tagsSection
                blocksSection
            }
            .formStyle(.grouped)
            .navigationTitle(title.wrappedValue.isEmpty ? "Untitled" : title.wrappedValue)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) {
                if let saveError {
                    Text(saveError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                }
            }
            .confirmationDialog(
                "Revert all unsaved changes?",
                isPresented: isConfirmingRevert,
                titleVisibility: .visible
            ) {
                Button("Revert Changes", role: .destructive, action: onRevert)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This discards every edit made since the last save and can't be undone.")
            }
            .confirmationDialog(
                "Discard unsaved changes and open the other article?",
                isPresented: isConfirmingDiscardOpen,
                titleVisibility: .visible
            ) {
                Button("Discard and Open", role: .destructive, action: onConfirmDiscardAndOpen)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This article has unsaved changes. Switching now discards them — save first if you want to keep them.")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                onSave()
            } label: {
                if isSaving {
                    ProgressView()
                } else {
                    Label(hasUnsavedChanges ? "Save*" : "Save", systemImage: "square.and.arrow.down")
                }
            }
            .disabled(isSaving || !hasUnsavedChanges)
            .keyboardShortcut("s", modifiers: .command)
        }
        ToolbarItem(placement: .automatic) {
            Button(action: onUndo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!canUndo)
            .keyboardShortcut("z", modifiers: .command)
        }
        ToolbarItem(placement: .automatic) {
            Button(action: onRedo) {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        ToolbarItem(placement: .automatic) {
            Button(role: .destructive, action: onRequestRevert) {
                // Distinct from Undo's icon on purpose — Revert jumps all the way back
                // to the last save in one shot, not one step back.
                Label("Revert Changes", systemImage: "arrow.counterclockwise")
            }
            .disabled(!hasUnsavedChanges)
        }
        ToolbarItem(placement: .automatic) {
            Button {
                onBuild()
            } label: {
                if isBuilding {
                    ProgressView()
                } else {
                    Label("Build", systemImage: "hammer")
                }
            }
            .disabled(isBuilding)
            .help(buildStatus ?? "Generate the full site")
            .keyboardShortcut("b", modifiers: .command)
        }
        ToolbarItem(placement: .automatic) {
            Button {
                onRun()
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            .disabled(!isDocumentOpen)
            .help("Generate this article and open it in the browser")
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    private var conflictBanner: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("This file changed on disk while you were editing it.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                HStack {
                    Button("Keep Mine", role: .destructive, action: onKeepMine)
                    Button("Reload Theirs", action: onReloadTheirs)
                }
            }
        }
    }

    private var metadataSection: some View {
        Section("Metadata") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PasteAwareTextEditor(
                    text: title,
                    fontName: SiteTypography.headingFontName,
                    fontSize: SiteTypography.titleSize,
                    disablesNewlines: true,
                    isLinkAware: false
                )
            }
            TextField("Slug", text: slug)
            TextField("Author", text: author)
            Picker("Emphasis", selection: emphasis) {
                Text("Text").tag(Emphasis.text)
                Text("Video").tag(Emphasis.video)
            }
            Toggle("Draft", isOn: draft)
            Stepper("Number: \(number.wrappedValue)", value: number, in: 0...999)
            publishedField
        }
    }

    private var publishedField: some View {
        let isPublished = Binding<Bool>(
            get: { published.wrappedValue != nil },
            set: { enabled in
                published.wrappedValue = enabled ? (published.wrappedValue ?? todayPublicationDate()) : nil
            }
        )
        return VStack(alignment: .leading) {
            Toggle("Published", isOn: isPublished)
            if published.wrappedValue != nil {
                DatePicker(
                    "Date",
                    selection: Binding<Date>(
                        get: { (published.wrappedValue ?? todayPublicationDate()).asDate },
                        set: { published.wrappedValue = PublicationDate(date: $0) }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()
            }
        }
    }

    private var tagsSection: some View {
        Section("Tags") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sortedTags, id: \.self) { tag in
                        TagToggleChip(tag: tag, isSelected: tags.contains(tag)) {
                            onToggleTag(tag)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var sortedTags: [Tag] {
        allTags.sorted { $0.rawValue < $1.rawValue }
    }

    private var blocksSection: some View {
        Section("Blocks") {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                BlockRow(
                    block: block,
                    allSummaries: allSummaries,
                    allBlockKinds: allBlockKinds,
                    isFirst: index == 0,
                    isLast: index == blocks.count - 1,
                    onUpdate: { onUpdateBlock(block.id, $0) },
                    onRemove: { onRemoveBlock(block.id) },
                    onMoveUp: { onMoveBlocks(IndexSet(integer: index), max(index - 1, 0)) },
                    onMoveDown: { onMoveBlocks(IndexSet(integer: index), min(index + 2, blocks.count)) },
                    onAddBefore: { onAddBlock($0, index) },
                    onAddAfter: { onAddBlock($0, index + 1) }
                )
            }
            .onMove(perform: onMoveBlocks)
            .onDelete { offsets in
                for index in offsets { onRemoveBlock(blocks[index].id) }
            }

            Menu {
                ForEach(allBlockKinds) { kind in
                    Button(kind.displayName) { onAddBlock(kind, blocks.count) }
                }
            } label: {
                Label("Add Block", systemImage: "plus")
            }
        }
    }

    /// Personal notes, never rendered to the generated site — monospaced so pasted code
    /// snippets don't look confusing, but otherwise a plain text box: no syntax colour,
    /// no paste-aware link handling, no contextual menu.
    private var brainstormingSection: some View {
        // The assistant reads/writes THIS article's Brainstorming — so it's opened from
        // here, scoped to the article that's actually open, not from a top-level "app"
        // toolbar button unrelated to any particular article.
        Section {
            PasteAwareTextEditor(
                text: brainstorming,
                isMonospace: true,
                fontSize: SiteTypography.codeSize,
                isLinkAware: false
            )
        } header: {
            HStack {
                Text("Brainstorming")
                Spacer()
                Button(action: onOpenChat) {
                    Label("Ask Assistant", systemImage: "apple.intelligence")
                }
                .buttonStyle(.plain)
                .font(.footnote)
            }
        }
    }
}

private func todayPublicationDate() -> PublicationDate {
    // A reasonable default when a user enables "Published" for the first time; they
    // are expected to adjust it, same as hand-typing a date when writing a new article.
    PublicationDate(year: 2026, month: 1, day: 1)
}

/// A fixed Gregorian/UTC calendar for `PublicationDate ⇄ Date` conversion — deliberately
/// not `Calendar.current` (which reads the device's locale/region), since a UTC calendar
/// makes the conversion a pure function of the y/m/d values, with no ambient dependency
/// and no timezone-driven date-shifting near midnight.
private let publicationDateCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
}()

private extension PublicationDate {
    /// For binding to `DatePicker`, which only speaks `Date`.
    var asDate: Date {
        publicationDateCalendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    init(date: Date) {
        let components = publicationDateCalendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }
}

private struct TagToggleChip: View {
    let tag: Tag
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Text("#\(tag.rawValue)")
                .font(.callout)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct BlockRow: View {
    let block: EditableBlock
    let allSummaries: [ArticleSummary]
    let allBlockKinds: [ContentBlockKind]
    let isFirst: Bool
    let isLast: Bool
    let onUpdate: (ContentBlock) -> Void
    let onRemove: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onAddBefore: (ContentBlockKind) -> Void
    let onAddAfter: (ContentBlockKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(kindLabel)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                addBlockMenu(help: "Add block above", onAdd: onAddBefore)
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(isFirst)
                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(isLast)
                addBlockMenu(help: "Add block below", onAdd: onAddAfter)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
            content
        }
        .padding(.vertical, 4)
    }

    private func addBlockMenu(help: String, onAdd: @escaping (ContentBlockKind) -> Void) -> some View {
        Menu {
            ForEach(allBlockKinds) { kind in
                Button(kind.displayName) { onAdd(kind) }
            }
        } label: {
            Image(systemName: "plus")
        }
        .help(help)
    }

    private var kindLabel: String {
        switch block.block {
        case .heading: "Heading"
        case .paragraph: "Paragraph"
        case .list: "List"
        case .image: "Image"
        case .video: "Video"
        case .code: "Code"
        case .equation: "Equation (read-only in v1)"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch block.block {
        case .heading(let level, let text):
            Picker("Level", selection: Binding(
                get: { level },
                set: { onUpdate(.heading(level: $0, text: text)) }
            )) {
                Text("Section").tag(HeadingLevel.section)
                Text("Subsection").tag(HeadingLevel.subsection)
            }
            .pickerStyle(.segmented)
            PasteAwareTextEditor(
                text: Binding(
                    get: { text },
                    set: { onUpdate(.heading(level: level, text: $0)) }
                ),
                fontName: SiteTypography.headingFontName,
                fontSize: level == .section ? SiteTypography.sectionHeadingSize : SiteTypography.subsectionHeadingSize,
                disablesNewlines: true,
                isLinkAware: false
            )

        case .paragraph(let text):
            PasteAwareTextEditor(
                text: Binding(
                    get: { text },
                    set: { onUpdate(.paragraph($0)) }
                ),
                allSummaries: allSummaries,
                disablesNewlines: true
            )

        case .list(let items, let bullet):
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                TextField("Item \(index + 1)", text: Binding(
                    get: { item },
                    set: { newValue in
                        var newItems = items
                        newItems[index] = newValue
                        onUpdate(.list(items: newItems, bullet: bullet))
                    }
                ))
                .font(SiteTypography.body)
            }
            HStack {
                Button("Add item") { onUpdate(.list(items: items + [""], bullet: bullet)) }
                if items.count > 1 {
                    Button("Remove last") { onUpdate(.list(items: Array(items.dropLast()), bullet: bullet)) }
                }
            }
            .font(.caption)
            TextField("Bullet (optional, e.g. ✅)", text: Binding(
                get: { bullet ?? "" },
                set: { onUpdate(.list(items: items, bullet: $0.isEmpty ? nil : $0)) }
            ))

        case .image(let url, let altText):
            TextField("URL", text: Binding(get: { url }, set: { onUpdate(.image(url: $0, altText: altText)) }))
            TextField("Alt text", text: Binding(get: { altText }, set: { onUpdate(.image(url: url, altText: $0)) }))

        case .video(let url, let caption):
            TextField("URL", text: Binding(get: { url }, set: { onUpdate(.video(url: $0, caption: caption)) }))
            TextField("Caption (optional)", text: Binding(
                get: { caption ?? "" },
                set: { onUpdate(.video(url: url, caption: $0.isEmpty ? nil : $0)) }
            ))
            .font(SiteTypography.caption)
            .foregroundStyle(.secondary)

        case .code(let language, let source):
            PasteAwareTextEditor(
                text: Binding(get: { source }, set: { onUpdate(.code(language: language, source: $0)) }),
                isMonospace: true,
                isSyntaxHighlighted: true,
                fontSize: SiteTypography.codeSize,
                allSummaries: allSummaries,
                isLinkAware: false
            )

        case .equation:
            Text("Equation blocks aren't editable yet — this one is preserved untouched on save.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

}
